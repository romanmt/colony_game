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
    <div class="max-w-lg mx-auto p-6 bg-gray-100 rounded-lg shadow-lg">
    <h1 class="text-2xl font-bold text-gray-800 mb-4">🚀 Welcome, Colonist <%= @player_id %></h1>
    <p class="text-lg text-gray-600 mb-2">🌎 Civilization Age: <%= @tick_counter %> ticks</p>

    <div class="bg-white p-4 rounded-lg shadow-md">
      <h2 class="text-xl font-semibold text-gray-700 mb-3">📊 Resources:</h2>
      <ul class="space-y-2">
        <li class="text-gray-700">🍞 Food: <strong><%= @resources.food %></strong></li>
        <li class="text-gray-700">💧 Water: <strong><%= @resources.water %></strong></li>
        <li class="text-gray-700">⚡ Energy: <strong><%= @resources.energy %></strong></li>
      </ul>
    </div>

    <div class="mt-4">
      <%= if @status == :idle do %>
        <button
          phx-click="forage"
          class="mt-4 px-6 py-2 bg-green-500 text-white font-semibold rounded-md shadow-md hover:bg-green-600 transition"
        >
          🌿 Forage for Food
        </button>
      <% else %>
        <p class="text-yellow-600 font-semibold mt-4">⏳ Currently <%= @status %>...</p>
      <% end %>
    </div>

    <%= if @flash[:error] do %>
      <p class="mt-4 text-red-600 font-semibold"><%= @flash[:error] %></p>
    <% end %>
    </div>

    """
  end

  defp generate_anonymous_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
end
