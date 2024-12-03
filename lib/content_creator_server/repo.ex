defmodule Iris.Repo do
  use Ecto.Repo,
    otp_app: :iris,
    adapter: Ecto.Adapters.Postgres
end
