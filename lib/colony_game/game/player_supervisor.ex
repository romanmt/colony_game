defmodule ColonyGame.Game.PlayerSupervisor do
  use DynamicSupervisor

  alias ColonyGame.Game.PlayerProcess

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_player(player_id) do
    case DynamicSupervisor.start_child(__MODULE__, {PlayerProcess, player_id}) do
      {:ok, _pid} -> :ok
      # Player already running
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end
end
