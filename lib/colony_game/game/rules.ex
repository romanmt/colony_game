defmodule ColonyGame.Game.Rules do
  @moduledoc """
  The Rules module serves as the game's rules engine, handling all game mechanics,
  state transitions, and resource calculations.
  """

  alias ColonyGame.Game.Rules

  defstruct [
    :state,
    :current_state_counter,
    :resources,
    :inventory,
    :last_updated,
    :tick_counter,
    :foraging_location  # Track which location the player is foraging at (:forest, :river, :cave)
  ]

  @type resource_type :: :food | :water | :energy
  @type resources :: %{resource_type() => non_neg_integer()}
  @type item_type :: :wood | :stone | :fiber | :berries
  @type inventory :: %{item_type() => non_neg_integer()}
  @type game_state :: :idle | :foraging

  @foraging_duration 5  # ticks
  @food_consumption_rate 1
  @food_consumption_interval 5  # ticks
  @water_consumption_rate 1
  @water_consumption_interval 10  # ticks
  @energy_consumption_rate 1
  @energy_consumption_interval 15  # ticks

  @doc """
  Creates a new Rules struct with initial state
  """
  def new do
    %Rules{
      state: :idle,
      current_state_counter: 0,
      resources: %{food: 100, water: 100, energy: 100},
      inventory: %{wood: 0, stone: 0, fiber: 0, berries: 0},
      last_updated: System.system_time(:second),
      tick_counter: 0,
      foraging_location: nil
    }
  end

  @doc """
  Handles the begin_foraging action based on current game state.
  Accepts an optional location parameter (:forest, :river, or :cave).
  Defaults to :forest for backwards compatibility.
  """
  def check(%Rules{state: :idle} = rules, :begin_foraging) do
    check(rules, {:begin_foraging, :forest})
  end

  def check(%Rules{state: :idle} = rules, {:begin_foraging, location})
      when location in [:forest, :river, :cave] do
    {:ok, %Rules{rules |
      state: :foraging,
      current_state_counter: @foraging_duration,
      foraging_location: location
    }}
  end

  def check(%Rules{state: :idle}, {:begin_foraging, _invalid_location}) do
    {:error, :invalid_location}
  end

  def check(%Rules{state: :foraging}, :begin_foraging) do
    {:error, :already_foraging}
  end

  def check(%Rules{state: :foraging}, {:begin_foraging, _location}) do
    {:error, :already_foraging}
  end

  @doc """
  Processes a game tick, updating resources and state counters
  """
  def process_tick(%Rules{} = rules) do
    rules
    |> update_tick_counter()
    |> consume_resources()
    |> update_state_counter()
  end

  @doc """
  Updates resources based on given changes
  """
  def update_resources(%Rules{} = rules, resource_changes) do
    updated_resources = Map.merge(rules.resources, resource_changes, fn _, old, new ->
      max(old + new, 0)
    end)
    %Rules{rules | resources: updated_resources}
  end

  @doc """
  Adds an item to the inventory. Returns updated Rules struct.
  """
  def add_item(%Rules{} = rules, item, amount) when is_atom(item) and amount > 0 do
    current = Map.get(rules.inventory, item, 0)
    updated_inventory = Map.put(rules.inventory, item, current + amount)
    %Rules{rules | inventory: updated_inventory}
  end

  def add_item(%Rules{} = rules, _item, _amount), do: rules

  @doc """
  Removes an item from the inventory. Returns {:ok, updated_rules} or {:error, :insufficient_items}.
  """
  def remove_item(%Rules{} = rules, item, amount) when is_atom(item) and amount > 0 do
    current = Map.get(rules.inventory, item, 0)

    if current >= amount do
      updated_inventory = Map.put(rules.inventory, item, current - amount)
      {:ok, %Rules{rules | inventory: updated_inventory}}
    else
      {:error, :insufficient_items}
    end
  end

  def remove_item(%Rules{} = rules, _item, _amount), do: {:ok, rules}

  @doc """
  Checks if the player has at least the specified amount of an item.
  """
  def has_item?(%Rules{} = rules, item, amount \\ 1) when is_atom(item) do
    current = Map.get(rules.inventory, item, 0)
    current >= amount
  end

  @doc """
  Adds multiple items to the inventory at once.
  Expects a map of item => amount.
  """
  def add_items(%Rules{} = rules, items) when is_map(items) do
    Enum.reduce(items, rules, fn {item, amount}, acc ->
      add_item(acc, item, amount)
    end)
  end

  # Private helper functions

  defp update_tick_counter(%Rules{} = rules) do
    %Rules{rules | tick_counter: rules.tick_counter + 1}
  end

  defp consume_resources(%Rules{tick_counter: tick} = rules) do
    rules
    |> consume_food(tick)
    |> consume_water(tick)
    |> consume_energy(tick)
  end

  defp consume_food(rules, tick) do
    if rem(tick, @food_consumption_interval) == 0 do
      update_resources(rules, %{food: -@food_consumption_rate})
    else
      rules
    end
  end

  defp consume_water(rules, tick) do
    if rem(tick, @water_consumption_interval) == 0 do
      update_resources(rules, %{water: -@water_consumption_rate})
    else
      rules
    end
  end

  defp consume_energy(rules, tick) do
    if rem(tick, @energy_consumption_interval) == 0 do
      update_resources(rules, %{energy: -@energy_consumption_rate})
    else
      rules
    end
  end

  defp update_state_counter(%Rules{state: :foraging, current_state_counter: 1} = rules) do
    %Rules{rules | state: :idle, current_state_counter: 0, foraging_location: nil}
  end

  defp update_state_counter(%Rules{state: :foraging, current_state_counter: counter} = rules) when counter > 0 do
    %Rules{rules | current_state_counter: counter - 1}
  end

  defp update_state_counter(rules), do: rules
end
