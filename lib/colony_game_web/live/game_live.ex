defmodule ColonyGameWeb.GameLive do
  use Phoenix.LiveView
  require ColonyGameWeb.Endpoint
  require Logger

  alias ColonyGame.Game.{PlayerSupervisor, PlayerProcess, ChatServer, PlayerPresence}

  # Maximum resource value for percentage calculations
  @max_resource 200

  @impl true
  def mount(_params, _session, socket) do
    player_id = generate_anonymous_id()

    Logger.info("Starting player process for ID: #{player_id}")
    PlayerSupervisor.start_player(player_id)

    if connected?(socket) do
      ColonyGameWeb.Endpoint.subscribe("player:#{player_id}")
      # Subscribe to chat updates
      Phoenix.PubSub.subscribe(ColonyGame.PubSub, "chat:lobby")
      # Subscribe to presence updates for anonymous player indicators
      Phoenix.PubSub.subscribe(ColonyGame.PubSub, PlayerPresence.presence_topic())
    end

    state = PlayerProcess.get_state(player_id)
    messages = ChatServer.get_messages()
    # Get initial presence summary (anonymous aggregate data)
    presence = PlayerPresence.get_presence_summary()

    {:ok,
     assign(socket,
       player_id: player_id,
       resources: state.resources,
       status: :idle,
       tick_counter: state.tick_counter,
       foraging_ticks: Map.get(state, :foraging_ticks, 0),
       foraging_location: Map.get(state, :foraging_location),
       chat_messages: messages,
       chat_open: false,
       chat_input: "",
       # Presence data (anonymous)
       presence: presence
     )}
  end

  @impl true
  def handle_info(
        %{
          event: "tick_update",
          payload: %{resources: resources, status: status, tick_counter: tick} = payload
        },
        socket
      ) do
    foraging_ticks = Map.get(payload, :foraging_ticks, 0)
    foraging_location = Map.get(payload, :foraging_location)
    {:noreply, assign(socket,
      resources: resources,
      status: status,
      tick_counter: tick,
      foraging_ticks: foraging_ticks,
      foraging_location: foraging_location
    )}
  end

  @impl true
  def handle_info({:new_chat_message, message}, socket) do
    # Add new message to the list (newest at the end for display)
    messages = socket.assigns.chat_messages ++ [message]
    # Keep only last 50 messages
    messages = Enum.take(messages, -50)
    {:noreply, assign(socket, chat_messages: messages)}
  end

  @impl true
  def handle_info({:presence_update, presence}, socket) do
    # Update anonymous presence data (player counts and activity)
    {:noreply, assign(socket, presence: presence)}
  end

  @impl true
  def handle_event("forage", %{"location" => location}, socket) do
    location_atom = String.to_existing_atom(location)
    case PlayerProcess.forage(socket.assigns.player_id, location_atom) do
      {:ok, new_state} ->
        {:noreply,
         assign(socket,
           status: new_state.status,
           foraging_ticks: new_state.foraging_ticks,
           foraging_location: new_state.foraging_location
         )}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("forage", _params, socket) do
    # Default to forest for backwards compatibility
    case PlayerProcess.forage(socket.assigns.player_id, :forest) do
      {:ok, new_state} ->
        {:noreply,
         assign(socket,
           status: new_state.status,
           foraging_ticks: new_state.foraging_ticks,
           foraging_location: new_state.foraging_location
         )}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}
  end

  @impl true
  def handle_event("send_chat", %{"message" => message}, socket) do
    case ChatServer.send_message(message) do
      :ok ->
        {:noreply, assign(socket, chat_input: "")}

      {:error, :empty_message} ->
        {:noreply, socket}

      {:error, :message_too_long} ->
        {:noreply, put_flash(socket, :error, "Message too long (max 500 characters)")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
  def handle_event("update_chat_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, chat_input: message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-container">
      <!-- Toast Notifications -->
      <%= if @flash[:error] do %>
        <div class="toast toast--error">
          <%= @flash[:error] %>
        </div>
      <% end %>

      <!-- Survivor Count Header -->
      <div class="presence-header">
        <div class="survivor-count">
          <span class="survivor-icon"></span>
          <span class="survivor-text"><%= survivor_count_text(@presence.total_count) %></span>
        </div>
        <%= if @presence.foraging_count > 0 do %>
          <div class="activity-indicator activity-indicator--foraging">
            <%= activity_text(@presence.foraging_count, :foraging) %>
          </div>
        <% end %>
      </div>

      <!-- Resource Bars at Top -->
      <div class="resource-bar-container">
        <!-- Food Bar -->
        <div class="resource-bar">
          <div class="resource-icon resource-icon--food">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
              <path d="M18.06 22.99h1.66c.84 0 1.53-.64 1.63-1.46L23 5.05l-5 2V1h-2v8l-4-3-4 3V1H6v6.05l-5-2 1.66 16.48c.09.82.78 1.46 1.63 1.46h1.66l.66-5.74 1.55.35L7.5 23h9l-.66-5.4 1.55-.35.67 5.74z"/>
            </svg>
          </div>
          <div class="resource-track">
            <div class="resource-fill resource-fill--food" style={"width: #{resource_percentage(@resources.food)}%"}></div>
            <span class="resource-value"><%= @resources.food %></span>
          </div>
        </div>

        <!-- Water Bar -->
        <div class="resource-bar">
          <div class="resource-icon resource-icon--water">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
              <path d="M12 2c-5.33 4.55-8 8.48-8 11.8 0 4.98 3.8 8.2 8 8.2s8-3.22 8-8.2c0-3.32-2.67-7.25-8-11.8zm0 18c-3.35 0-6-2.57-6-6.2 0-2.34 1.95-5.44 6-9.14 4.05 3.7 6 6.79 6 9.14 0 3.63-2.65 6.2-6 6.2z"/>
            </svg>
          </div>
          <div class="resource-track">
            <div class="resource-fill resource-fill--water" style={"width: #{resource_percentage(@resources.water)}%"}></div>
            <span class="resource-value"><%= @resources.water %></span>
          </div>
        </div>

        <!-- Energy Bar -->
        <div class="resource-bar">
          <div class="resource-icon resource-icon--energy">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
              <path d="M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z"/>
            </svg>
          </div>
          <div class="resource-track">
            <div class="resource-fill resource-fill--energy" style={"width: #{resource_percentage(@resources.energy)}%"}></div>
            <span class="resource-value"><%= @resources.energy %></span>
          </div>
        </div>
      </div>

      <!-- Central Game Area -->
      <div class="game-area">
        <!-- Status Indicator -->
        <div class={"status-indicator #{status_class(@status)}"}>
          <%= status_text(@status) %>
        </div>

        <!-- Colony Map with Anonymous Player Dots -->
        <div class="colony-map">
          <!-- Central colony structure -->
          <div class="colony-center">
            <div class="colony-building"></div>
          </div>

          <!-- Anonymous player dots - positions are random, no IDs visible -->
          <%= for {dot, index} <- Enum.with_index(@presence.player_dots) do %>
            <div
              class={"player-dot player-dot--#{dot.activity}"}
              style={"left: #{elem(dot.position, 0) * 100}%; top: #{elem(dot.position, 1) * 100}%;"}
              data-index={index}
            >
              <div class="player-dot-pulse"></div>
            </div>
          <% end %>
        </div>

        <!-- Foraging Progress Overlay -->
        <%= if @status == :foraging do %>
          <div class="foraging-overlay animate-fade-in">
            <div class="progress-ring">
              <div class="progress-ring-bg"></div>
              <div class="progress-ring-fill"></div>
              <div class="progress-icon">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#22c55e" class="w-10 h-10">
                  <path d="M18.06 22.99h1.66c.84 0 1.53-.64 1.63-1.46L23 5.05l-5 2V1h-2v8l-4-3-4 3V1H6v6.05l-5-2 1.66 16.48c.09.82.78 1.46 1.63 1.46h1.66l.66-5.74 1.55.35L7.5 23h9l-.66-5.4 1.55-.35.67 5.74z"/>
                </svg>
              </div>
            </div>
            <div class="progress-text">
              Gathering resources...
              <div class="progress-ticks">
                <%= for i <- 1..5 do %>
                  <div class={"progress-tick #{if i <= @foraging_ticks, do: "progress-tick--complete", else: ""}"}></div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Tick Counter -->
        <div class="tick-counter">
          <div class="tick-dot"></div>
          <span>Age: <%= @tick_counter %></span>
        </div>
      </div>

      <!-- Action Buttons at Bottom -->
      <div class="action-bar">
        <%= if @status == :idle do %>
          <button phx-click="forage" class="action-btn action-btn--primary">
            <span class="action-btn-icon">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
                <path d="M18.06 22.99h1.66c.84 0 1.53-.64 1.63-1.46L23 5.05l-5 2V1h-2v8l-4-3-4 3V1H6v6.05l-5-2 1.66 16.48c.09.82.78 1.46 1.63 1.46h1.66l.66-5.74 1.55.35L7.5 23h9l-.66-5.4 1.55-.35.67 5.74z"/>
              </svg>
            </span>
            <span class="action-btn-label">Forage</span>
          </button>
        <% else %>
          <button class="action-btn action-btn--disabled" disabled>
            <span class="action-btn-icon">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
                <path d="M18.06 22.99h1.66c.84 0 1.53-.64 1.63-1.46L23 5.05l-5 2V1h-2v8l-4-3-4 3V1H6v6.05l-5-2 1.66 16.48c.09.82.78 1.46 1.63 1.46h1.66l.66-5.74 1.55.35L7.5 23h9l-.66-5.4 1.55-.35.67 5.74z"/>
              </svg>
            </span>
            <span class="action-btn-label">Foraging...</span>
          </button>
        <% end %>

        <button class="action-btn action-btn--secondary">
          <span class="action-btn-icon">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
              <path d="M19 12h-2v3h-3v2h5v-5zM7 9h3V7H5v5h2V9zm14-6H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16.01H3V4.99h18v14.02z"/>
            </svg>
          </span>
          <span class="action-btn-label">Build</span>
        </button>

        <button phx-click="toggle_chat" class={"action-btn #{if @chat_open, do: "action-btn--chat-active", else: "action-btn--secondary"}"}>
          <span class="action-btn-icon">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6">
              <path d="M21 6h-2v9H6v2c0 .55.45 1 1 1h11l4 4V7c0-.55-.45-1-1-1zm-4 6V3c0-.55-.45-1-1-1H3c-.55 0-1 .45-1 1v14l4-4h10c.55 0 1-.45 1-1z"/>
            </svg>
          </span>
          <span class="action-btn-label">Chat</span>
        </button>
      </div>

      <!-- Chat Panel (Collapsible Drawer) -->
      <%= if @chat_open do %>
        <div class="chat-panel animate-fade-in">
          <div class="chat-header">
            <span class="chat-title">Colony Chat</span>
            <button phx-click="toggle_chat" class="chat-close-btn">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
                <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
              </svg>
            </button>
          </div>

          <div id="chat-messages" class="chat-messages" phx-hook="ScrollToBottom">
            <%= if Enum.empty?(@chat_messages) do %>
              <p class="chat-empty">No messages yet. Say something!</p>
            <% else %>
              <%= for message <- @chat_messages do %>
                <div class="chat-message">
                  <p class="chat-message-text"><%= message.content %></p>
                  <span class="chat-message-time"><%= format_timestamp(message.timestamp) %></span>
                </div>
              <% end %>
            <% end %>
          </div>

          <form phx-submit="send_chat" class="chat-input-form">
            <input
              type="text"
              name="message"
              value={@chat_input}
              phx-change="update_chat_input"
              placeholder="Type anonymously..."
              class="chat-input"
              maxlength="500"
              autocomplete="off"
            />
            <button type="submit" class="chat-send-btn">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5">
                <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
              </svg>
            </button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions for template
  defp resource_percentage(value) do
    min(100, round(value / @max_resource * 100))
  end

  defp status_class(:idle), do: "status-indicator--idle"
  defp status_class(:foraging), do: "status-indicator--foraging"
  defp status_class(_), do: "status-indicator--idle"

  defp status_text(:idle), do: "Ready"
  defp status_text(:foraging), do: "Foraging"
  defp status_text(status), do: status |> to_string() |> String.capitalize()

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp generate_anonymous_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  # Presence helper functions

  defp survivor_count_text(1), do: "1 survivor in colony"
  defp survivor_count_text(count), do: "#{count} survivors in colony"

  defp activity_text(1, :foraging), do: "Someone is foraging..."
  defp activity_text(count, :foraging), do: "#{count} survivors foraging..."
  defp activity_text(_, _), do: ""
end
