defmodule ColonyGameWeb.GameLive do
  use Phoenix.LiveView
  require ColonyGameWeb.Endpoint
  require Logger

  alias ColonyGame.Game.{PlayerSupervisor, PlayerProcess}

  @impl true
  def mount(_params, _session, socket) do
    player_id = generate_anonymous_id()

    Logger.info("Starting player process for ID: #{player_id}")
    PlayerSupervisor.start_player(player_id)

    if connected?(socket),
      do: ColonyGameWeb.Endpoint.subscribe("player:#{player_id}")

    state = PlayerProcess.get_state(player_id)

    {:ok,
     assign(socket,
       player_id: player_id,
       resources: state.resources,
       status: :idle,
       tick_counter: state.tick_counter
     )}
  end

  @impl true
  def handle_info(
        %{
          event: "tick_update",
          payload: %{resources: resources, status: status, tick_counter: tick}
        },
        socket
      ) do
    {:noreply, assign(socket, resources: resources, status: status, tick_counter: tick)}
  end

  @impl true
  def handle_event("forage", _params, socket) do
    case PlayerProcess.forage(socket.assigns.player_id) do
      {:ok, new_state} ->
        {:noreply,
         assign(socket, status: new_state.status, foraging_ticks: new_state.foraging_ticks)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Welcome, Colonist <%= @player_id %> <%= @status %></h1>
      <p>Civilization Age: <%= @tick_counter %></p>

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
