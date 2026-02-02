defmodule ColonyGame.Game.ForagingServer do
  @moduledoc """
  Manages multiple foraging locations with different resources:
  - Forest: Food source (10-30 food, fast regrowth every 15 ticks)
  - River: Water source (5-20 water, medium regrowth every 25 ticks)
  - Cave: Energy crystals (3-15 energy, slow regrowth every 40 ticks)
  """

  use GenServer
  alias ColonyGame.Game.PlayerProcess

  # Regrowth intervals for each location
  @forest_regrow_interval 15
  @river_regrow_interval 25
  @cave_regrow_interval 40

  # Location configurations: {resource_type, min_amount, max_amount, harvest_min, harvest_max}
  @location_configs %{
    forest: {:food, 10, 30, 1, 5},
    river: {:water, 5, 20, 1, 4},
    cave: {:energy, 3, 15, 1, 3}
  }

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Forage at a specific location. Returns the resource type and amount gathered.
  Location must be :forest, :river, or :cave.
  """
  def forage(location) when location in [:forest, :river, :cave] do
    GenServer.call(__MODULE__, {:forage, location})
  end

  def forage(_location), do: {:error, :invalid_location}

  @doc """
  Legacy forage function for backwards compatibility - defaults to forest.
  """
  def forage(player_id) when is_binary(player_id) do
    case forage(:forest) do
      {:ok, resource_type, amount} ->
        PlayerProcess.update_resources(player_id, %{resource_type => amount})
        {:ok, amount}

      :empty ->
        :empty
    end
  end

  @doc """
  Get the current resource levels at all locations.
  """
  def get_locations do
    GenServer.call(__MODULE__, :get_locations)
  end

  ## Server Callbacks

  def init(_state) do
    :ets.new(:foraging_locations, [:set, :public, :named_table])
    seed_all_locations()
    state = %{
      tick_counter: 0,
      forest_counter: 0,
      river_counter: 0,
      cave_counter: 0
    }
    {:ok, state}
  end

  def handle_call({:forage, location}, _from, state) do
    case take_resource(location) do
      {:ok, resource_type, amount} ->
        {:reply, {:ok, resource_type, amount}, state}

      :empty ->
        {:reply, :empty, state}
    end
  end

  def handle_call(:get_locations, _from, state) do
    locations = %{
      forest: get_location_amount(:forest),
      river: get_location_amount(:river),
      cave: get_location_amount(:cave)
    }
    {:reply, locations, state}
  end

  def handle_cast(:tick, state) do
    new_state = state
    |> Map.update!(:tick_counter, &(&1 + 1))
    |> process_regrowth(:forest, @forest_regrow_interval)
    |> process_regrowth(:river, @river_regrow_interval)
    |> process_regrowth(:cave, @cave_regrow_interval)

    {:noreply, new_state}
  end

  ## Helper Functions

  defp process_regrowth(state, location, interval) do
    counter_key = String.to_atom("#{location}_counter")
    counter = Map.get(state, counter_key, 0) + 1

    if counter >= interval do
      regrow_location(location)
      Map.put(state, counter_key, 0)
    else
      Map.put(state, counter_key, counter)
    end
  end

  defp take_resource(location) do
    {resource_type, _min, _max, harvest_min, harvest_max} = @location_configs[location]

    case :ets.lookup(:foraging_locations, location) do
      [{^location, amount}] when amount > 0 ->
        harvest_amount = min(Enum.random(harvest_min..harvest_max), amount)
        new_amount = max(amount - harvest_amount, 0)
        :ets.insert(:foraging_locations, {location, new_amount})
        {:ok, resource_type, harvest_amount}

      _ ->
        :empty
    end
  end

  defp get_location_amount(location) do
    case :ets.lookup(:foraging_locations, location) do
      [{^location, amount}] -> amount
      _ -> 0
    end
  end

  defp regrow_location(location) do
    {_resource_type, min_amount, max_amount, _harvest_min, _harvest_max} = @location_configs[location]
    :ets.insert(:foraging_locations, {location, Enum.random(min_amount..max_amount)})
  end

  defp seed_all_locations do
    Enum.each(@location_configs, fn {location, {_resource_type, min, max, _hmin, _hmax}} ->
      :ets.insert(:foraging_locations, {location, Enum.random(min..max)})
    end)
  end
end
