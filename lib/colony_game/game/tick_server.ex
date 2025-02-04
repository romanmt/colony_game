defmodule ColonyGame.Game.TickServer do
  use GenServer

  # 5 seconds
  @tick_interval 5000

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_tick()
    {:ok, state}
  end

  def handle_info(:tick, state) do
    update_all_players()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp update_all_players do
    players = DynamicSupervisor.which_children(ColonyGame.Game.PlayerSupervisor)

    for {_, pid, _, _} <- players do
      GenServer.cast(pid, :tick)
    end

    GenServer.cast(ColonyGame.Game.ForagingServer, :tick)
  end
end
