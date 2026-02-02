defmodule ColonyGame.Game.PlayerSupervisor do
  use DynamicSupervisor

  alias ColonyGame.Game.{PlayerProcess, PlayerPresence}

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_player(player_id) do
    case DynamicSupervisor.start_child(__MODULE__, {PlayerProcess, player_id}) do
      {:ok, _pid} ->
        # Register player with presence system
        PlayerPresence.register_player(player_id)
        :ok
      # Player already running - still register in case of reconnect
      {:error, {:already_started, _pid}} ->
        PlayerPresence.register_player(player_id)
        :ok
      error ->
        error
    end
  end

  @doc """
  Stop a player process and unregister from presence.
  """
  def stop_player(player_id) do
    PlayerPresence.unregister_player(player_id)

    case Registry.lookup(ColonyGame.Game.Registry, player_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] ->
        :ok
    end
  end
end
