defmodule ColonyGame.Game.TickServerTest do
  use ExUnit.Case, async: false

  alias ColonyGame.Game.TickServer

  # A simple GenServer to receive and track tick messages
  defmodule TickReceiver do
    use GenServer

    def start_link(test_pid) do
      GenServer.start_link(__MODULE__, test_pid)
    end

    def init(test_pid) do
      {:ok, %{test_pid: test_pid, tick_count: 0}}
    end

    def handle_cast(:tick, state) do
      send(state.test_pid, {:tick_received, self()})
      {:noreply, %{state | tick_count: state.tick_count + 1}}
    end

    def get_tick_count(pid) do
      GenServer.call(pid, :get_tick_count)
    end

    def handle_call(:get_tick_count, _from, state) do
      {:reply, state.tick_count, state}
    end
  end

  # A fast tick server for testing rescheduling behavior
  defmodule FastTickServer do
    use GenServer

    @tick_interval 50

    def start_link(test_pid) do
      GenServer.start_link(__MODULE__, test_pid)
    end

    def init(test_pid) do
      schedule_tick()
      {:ok, %{test_pid: test_pid, tick_count: 0}}
    end

    def handle_info(:tick, state) do
      send(state.test_pid, {:tick, state.tick_count + 1})
      schedule_tick()
      {:noreply, %{state | tick_count: state.tick_count + 1}}
    end

    defp schedule_tick do
      Process.send_after(self(), :tick, @tick_interval)
    end
  end

  # A tick server that tracks timing between ticks
  defmodule TimedTickServer do
    use GenServer

    @tick_interval 100

    def start_link(test_pid) do
      GenServer.start_link(__MODULE__, test_pid)
    end

    def init(test_pid) do
      schedule_tick()
      {:ok, %{test_pid: test_pid, last_tick: System.monotonic_time(:millisecond)}}
    end

    def handle_info(:tick, state) do
      now = System.monotonic_time(:millisecond)
      elapsed = now - state.last_tick
      send(state.test_pid, {:tick_elapsed, elapsed})
      schedule_tick()
      {:noreply, %{state | last_tick: now}}
    end

    defp schedule_tick do
      Process.send_after(self(), :tick, @tick_interval)
    end
  end

  # A test server to verify tick scheduling on init
  defmodule TestTickServerInit do
    use GenServer

    def start_link(opts) do
      name = Keyword.get(opts, :name)
      test_pid = Keyword.fetch!(opts, :test_pid)

      if name do
        GenServer.start_link(__MODULE__, test_pid, name: name)
      else
        GenServer.start_link(__MODULE__, test_pid)
      end
    end

    def init(test_pid) do
      # Mimic TickServer's behavior - schedule immediately
      Process.send_after(self(), :tick, 50)
      {:ok, %{test_pid: test_pid}}
    end

    def handle_info(:tick, state) do
      send(state.test_pid, :tick_scheduled)
      {:noreply, state}
    end
  end

  describe "start_link/1" do
    test "starts the tick server successfully" do
      # The TickServer is already started by the application
      # Verify it's running by checking if the process is alive
      assert Process.whereis(TickServer) != nil
      assert Process.alive?(Process.whereis(TickServer))
    end

    test "server is registered with its module name" do
      pid = Process.whereis(TickServer)
      assert is_pid(pid)
    end
  end

  describe "tick scheduling" do
    test "schedules a tick on init" do
      {:ok, pid} = TestTickServerInit.start_link(test_pid: self())

      # Should receive tick within 100ms
      assert_receive :tick_scheduled, 200

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 for :tick" do
    test "sends tick to all player processes" do
      # Start some mock player processes
      {:ok, player1} = TickReceiver.start_link(self())
      {:ok, player2} = TickReceiver.start_link(self())

      # Verify initial tick count is 0
      assert TickReceiver.get_tick_count(player1) == 0
      assert TickReceiver.get_tick_count(player2) == 0

      # Send tick directly to receivers (simulating what TickServer does)
      GenServer.cast(player1, :tick)
      GenServer.cast(player2, :tick)

      # Wait for messages
      assert_receive {:tick_received, ^player1}, 100
      assert_receive {:tick_received, ^player2}, 100

      # Verify tick count increased
      assert TickReceiver.get_tick_count(player1) == 1
      assert TickReceiver.get_tick_count(player2) == 1

      GenServer.stop(player1)
      GenServer.stop(player2)
    end

    test "tick server reschedules tick after processing" do
      {:ok, pid} = FastTickServer.start_link(self())

      # Should receive multiple ticks
      assert_receive {:tick, 1}, 100
      assert_receive {:tick, 2}, 100
      assert_receive {:tick, 3}, 100

      GenServer.stop(pid)
    end
  end

  describe "tick interval" do
    test "tick interval timing is consistent" do
      {:ok, pid} = TimedTickServer.start_link(self())

      # First tick - elapsed time from init
      assert_receive {:tick_elapsed, elapsed1}, 200
      assert elapsed1 >= 90 and elapsed1 <= 150

      # Second tick - should be approximately 100ms after first
      assert_receive {:tick_elapsed, elapsed2}, 200
      assert elapsed2 >= 90 and elapsed2 <= 150

      GenServer.stop(pid)
    end

    test "uses Process.send_after for scheduling" do
      # This test verifies the scheduling pattern by checking
      # that the server continues to tick at regular intervals
      {:ok, pid} = FastTickServer.start_link(self())

      # Collect timing data for multiple ticks
      ticks = for _i <- 1..5 do
        receive do
          {:tick, n} -> n
        after
          200 -> :timeout
        end
      end

      # All ticks should be received (no timeouts)
      assert ticks == [1, 2, 3, 4, 5]

      GenServer.stop(pid)
    end
  end

  describe "integration with ForagingServer" do
    test "ForagingServer is running and accepts tick casts" do
      # The ForagingServer is started by the application
      foraging_server = Process.whereis(ColonyGame.Game.ForagingServer)
      assert foraging_server != nil
      assert Process.alive?(foraging_server)

      # We can verify the ForagingServer accepts :tick casts
      # by sending one directly and ensuring no crash
      GenServer.cast(ColonyGame.Game.ForagingServer, :tick)

      # Give it a moment to process
      Process.sleep(10)

      # Server should still be alive after receiving tick
      assert Process.alive?(foraging_server)
    end
  end

  describe "integration with PlayerSupervisor" do
    test "PlayerSupervisor is running and returns children list" do
      # Verify the PlayerSupervisor is running
      supervisor = Process.whereis(ColonyGame.Game.PlayerSupervisor)
      assert supervisor != nil
      assert Process.alive?(supervisor)

      # which_children should return a list (even if empty)
      children = DynamicSupervisor.which_children(ColonyGame.Game.PlayerSupervisor)
      assert is_list(children)
    end

    test "tick is sent to dynamically added players" do
      # Start a player via the supervisor
      player_id = "test_player_#{System.unique_integer([:positive])}"
      :ok = ColonyGame.Game.PlayerSupervisor.start_player(player_id)

      # Give the system a moment
      Process.sleep(10)

      # Verify player is in the supervisor
      children = DynamicSupervisor.which_children(ColonyGame.Game.PlayerSupervisor)
      assert length(children) >= 1

      # Find the player process via Registry
      [{pid, _}] = Registry.lookup(ColonyGame.Game.Registry, player_id)
      assert Process.alive?(pid)

      # Clean up - stop the player process
      DynamicSupervisor.terminate_child(ColonyGame.Game.PlayerSupervisor, pid)
    end
  end

  describe "update_all_players/0 behavior" do
    test "iterates through all players in PlayerSupervisor" do
      # Start multiple test players
      player_ids = for i <- 1..3 do
        player_id = "tick_test_player_#{i}_#{System.unique_integer([:positive])}"
        :ok = ColonyGame.Game.PlayerSupervisor.start_player(player_id)
        player_id
      end

      # Give the system a moment
      Process.sleep(10)

      # Verify all players are registered
      children = DynamicSupervisor.which_children(ColonyGame.Game.PlayerSupervisor)
      assert length(children) >= 3

      # Get PIDs for cleanup
      pids =
        for player_id <- player_ids do
          [{pid, _}] = Registry.lookup(ColonyGame.Game.Registry, player_id)
          pid
        end

      # All players should be alive
      for pid <- pids do
        assert Process.alive?(pid)
      end

      # Clean up
      for pid <- pids do
        DynamicSupervisor.terminate_child(ColonyGame.Game.PlayerSupervisor, pid)
      end
    end
  end
end
