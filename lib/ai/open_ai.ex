defmodule Iris.OpenAI do
  # alias Iris.OpenAI.StreamClient

  @behaviour Iris.AI.ChatCompletion

  @api_key "api_key"
  @organization_id "iris_org_id"
  @base_url "https://api.openai.com"

  use Supervisor

  require Logger

  def start_link([]) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    children = [StreamClient]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @impl true
  def complete_chat(payload, options \\ []) do
    req_headers = [{"content-type", "application/json"}]
    req_path = "/v1/chat/completions"
    req_options = Keyword.put_new(options, :timeout, 60_000)
    req_body = Jason.encode!(payload)

    case request("POST", req_path, req_headers, req_body, req_options) do
      {:ok, %{"choices" => [%{"message" => message}]}} ->
        {:ok, Map.fetch!(message, "content")}

      :error ->
        :error
    end
  end

  @impl true
  def stream_chat do
    IO.puts("Streaming chat")
  end

  # @impl true
  # def stream_chat(payload, options \\ [], receiver \\ self()) do
  #   req_headers = [{"content-type", "application/json"}]
  #   req_path = "/v1/chat/completions"
  #   req_options = Keyword.put_new(options, :timeout, 60_000)

  #   req_body =
  #     payload
  #     |> Map.put(:stream, true)
  #     |> Jason.encode!()

  #   request_stream(receiver, "POST", req_path, req_headers, req_body, req_options)
  # end

  def complete_text(payload) do
    req_headers = [{"content-type", "application/json"}]
    req_body = Jason.encode!(payload)

    case request("POST", "/v1/chat/completions", req_headers, req_body, timeout: 30_000) do
      {:ok, %{"choices" => [choice]}} ->
        %{"message" => %{"content" => content}} = choice
        {:ok, content}

      :error ->
        :error
    end
  end

  # def stream_text(payload, options \\ [], receiver \\ self()) do
  #   req_path = "/v1/completions"
  #   req_headers = [{"content-type", "application/json"}]
  #   req_body = Jason.encode!(payload)
  #   req_options = Keyword.put_new(options, :timeout, 3_000)

  #   request_stream(receiver, "POST", req_path, req_headers, req_body, req_options)
  # end

  def text_to_image(prompt) do
    req_headers = [{"content-type", "application/json"}]

    req_body =
      Jason.encode!(%{
        model: "dall-e-3",
        n: 1,
        prompt: prompt,
        size: "1024x1024"
      })

    case request("POST", "/v1/images/generations", req_headers, req_body, timeout: 30_000) do
      {:ok, payload} ->
        %{"data" => [%{"url" => image_url}]} = payload
        {:ok, image_url}

      :error ->
        :error
    end
  end

  def request(method, path, headers, body, req_options) do
    headers = build_req_headers(headers)
    req_url = @base_url <> path

    case Iris.HTTP.Client.request(method, req_url, headers, body, req_options) do
      {:ok, 200, _, resp_body} ->
        {:ok, Jason.decode!(resp_body)}

      {:ok, status, _, resp_body} ->
        Logger.error("Received unexpected response: " <> inspect({status, resp_body}))
        :error

      {:error, _reason} ->
        :error
    end
  end

  # defp request_stream(receiver, method, path, headers, body, req_options) do
  #   headers = build_req_headers(headers)

  #   case StreamClient.request(receiver, method, path, headers, body, req_options) do
  #     {:ok, 200, _, req_ref} ->
  #       {:ok, req_ref}

  #     {:ok, status, _, resp_body} ->
  #       Logger.error("Received unexpected response: " <> inspect({status, resp_body}))
  #       :error

  #     {:error, _reason} ->
  #       :error
  #   end
  # end

  defp build_req_headers(headers) do
    [
      {"authorization", "Bearer " <> @api_key},
      {"OpenAI-Organization", @organization_id},
      {"accept", "application/json"}
    ] ++ headers
  end
end
