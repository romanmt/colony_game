defmodule ColonyGameWeb.GameLive do
  use Phoenix.LiveView
  require Logger

  alias ColonyGame.Game.{PlayerSupervisor, PlayerProcess}

  @impl true
  def mount(_params, _session, socket) do
    player_id = generate_anonymous_id()

    Logger.info("Starting player process for ID: #{player_id}")
    PlayerSupervisor.start_player(player_id)

    if connected?(socket), do: Process.send_after(self(), :tick, 5000)

    {:ok,
     assign(socket, player_id: player_id, resources: PlayerProcess.get_state(player_id).resources)}
  end

  @impl true
  def handle_info(:tick, socket) do
    new_resources = PlayerProcess.get_state(socket.assigns.player_id).resources
    # Reschedule the next tick
    Process.send_after(self(), :tick, 5000)
    {:noreply, assign(socket, resources: new_resources)}
  end

  @impl true
  def handle_event("forage", _params, socket) do
    case ColonyGame.Game.ForagingServer.forage(socket.assigns.player_id) do
      {:ok, amount} ->
        new_resources = PlayerProcess.get_state(socket.assigns.player_id).resources
        {:noreply, assign(socket, resources: new_resources)}

      :empty ->
        Logger.info("out of food")

        socket =
          socket
          |> put_flash(:error, "No food left!")

        {:noreply, socket}
    end
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

      <button phx-click="forage">Forage for Food</button>

      <p class="alert alert-danger" role="alert" phx-click="lv:clear-flash" phx-value-key="error">
        <%= live_flash(@flash, :error) %>
      </p>
    </div>
    """
  end

  defp generate_anonymous_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end
