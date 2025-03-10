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
    :last_updated,
    :tick_counter
  ]

  @type resource_type :: :food | :water | :energy
  @type resources :: %{resource_type() => non_neg_integer()}
  @type game_state :: :idle | :foraging

  @foraging_duration 5  # ticks
  @food_consumption_rate 1
  @food_consumption_interval 5  # ticks

  @doc """
  Creates a new Rules struct with initial state
  """
  def new do
    %Rules{
      state: :idle,
      current_state_counter: 0,
      resources: %{food: 100, water: 100, energy: 100},
      last_updated: System.system_time(:second),
      tick_counter: 0
    }
  end

  @doc """
  Handles the begin_foraging action based on current game state
  """
  def check(%Rules{state: :idle} = rules, :begin_foraging) do
    {:ok, %Rules{rules | state: :foraging, current_state_counter: @foraging_duration}}
  end

  def check(%Rules{state: :foraging}, :begin_foraging) do
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

  # Private helper functions

  defp update_tick_counter(%Rules{} = rules) do
    %Rules{rules | tick_counter: rules.tick_counter + 1}
  end

  defp consume_resources(%Rules{tick_counter: tick} = rules) do
    if rem(tick, @food_consumption_interval) == 0 do
      update_resources(rules, %{food: -@food_consumption_rate})
    else
      rules
    end
  end

  defp update_state_counter(%Rules{state: :foraging, current_state_counter: 1} = rules) do
    %Rules{rules | state: :idle, current_state_counter: 0}
  end

  defp update_state_counter(%Rules{state: :foraging, current_state_counter: counter} = rules) when counter > 0 do
    %Rules{rules | current_state_counter: counter - 1}
  end

  defp update_state_counter(rules), do: rules
end
