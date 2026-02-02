defmodule ColonyGame.Game.Schemas.GameState do
  @moduledoc """
  Ecto schema for global game state persistence.

  Stores shared game state including tick count and available resources
  that are shared across all players.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_states" do
    field :tick_count, :integer, default: 0
    field :food_available, :integer, default: 100

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new game state.
  """
  def create_changeset(game_state, attrs) do
    game_state
    |> cast(attrs, [:tick_count, :food_available])
    |> validate_number(:tick_count, greater_than_or_equal_to: 0)
    |> validate_number(:food_available, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating game state (typically on each tick).
  """
  def update_changeset(game_state, attrs) do
    game_state
    |> cast(attrs, [:tick_count, :food_available])
    |> validate_number(:tick_count, greater_than_or_equal_to: 0)
    |> validate_number(:food_available, greater_than_or_equal_to: 0)
  end
end
