defmodule ColonyGameWeb.GameLive do
  use Phoenix.LiveView
  require Logger

  alias ColonyGame.Game.{PlayerSupervisor, PlayerProcess}

  @impl true
  def mount(_params, _session, socket) do
    player_id = generate_anonymous_id()

    Logger.info("Starting player process for ID: #{player_id}")
    PlayerSupervisor.start_player(player_id)

    {:ok,
     assign(socket, player_id: player_id, resources: PlayerProcess.get_state(player_id).resources)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Welcome, Colonist <%= @player_id %></h1>
      <p>Resources:</p>
      <ul>
        <li>Food: <%= @resources.food %></li>
        <li>Water: <%= @resources.water %></li>
        <li>Energy: <%= @resources.energy %></li>
      </ul>
    </div>
    """
  end

  defp generate_anonymous_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end
