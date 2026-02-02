defmodule ColonyGame.Game.PlayerPresence do
  @moduledoc """
  Tracks active players and their activities without exposing identifying information.

  This GenServer maintains anonymous presence data for all connected players,
  broadcasting aggregated counts and activity indicators to support social
  deduction gameplay without revealing individual player identities.
  """
  use GenServer

  alias Phoenix.PubSub

  @pubsub ColonyGame.PubSub
  @presence_topic "colony:presence"

  # Player state without identifying info - just activity
  defstruct players: %{},
            # Aggregate counts for UI
            total_count: 0,
            foraging_count: 0,
            idle_count: 0

  ## Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc """
  Register a new player. Called when a player joins.
  """
  def register_player(player_id) do
    GenServer.call(__MODULE__, {:register, player_id})
  end

  @doc """
  Unregister a player. Called when a player disconnects.
  """
  def unregister_player(player_id) do
    GenServer.cast(__MODULE__, {:unregister, player_id})
  end

  @doc """
  Update a player's activity status.
  """
  def update_activity(player_id, activity) when activity in [:idle, :foraging] do
    GenServer.cast(__MODULE__, {:update_activity, player_id, activity})
  end

  @doc """
  Get current presence summary (anonymous aggregate data only).
  """
  def get_presence_summary do
    GenServer.call(__MODULE__, :get_summary)
  end

  @doc """
  Get the presence topic for PubSub subscriptions.
  """
  def presence_topic, do: @presence_topic

  ## GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, player_id}, _from, state) do
    if Map.has_key?(state.players, player_id) do
      # Already registered
      {:reply, :ok, state}
    else
      # Generate a random position for this player's dot (0.0 to 1.0 range)
      position = {random_position(), random_position()}

      new_players = Map.put(state.players, player_id, %{
        activity: :idle,
        position: position,
        joined_at: System.monotonic_time(:millisecond)
      })

      new_state = %{state |
        players: new_players,
        total_count: state.total_count + 1,
        idle_count: state.idle_count + 1
      }

      broadcast_presence_update(new_state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    summary = build_summary(state)
    {:reply, summary, state}
  end

  @impl true
  def handle_cast({:unregister, player_id}, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:noreply, state}

      player_data ->
        new_players = Map.delete(state.players, player_id)

        {idle_delta, foraging_delta} = activity_deltas(player_data.activity, :removed)

        new_state = %{state |
          players: new_players,
          total_count: max(0, state.total_count - 1),
          idle_count: max(0, state.idle_count + idle_delta),
          foraging_count: max(0, state.foraging_count + foraging_delta)
        }

        broadcast_presence_update(new_state)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:update_activity, player_id, new_activity}, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:noreply, state}

      player_data ->
        old_activity = player_data.activity

        if old_activity == new_activity do
          {:noreply, state}
        else
          updated_player = %{player_data | activity: new_activity}
          new_players = Map.put(state.players, player_id, updated_player)

          {idle_delta, foraging_delta} = activity_transition_deltas(old_activity, new_activity)

          new_state = %{state |
            players: new_players,
            idle_count: max(0, state.idle_count + idle_delta),
            foraging_count: max(0, state.foraging_count + foraging_delta)
          }

          broadcast_presence_update(new_state)
          {:noreply, new_state}
        end
    end
  end

  ## Private Helpers

  defp random_position do
    # Generate position between 0.15 and 0.85 to keep dots within visible area
    0.15 + :rand.uniform() * 0.7
  end

  defp activity_deltas(:idle, :removed), do: {-1, 0}
  defp activity_deltas(:foraging, :removed), do: {0, -1}
  defp activity_deltas(_, :removed), do: {0, 0}

  defp activity_transition_deltas(:idle, :foraging), do: {-1, 1}
  defp activity_transition_deltas(:foraging, :idle), do: {1, -1}
  defp activity_transition_deltas(_, _), do: {0, 0}

  defp build_summary(state) do
    # Build anonymous player dots list (just positions and activities, no IDs)
    player_dots = state.players
    |> Map.values()
    |> Enum.map(fn player_data ->
      %{
        position: player_data.position,
        activity: player_data.activity
      }
    end)

    %{
      total_count: state.total_count,
      foraging_count: state.foraging_count,
      idle_count: state.idle_count,
      player_dots: player_dots
    }
  end

  defp broadcast_presence_update(state) do
    summary = build_summary(state)
    PubSub.broadcast(@pubsub, @presence_topic, {:presence_update, summary})
  end
end
