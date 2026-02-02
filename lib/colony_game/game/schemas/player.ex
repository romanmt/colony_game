defmodule ColonyGame.Game.Schemas.Player do
  @moduledoc """
  Ecto schema for player state persistence.

  Stores individual player data including resources, current state,
  and session information for reconnection handling.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :session_id, :string
    field :food, :integer, default: 100
    field :water, :integer, default: 100
    field :energy, :integer, default: 100
    field :state, :string, default: "idle"
    field :last_seen, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new player.
  """
  def create_changeset(player, attrs) do
    player
    |> cast(attrs, [:session_id, :food, :water, :energy, :state, :last_seen])
    |> validate_required([:session_id])
    |> validate_inclusion(:state, ["idle", "foraging"])
    |> validate_number(:food, greater_than_or_equal_to: 0)
    |> validate_number(:water, greater_than_or_equal_to: 0)
    |> validate_number(:energy, greater_than_or_equal_to: 0)
    |> put_last_seen()
    |> unique_constraint(:session_id)
  end

  @doc """
  Changeset for updating player state and resources.
  """
  def update_changeset(player, attrs) do
    player
    |> cast(attrs, [:food, :water, :energy, :state, :last_seen])
    |> validate_inclusion(:state, ["idle", "foraging"])
    |> validate_number(:food, greater_than_or_equal_to: 0)
    |> validate_number(:water, greater_than_or_equal_to: 0)
    |> validate_number(:energy, greater_than_or_equal_to: 0)
    |> put_last_seen()
  end

  defp put_last_seen(changeset) do
    put_change(changeset, :last_seen, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
