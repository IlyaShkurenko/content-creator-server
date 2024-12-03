defmodule Iris.AWS.Client do
  @behaviour ExAws.Request.HttpClient

  def request(method, url, body, headers, http_opts) do
    method = method |> to_string() |> String.upcase()

    case Iris.HTTP.Client.request(method, url, headers, body, http_opts) do
      {:ok, status, headers, body} ->
        {:ok, %{status_code: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
