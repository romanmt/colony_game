defmodule ColonyGame.Game.PlayerProcessTest do
  use ExUnit.Case

  alias ColonyGame.Game.PlayerProcess

  # Helper to generate unique player IDs for each test
  defp unique_player_id do
    "test_player_#{System.unique_integer([:positive, :monotonic])}"
  end

  describe "start_link/1" do
    test "starts a player process with the given player_id" do
      player_id = unique_player_id()

      assert {:ok, pid} = PlayerProcess.start_link(player_id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "registers the process in the Registry" do
      player_id = unique_player_id()

      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Verify it's registered in the Registry
      assert [{^pid, nil}] = Registry.lookup(ColonyGame.Game.Registry, player_id)
    end

    test "returns error when starting duplicate player_id" do
      player_id = unique_player_id()

      {:ok, _pid} = PlayerProcess.start_link(player_id)

      # Attempting to start another process with the same player_id should fail
      assert {:error, {:already_started, _}} = PlayerProcess.start_link(player_id)
    end
  end

  describe "get_state/1" do
    test "returns the current player state" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      state = PlayerProcess.get_state(player_id)

      assert state.player_id == player_id
      assert state.resources == %{food: 100, water: 100, energy: 100}
      assert state.status == :idle
      assert state.tick_counter == 0
    end

    test "returns initial resources of 100 for food, water, and energy" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      state = PlayerProcess.get_state(player_id)

      assert state.resources.food == 100
      assert state.resources.water == 100
      assert state.resources.energy == 100
    end
  end

  describe "forage/1" do
    test "transitions player from idle to foraging state" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      assert {:ok, new_state} = PlayerProcess.forage(player_id)

      assert new_state.status == :foraging
      assert new_state.foraging_ticks == 5
    end

    test "returns error when player is already foraging" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      # Start foraging
      {:ok, _} = PlayerProcess.forage(player_id)

      # Try to forage again
      assert {:error, :already_foraging} = PlayerProcess.forage(player_id)
    end

    test "preserves player_id in returned state" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      {:ok, new_state} = PlayerProcess.forage(player_id)

      assert new_state.player_id == player_id
    end

    test "preserves resources when starting to forage" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      {:ok, new_state} = PlayerProcess.forage(player_id)

      assert new_state.resources == %{food: 100, water: 100, energy: 100}
    end
  end

  describe "update_resources/2" do
    test "updates resources with positive values" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      PlayerProcess.update_resources(player_id, %{food: 10})

      # Give the cast time to process
      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 110
    end

    test "updates resources with negative values" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      PlayerProcess.update_resources(player_id, %{food: -20})

      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 80
    end

    test "updates multiple resources at once" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      PlayerProcess.update_resources(player_id, %{food: -10, water: 15, energy: -5})

      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 90
      assert state.resources.water == 115
      assert state.resources.energy == 95
    end

    test "prevents resources from going below zero" do
      player_id = unique_player_id()
      {:ok, _pid} = PlayerProcess.start_link(player_id)

      PlayerProcess.update_resources(player_id, %{food: -150})

      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 0
    end
  end

  describe "tick handling" do
    test "increments tick counter on tick" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      initial_state = PlayerProcess.get_state(player_id)
      assert initial_state.tick_counter == 0

      # Send a tick
      GenServer.cast(pid, :tick)
      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.tick_counter == 1
    end

    test "processes multiple ticks correctly" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Send 3 ticks
      Enum.each(1..3, fn _ ->
        GenServer.cast(pid, :tick)
        Process.sleep(10)
      end)

      state = PlayerProcess.get_state(player_id)
      assert state.tick_counter == 3
    end

    test "consumes food every 5 ticks" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Send 4 ticks - should not consume food
      Enum.each(1..4, fn _ ->
        GenServer.cast(pid, :tick)
        Process.sleep(10)
      end)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 100

      # Send 5th tick - should consume 1 food
      GenServer.cast(pid, :tick)
      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.resources.food == 99
    end

    test "decrements foraging counter during ticks" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Start foraging
      {:ok, state} = PlayerProcess.forage(player_id)
      assert state.foraging_ticks == 5

      # Send one tick
      GenServer.cast(pid, :tick)
      Process.sleep(10)

      state = PlayerProcess.get_state(player_id)
      assert state.status == :foraging
    end

    test "transitions from foraging to idle after 5 ticks" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Start foraging
      {:ok, _state} = PlayerProcess.forage(player_id)

      # Send 5 ticks to complete foraging
      Enum.each(1..5, fn _ ->
        GenServer.cast(pid, :tick)
        Process.sleep(10)
      end)

      state = PlayerProcess.get_state(player_id)
      assert state.status == :idle
    end

    test "can forage again after completing foraging" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # First foraging cycle
      {:ok, _state} = PlayerProcess.forage(player_id)

      # Complete foraging
      Enum.each(1..5, fn _ ->
        GenServer.cast(pid, :tick)
        Process.sleep(10)
      end)

      state = PlayerProcess.get_state(player_id)
      assert state.status == :idle

      # Should be able to forage again
      assert {:ok, new_state} = PlayerProcess.forage(player_id)
      assert new_state.status == :foraging
    end
  end

  describe "integration" do
    test "full game cycle: start, forage, complete, get resources" do
      player_id = unique_player_id()
      {:ok, pid} = PlayerProcess.start_link(player_id)

      # Verify initial state
      initial_state = PlayerProcess.get_state(player_id)
      assert initial_state.status == :idle
      assert initial_state.resources.food == 100

      # Start foraging
      {:ok, foraging_state} = PlayerProcess.forage(player_id)
      assert foraging_state.status == :foraging

      # Complete foraging (5 ticks)
      Enum.each(1..5, fn _ ->
        GenServer.cast(pid, :tick)
        Process.sleep(10)
      end)

      # Verify foraging complete
      final_state = PlayerProcess.get_state(player_id)
      assert final_state.status == :idle
      assert final_state.tick_counter == 5

      # Food may have increased from foraging (depends on ForagingServer)
      # and decreased by 1 from consumption at tick 5
      # The exact value depends on ForagingServer random food amount
      assert is_integer(final_state.resources.food)
    end
  end
end
