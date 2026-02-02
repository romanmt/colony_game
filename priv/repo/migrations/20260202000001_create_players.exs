defmodule ColonyGame.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :food, :integer, default: 100, null: false
      add :water, :integer, default: 100, null: false
      add :energy, :integer, default: 100, null: false
      add :state, :string, default: "idle", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:players, [:session_id])
  end
end
