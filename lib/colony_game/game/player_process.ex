defmodule ColonyGame.Game.PlayerProcess do
  use GenServer
  import Logger

  defmodule PlayerState do
    defstruct [
      :player_id,
      :last_updated,
      :tick_counter,
      :foraging_ticks,
      :status,
      resources: [:food, :water, :energy]
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

  def update_resources(player_id, new_resources) do
    GenServer.cast(via_tuple(player_id), {:update_resources, new_resources})
  end

  ## GenServer Callbacks

  def init(player_id) do
    state = %PlayerState{
      player_id: player_id,
      status: :idle,
      resources: %{food: 100, water: 100, energy: 100},
      last_updated: System.system_time(:second),
      tick_counter: 0,
      foraging_ticks: 0
    }

    {:ok, state}
  end

  def handle_call(:start_foraging, _from, %{status: :idle} = state) do
    # ✅ Foraging takes 5 ticks
    new_state = %{state | status: :foraging, foraging_ticks: 5}
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:start_foraging, _from, %{status: :foraging} = state) do
    {:reply, {:error, "You are already foraging!"}, state}
  end

  def handle_cast({:update_resources, new_resources}, state) do
    updated_resources = Map.merge(state.resources, new_resources, fn _, old, new -> old + new end)
    {:noreply, %{state | resources: updated_resources}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:tick, %{status: :idle, resources: new_resources} = state) do
    Logger.info("** IDLING **")
    tick = state.tick_counter + 1

    # ✅ Broadcast an event to LiveView
    new_resources = consume(new_resources, tick)

    ColonyGameWeb.Endpoint.broadcast("player:#{state.player_id}", "tick_update", %{
      resources: new_resources,
      status: state.status,
      tick_counter: tick
    })

    {:noreply,
     %PlayerState{
       state
       | resources: new_resources,
         tick_counter: tick,
         last_updated: System.system_time(:seconds)
     }}
  end

  def handle_cast(
        :tick,
        %{status: :foraging, resources: new_resources, foraging_ticks: foraging_ticks} = state
      ) do
    tick = state.tick_counter + 1
    foraging_ticks = foraging_ticks - 1
    new_status = state.status

    {new_status, new_resources} =
      if(foraging_ticks == 0) do
        case ColonyGame.Game.ForagingServer.forage(state.player_id) do
          {:ok, amount} ->
            {:idle, %{new_resources | food: new_resources.food + amount}}

          :empty ->
            {:idle, state.resources}
        end
      else
        {state.status, state.resources}
      end

    ColonyGameWeb.Endpoint.broadcast("player:#{state.player_id}", "tick_update", %{
      resources: new_resources,
      status: new_status,
      tick_counter: tick
    })

    {:noreply,
     %PlayerState{
       state
       | resources: new_resources,
         tick_counter: tick,
         status: new_status,
         foraging_ticks: foraging_ticks,
         last_updated: System.system_time(:seconds)
     }}
  end

  ## Internal Helper

  defp via_tuple(player_id), do: {:via, Registry, {ColonyGame.Game.Registry, player_id}}

  defp consume(resources, tick) do
    if rem(tick, 5) == 0 do
      %{resources | food: max(resources.food - 1, 0)}
    else
      resources
    end
  end
end
