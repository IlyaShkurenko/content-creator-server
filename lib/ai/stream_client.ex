# defmodule Iris.OpenAI.StreamClient do
#   alias Iris.Web.ServerSentEvent

#   def child_spec([]) do
#     options = [
#       name: __MODULE__,
#       responder_module: __MODULE__,
#       server: {:https, "api.openai.com", 443}
#     ]

#     %{
#       id: __MODULE__,
#       start: {Iris.HTTP.Connection, :start_link, [options]},
#       type: :worker
#     }
#   end

#   def request(receiver, method, path, headers \\ [], body \\ nil, options \\ []) do
#     options = Keyword.put(options, :responder_module, __MODULE__)

#     Iris.HTTP.Connection.request(__MODULE__, receiver, method, path, headers, body, options)
#   end

#   def handle_message({:status, _request_ref, status}, request, _replier) do
#     Map.put(request, :status, status)
#   end

#   def handle_message({:headers, request_ref, headers}, request, replier) do
#     request =
#       request
#       |> Map.put(:headers, headers)
#       |> Map.put(:sse?, sse?(headers))

#     if request.sse? do
#       %{status: status} = request

#       replier.({:ok, status, headers, request_ref})
#       Map.put(request, :parser_state, ServerSentEvent.new())
#     else
#       request
#     end
#   end

#   def handle_message({:data, request_ref, binary}, request, _replier) do
#     %{body: body, sse?: sse?} = request

#     request = Map.put(request, :body, [body | binary])

#     if sse? do
#       %{receiver: receiver, parser_state: parser_state} = request
#       {:ok, parser_state, events} = ServerSentEvent.parse(parser_state, binary)

#       events
#       |> Enum.flat_map(fn chunk ->
#         List.wrap(extract_chunk(chunk))
#       end)
#       |> Enum.group_by(fn {type, _value} -> type end, fn {_type, value} -> value end)
#       |> Enum.each(fn {type, values} ->
#         send_chunk_data(receiver, request_ref, type, values)
#       end)

#       request
#       |> Map.put(:parser_state, parser_state)
#     else
#       request
#     end
#   end

#   def handle_message({:done, request_ref}, request, replier) do
#     if request.sse? do
#       %{receiver: receiver, body: body} = request
#       send(receiver, {:stream, request_ref, {:done, IO.iodata_to_binary(body)}})
#     else
#       %{status: status, headers: headers, body: body} = request
#       replier.({:ok, status, headers, Jason.decode!(body)})
#     end

#     nil
#   end

#   defp send_chunk_data(receiver, request_ref, :function_partial, values) do
#     Enum.each(values, fn {index, id, name, arg} ->
#       send(receiver, {:stream, request_ref, {:function_partial, index, {id, name, arg}}})
#     end)
#   end

#   defp send_chunk_data(receiver, request_ref, :token, values) do
#     send(receiver, {:stream, request_ref, {:token, IO.iodata_to_binary(values)}})
#   end

#   defp send_chunk_data(receiver, request_ref, event_type, event_data) do
#     send(receiver, {:stream, request_ref, {event_type, event_data}})
#   end

#   defp extract_chunk_data(
#          "chat.completion.chunk",
#          %{"delta" => %{"tool_calls" => tool_calls}}
#        ) do
#     extract_tool_calls(tool_calls)
#   end

#   defp extract_chunk_data(
#          "chat.completion.chunk",
#          %{"delta" => %{"content" => token}}
#        )
#        when is_binary(token) do
#     {:token, token}
#   end

#   defp extract_chunk_data("text_completion", %{"text" => token}) do
#     {:token, token}
#   end

#   defp extract_chunk_data(_, _), do: nil

#   defp extract_chunk("data: " <> json) do
#     case Jason.decode(json) do
#       {:ok, %{"usage" => usage}} when is_map(usage) ->
#         extract_usage(usage)

#       {:ok, %{"object" => object_type, "choices" => [choice]}} ->
#         extract_chunk_data(object_type, choice)

#       {:error, _} ->
#         nil
#     end
#   end

#   defp extract_chunk(_), do: nil

#   defp sse?(headers) do
#     case get_header(headers, "content-type") do
#       [content_type] ->
#         match?(
#           {:ok, "text", "event-stream", _},
#           Plug.Conn.Utils.media_type(content_type)
#         )

#       _ ->
#         false
#     end
#   end

#   defp get_header(headers, key) do
#     for {^key, value} <- headers, do: value
#   end

#   defp extract_tool_calls([%{"function" => function, "index" => index} = tool_call]) do
#     {:function_partial, {index, tool_call["id"], function["name"], function["arguments"]}}
#   end

#   defp extract_tool_calls(_), do: nil

#   defp extract_usage(usage) do
#     %{"completion_tokens" => completion_tokens} = usage
#     # TODO: Extract data when it's used.
#     {:usage, %{token_count: completion_tokens}}
#   end
# end
