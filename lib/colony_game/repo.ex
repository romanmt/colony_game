defmodule ColonyGame.Repo do
  use Ecto.Repo,
    otp_app: :colony_game,
    adapter: Ecto.Adapters.Postgres
end
