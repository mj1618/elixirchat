defmodule Elixirchat.Repo do
  use Ecto.Repo,
    otp_app: :elixirchat,
    adapter: Ecto.Adapters.Postgres
end
