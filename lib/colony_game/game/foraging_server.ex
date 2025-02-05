defmodule ColonyGame.Game.ForagingServer do
  use GenServer
  alias ColonyGame.Game.PlayerProcess

  # Food regrows every 10 ticks
  @tick_interval 30

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def forage(player_id) do
    GenServer.call(__MODULE__, {:forage, player_id})
  end

  ## Server Callbacks

  def init(state) do
    :ets.new(:food_sources, [:set, :public, :named_table])
    seed_food_sources()
    state = %{tick_counter: 0}
    {:ok, state}
  end

  def handle_call({:forage, player_id}, _from, state) do
    case take_food() do
      {:ok, amount} ->
        PlayerProcess.update_resources(player_id, %{food: amount})
        {:reply, {:ok, amount}, state}

      :empty ->
        {:reply, :empty, state}
    end
  end

  def handle_info(:regrow_food, state) do
    regrow_food()
    {:noreply, state}
  end

  def handle_cast(:tick, state) do
    tick_count = state.tick_counter

    if(tick_counter = @tick_interval) do
      regrow_food()
      state = %{state | tick_counter: 0}
    end

    {:noreply, state}
  end

  ## Helper Functions

  defp take_food() do
    case :ets.lookup(:food_sources, :main_location) do
      [{:main_location, food}] when food > 0 ->
        new_food = max(food - Enum.random(1..5), 0)
        :ets.insert(:food_sources, {:main_location, new_food})
        {:ok, food - new_food}

      _ ->
        :empty
    end
  end

  defp regrow_food() do
    :ets.insert(:food_sources, {:main_location, Enum.random(10..30)})
  end

  # defp schedule_food_regeneration() do
  #  Process.send_after(self(), :regrow_food, @tick_interval)
  # end

  defp seed_food_sources() do
    :ets.insert(:food_sources, {:main_location, Enum.random(10..30)})
  end
end
