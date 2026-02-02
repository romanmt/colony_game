defmodule ColonyGame.Repo.Migrations.AddLastSeenToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :last_seen, :utc_datetime, null: true
    end

    # Set initial value to updated_at for existing records
    execute "UPDATE players SET last_seen = updated_at", ""
  end
end
