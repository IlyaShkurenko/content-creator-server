# defmodule Iris.HTTP.Connection do
#   @behaviour :gen_statem

#   require Logger

#   @enforce_keys [:server, :responder_module, :ping_interval]
#   defstruct @enforce_keys ++ [requests: %{}]

#   @http_client Application.compile_env(
#                  :iris,
#                  [Iris.HTTP.Server, :http_client],
#                  Iris.HTTP.Standard
#                )

#   def start_link(options) do
#     name = {:local, Keyword.fetch!(options, :name)}

#     :gen_statem.start_link(name, __MODULE__, options, [])
#   end

#   def request(server, receiver, method, path, headers, body, options) do
#     {timeout, options} = Keyword.pop(options, :timeout, 5000)

#     :gen_statem.call(
#       server,
#       {:request, receiver, {method, path, headers, body, options}},
#       timeout
#     )
#   end

#   @impl true
#   def callback_mode(), do: [:handle_event_function, :state_enter]

#   @impl true
#   def init(options) do
#     data = %__MODULE__{
#       server: Keyword.fetch!(options, :server),
#       ping_interval: Keyword.get(options, :ping_interval, 5_000),
#       responder_module: Keyword.fetch!(options, :responder_module)
#     }

#     actions = [{:next_event, :internal, :connect}]
#     {:ok, :disconnected, data, actions}
#   end

#   @impl true
#   def handle_event(:enter, old_state, new_state, data) do
#     handle_enter(old_state, new_state, data)
#   end

#   def handle_event(:internal, :connect, :disconnected, data) do
#     %__MODULE__{server: {scheme, host, port}} = data
#     transport_opts = [timeout: 1_000]

#     case @http_client.connect(scheme, host, port, transport_opts: transport_opts) do
#       {:ok, conn} ->
#         {:next_state, {:connected, conn}, data}

#       {:error, reason} ->
#         Logger.error("Could not connect to remote server: " <> Exception.message(reason))

#         # TODO: Improve backoff.
#         backoff_seconds = 1_000
#         actions = [{{:timeout, :reconnect}, backoff_seconds, nil}]
#         {:keep_state_and_data, actions}
#     end
#   end

#   def handle_event(
#         :internal,
#         {:stream_request_body, {request_ref, body, position}} = action,
#         {:connected, conn},
#         data
#       ) do
#     window_size = Mint.HTTP2.get_window_size(conn, {:request, request_ref})

#     if window_size == 0 do
#       {:keep_state_and_data, [{{:timeout, :retry_action}, 100, action}]}
#     else
#       <<_skip::bytes-size(position), rest::binary>> = body

#       {chunks, actions} =
#         case rest do
#           <<chunk::bytes-size(window_size), _::1-bytes, _::binary>> ->
#             actions = [stream_request_action(request_ref, body, position + window_size)]
#             {[chunk], actions}

#           chunk ->
#             {[chunk, :eof], []}
#         end

#       chunk_result =
#         Enum.reduce_while(chunks, {:ok, conn}, fn chunk, {:ok, conn} ->
#           case Mint.HTTP2.stream_request_body(conn, request_ref, chunk) do
#             {:ok, conn} ->
#               {:cont, {:ok, conn}}

#             {:error, conn, reason} ->
#               {:halt, {:error, conn, reason}}
#           end
#         end)

#       case chunk_result do
#         {:ok, conn} ->
#           {:next_state, {:connected, conn}, data, actions}

#         {:error, _conn, reason} ->
#           Logger.error(
#             "Encountered error while streaming request body: " <> Exception.message(reason)
#           )

#           %__MODULE__{requests: requests} = data

#           Enum.each(requests, fn {_req_ref, %{from: from}} ->
#             :gen_statem.reply(from, {:error, :disconnected})
#           end)

#           {:next_state, :disconnected, data}
#       end
#     end
#   end

#   def handle_event({:timeout, :reconnect}, _, :disconnected, _data) do
#     actions = [{:next_event, :internal, :connect}]
#     {:keep_state_and_data, actions}
#   end

#   def handle_event({:timeout, :retry_action}, event, _, _data) do
#     {:keep_state_and_data, [{:next_event, :internal, event}]}
#   end

#   def handle_event(:state_timeout, :connect, :disconnected, _data) do
#     {:keep_state_and_data, [{:next_event, :internal, :connect}]}
#   end

#   def handle_event(:state_timeout, :check_alive, {:connected, conn}, data) do
#     if @http_client.open?(conn) do
#       @http_client.ping(conn)
#       {:keep_state_and_data, [check_alive_action(data)]}
#     else
#       {:next_state, :disconnected, data}
#     end
#   end

#   def handle_event({:call, from}, {:request, receiver, request}, state, data) do
#     handle_request(request, {from, receiver}, state, data)
#   end

#   def handle_event(:info, message, {:connected, conn}, data) do
#     case @http_client.stream(conn, message) do
#       :unknown ->
#         Logger.error("Received unknown message: " <> inspect(message))
#         :keep_state_and_data

#       {:ok, conn, responses} ->
#         data = Enum.reduce(responses, data, &process_response/2)
#         {:next_state, {:connected, conn}, data}

#       {:error, _conn, _error, responses} ->
#         data = Enum.reduce(responses, data, &process_response/2)
#         {:next_state, :disconnected, data}
#     end
#   end

#   defp handle_enter({:connected, conn}, :disconnected, data) do
#     %__MODULE__{requests: requests} = data

#     Enum.each(requests, fn {_req_ref, %{from: from}} ->
#       :gen_statem.reply(from, {:error, :disconnected})
#     end)

#     @http_client.close(conn)

#     data = %__MODULE__{data | requests: %{}}
#     actions = [{:state_timeout, 0, :connect}]
#     {:keep_state, data, actions}
#   end

#   defp handle_enter(_, {:connected, _conn}, data) do
#     {:keep_state_and_data, [check_alive_action(data)]}
#   end

#   defp handle_enter(_, _, _), do: :keep_state_and_data

#   defp handle_request(_request, {from, _receiver}, :disconnected, _data) do
#     actions = [{:reply, from, {:error, :disconnected}}]
#     {:keep_state_and_data, actions}
#   end

#   defp handle_request(request, {from, receiver}, {:connected, conn}, data) do
#     {method, req_path, req_headers, req_body, _req_options} = request
#     %__MODULE__{requests: requests} = data

#     case @http_client.request(conn, method, req_path, req_headers, :stream) do
#       {:ok, conn, request_ref} ->
#         data = %__MODULE__{
#           data
#           | requests: Map.put(requests, request_ref, new_request(from, receiver))
#         }

#         actions = [stream_request_action(request_ref, req_body, 0)]
#         {:next_state, {:connected, conn}, data, actions}

#       {:error, _conn, error} ->
#         Logger.error("Encountered error while making requests: " <> Exception.message(error))

#         :gen_statem.reply(from, {:error, error})

#         # It may feel too defensive we always reconnect when request errors happen, instead of handling
#         # case by case. However, until we are fully aware of such cases, let us always reconnect.
#         {:next_state, :disconnected, data}
#     end
#   end

#   defp new_request(from, receiver) do
#     %{from: from, receiver: receiver, status: nil, headers: nil, body: ""}
#   end

#   defp process_response({tag, request_ref, _} = message, data)
#        when tag in [:status, :headers, :data] do
#     %{requests: requests, responder_module: responder_module} = data

#     case requests do
#       %{^request_ref => %{from: from} = request} ->
#         replier = &:gen_statem.reply(from, &1)
#         request = responder_module.handle_message(message, request, replier)
#         put_in(data.requests[request_ref], request)

#       _ ->
#         Logger.error("Received unknown response message")
#         data
#     end
#   end

#   defp process_response({:done, request_ref}, data) do
#     %{responder_module: responder_module} = data
#     {request, data} = pop_in(data.requests[request_ref])

#     replier = &:gen_statem.reply(request.from, &1)
#     responder_module.handle_message({:done, request_ref}, request, replier)

#     data
#   end

#   defp check_alive_action(data) do
#     {:state_timeout, data.ping_interval, :check_alive}
#   end

#   defp stream_request_action(request_ref, body, start) do
#     {:next_event, :internal, {:stream_request_body, {request_ref, body, start}}}
#   end
# end
