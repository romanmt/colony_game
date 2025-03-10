defmodule ColonyGame.Game.PlayerProcess do
  use GenServer
  import Logger

  alias ColonyGame.Game.Rules

  defmodule PlayerState do
    defstruct [
      :player_id,
      :rules  # This will hold the Rules struct
    ]
  end

  ## Public API

  def start_link(player_id) do
    GenServer.start_link(__MODULE__, player_id, name: via_tuple(player_id))
  end

  def get_state(player_id) do
    GenServer.call(via_tuple(player_id), :get_state)
  end

  def update_resources(player_id, new_resources) do
    GenServer.cast(via_tuple(player_id), {:update_resources, new_resources})
  end

  def forage(player_id) do
    GenServer.call(via_tuple(player_id), :start_foraging)
  end

  ## GenServer Callbacks

  def init(player_id) do
    state = %PlayerState{
      player_id: player_id,
      rules: Rules.new()
    }

    {:ok, state}
  end

  def handle_call(:start_foraging, _from, state) do
    case Rules.check(state.rules, :begin_foraging) do
      {:ok, new_rules} ->
        new_state = %{state | rules: new_rules}
        # Return flattened state in the response
        flattened_state = %{
          player_id: new_state.player_id,
          resources: new_rules.resources,
          status: new_rules.state,
          tick_counter: new_rules.tick_counter,
          foraging_ticks: new_rules.current_state_counter
        }
        {:reply, {:ok, flattened_state}, new_state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_cast({:update_resources, new_resources}, state) do
    new_rules = Rules.update_resources(state.rules, new_resources)
    {:noreply, %{state | rules: new_rules}}
  end

  def handle_call(:get_state, _from, state) do
    # Return a flattened version of the state that matches the expected structure
    flattened_state = %{
      player_id: state.player_id,
      resources: state.rules.resources,
      status: state.rules.state,
      tick_counter: state.rules.tick_counter
    }
    {:reply, flattened_state, state}
  end

  def handle_cast(:tick, state) do
    new_rules = Rules.process_tick(state.rules)

    # Handle foraging completion if state changed from foraging to idle
    new_rules =
      if state.rules.state == :foraging and new_rules.state == :idle do
        case ColonyGame.Game.ForagingServer.forage(state.player_id) do
          {:ok, amount} ->
            Rules.update_resources(new_rules, %{food: amount})
          :empty ->
            new_rules
        end
      else
        new_rules
      end

    # Broadcast state update to LiveView
    ColonyGameWeb.Endpoint.broadcast("player:#{state.player_id}", "tick_update", %{
      resources: new_rules.resources,
      status: new_rules.state,
      tick_counter: new_rules.tick_counter
    })

    {:noreply, %{state | rules: new_rules}}
  end

  ## Internal Helper

  defp via_tuple(player_id), do: {:via, Registry, {ColonyGame.Game.Registry, player_id}}
end
