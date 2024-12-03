defmodule Iris.HTTP.SimpleClient do
  @behaviour Iris.HTTP.Client

  @impl true
  def request(method, req_url, req_headers, req_body \\ nil, options \\ []) do
    %URI{path: req_path, query: req_query} = uri = URI.parse(req_url)
    req_path = URI.to_string(%URI{path: req_path, query: req_query})
    timeout = Keyword.get(options, :timeout, 5_000)

    with {:ok, conn} <- connect(uri),
         {:ok, conn, request_ref} <-
           send_request(conn, method, req_path, req_headers, req_body),
         {:ok, conn, {status, headers, body}} <-
           receive_response([], {nil, [], []}, conn, request_ref, timeout) do
      Mint.HTTP1.close(conn)
      {:ok, status, headers, body}
    else
      {:error, reason} ->
        {:error, reason}

      {:error, conn, reason} ->
        Mint.HTTP1.close(conn)
        {:error, reason}
    end
  end

  defp connect(%URI{scheme: scheme, host: host, port: port}) when scheme in ["http", "https"] do
    with {:error, reason} <-
           Mint.HTTP1.connect(String.to_existing_atom(scheme), host, port, mode: :passive) do
      {:error, reason}
    end
  end

  defp send_request(conn, method, path, headers, body) do
    Mint.HTTP1.request(conn, method, path, headers, body)
  end

  defp receive_response([], result, conn, request_ref, timeout) do
    case Mint.HTTP1.recv(conn, 0, timeout) do
      {:ok, conn, entries} ->
        receive_response(entries, result, conn, request_ref, timeout)

      {:error, conn, reason, _} ->
        {:error, conn, reason}
    end
  end

  defp receive_response([entry | entries], {status, headers, data}, conn, request_ref, timeout) do
    case entry do
      {:status, ^request_ref, value} ->
        receive_response(entries, {value, headers, data}, conn, request_ref, timeout)

      {:headers, ^request_ref, value} ->
        receive_response(entries, {status, headers ++ value, data}, conn, request_ref, timeout)

      {:data, ^request_ref, value} ->
        receive_response(entries, {status, headers, [value | data]}, conn, request_ref, timeout)

      {:done, ^request_ref} ->
        body = data |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, conn, {status, headers, body}}
    end
  end
end
