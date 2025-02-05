defmodule ColonyGame.Game.PlayerProcess do
  use GenServer
  import Logger

  @initial_resources %{food: 100, water: 100, energy: 100}

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

  ## GenServer Callbacks

  def init(player_id) do
    state = %{
      player_id: player_id,
      resources: @initial_resources,
      last_updated: System.system_time(:second),
      tick_counter: 0
    }

    {:ok, state}
  end

  def update_resources(player_id, new_resources) do
    GenServer.cast(via_tuple(player_id), {:update_resources, new_resources})
  end

  def handle_cast({:update_resources, new_resources}, state) do
    updated_resources = Map.merge(state.resources, new_resources, fn _, old, new -> old + new end)
    {:noreply, %{state | resources: updated_resources}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:tick, state) do
    Logger.debug(inspect(state))
    tick = state.tick_counter + 1

    new_resources = state.resources

    new_resources =
      if rem(tick, 5) == 0 do
        %{new_resources | food: max(new_resources.food - 1, 0)}
      else
        new_resources
      end

    {:noreply,
     %{
       state
       | resources: new_resources,
         tick_counter: tick,
         last_updated: System.system_time(:seconds)
     }}
  end

  ## Internal Helper

  defp via_tuple(player_id), do: {:via, Registry, {ColonyGame.Game.Registry, player_id}}
end
