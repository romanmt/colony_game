defmodule ColonyGame.Repo.Migrations.CreateGameStates do
  use Ecto.Migration

  def change do
    create table(:game_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tick_count, :integer, default: 0, null: false
      add :food_available, :integer, default: 100, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
