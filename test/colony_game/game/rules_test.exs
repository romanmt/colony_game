defmodule ColonyGame.Game.RulesTest do
  use ExUnit.Case, async: true
  alias ColonyGame.Game.Rules

  describe "new/0" do
    test "creates a new rules struct with default values" do
      rules = Rules.new()

      assert rules.state == :idle
      assert rules.current_state_counter == 0
      assert rules.resources == %{food: 100, water: 100, energy: 100}
      assert rules.tick_counter == 0
      assert is_integer(rules.last_updated)
    end
  end

  describe "check/2" do
    test "allows starting foraging when idle" do
      rules = Rules.new()

      assert {:ok, new_rules} = Rules.check(rules, :begin_foraging)
      assert new_rules.state == :foraging
      assert new_rules.current_state_counter == 5
    end

    test "prevents starting foraging when already foraging" do
      rules = %Rules{Rules.new() | state: :foraging}

      assert {:error, :already_foraging} = Rules.check(rules, :begin_foraging)
    end
  end

  describe "process_tick/1" do
    test "increments tick counter" do
      rules = Rules.new()

      new_rules = Rules.process_tick(rules)
      assert new_rules.tick_counter == rules.tick_counter + 1
    end

    test "consumes food every 5 ticks" do
      rules = Rules.new()

      # Process 4 ticks - should not consume food
      rules = Enum.reduce(1..4, rules, fn _, acc -> Rules.process_tick(acc) end)
      assert rules.resources.food == 100

      # Process 5th tick - should consume 1 food
      rules = Rules.process_tick(rules)
      assert rules.resources.food == 99
    end

    test "prevents food from going below 0" do
      rules = %Rules{Rules.new() | resources: %{food: 0, water: 100, energy: 100}}

      # Process 5 ticks to trigger food consumption
      rules = Enum.reduce(1..5, rules, fn _, acc -> Rules.process_tick(acc) end)
      assert rules.resources.food == 0
    end

    test "decrements foraging counter and transitions to idle when complete" do
      rules = %Rules{Rules.new() | state: :foraging, current_state_counter: 2}

      # First tick
      rules = Rules.process_tick(rules)
      assert rules.state == :foraging
      assert rules.current_state_counter == 1

      # Second tick - should transition to idle
      rules = Rules.process_tick(rules)
      assert rules.state == :idle
      assert rules.current_state_counter == 0
    end
  end

  describe "update_resources/2" do
    test "adds resources correctly" do
      rules = Rules.new()

      new_rules = Rules.update_resources(rules, %{food: 10})
      assert new_rules.resources.food == 110
      assert new_rules.resources.water == 100  # unchanged
      assert new_rules.resources.energy == 100  # unchanged
    end

    test "subtracts resources correctly" do
      rules = Rules.new()

      new_rules = Rules.update_resources(rules, %{food: -10})
      assert new_rules.resources.food == 90
    end

    test "prevents resources from going below 0" do
      rules = Rules.new()

      new_rules = Rules.update_resources(rules, %{food: -150})
      assert new_rules.resources.food == 0
    end

    test "handles multiple resource updates simultaneously" do
      rules = Rules.new()

      new_rules = Rules.update_resources(rules, %{food: -10, water: 20, energy: -30})
      assert new_rules.resources.food == 90
      assert new_rules.resources.water == 120
      assert new_rules.resources.energy == 70
    end
  end
end
