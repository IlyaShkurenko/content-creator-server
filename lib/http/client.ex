defmodule Iris.HTTP.Client do
  @callback request(
              method :: String.t(),
              url :: String.t(),
              headers :: Mint.Types.headers(),
              body :: iodata(),
              options :: keyword()
            ) :: {:ok, Mint.Types.status(), Mint.Types.headers(), iodata()}

  @http_client Application.compile_env(:iris, :http_client, Iris.HTTP.SimpleClient)

  defdelegate request(method, url, headers, body, options \\ []), to: @http_client
end
