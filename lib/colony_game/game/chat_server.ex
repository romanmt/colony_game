defmodule ColonyGame.Game.ChatServer do
  @moduledoc """
  GenServer that manages anonymous chat messages for the colony game.

  Messages are completely anonymous - no player identifier is stored or broadcast.
  This supports the game's core design principle of anonymous social deduction.
  """
  use GenServer

  @max_messages 50

  # Client API

  @doc """
  Starts the ChatServer GenServer.
  """
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Sends an anonymous message to the chat.
  Returns :ok on success, {:error, reason} on failure.
  """
  @spec send_message(String.t()) :: :ok | {:error, atom()}
  def send_message(content) when is_binary(content) do
    content = String.trim(content)

    cond do
      content == "" ->
        {:error, :empty_message}

      String.length(content) > 500 ->
        {:error, :message_too_long}

      true ->
        GenServer.call(__MODULE__, {:send_message, content})
    end
  end

  def send_message(_), do: {:error, :invalid_message}

  @doc """
  Returns the list of recent messages (up to 50).
  Each message is a map with :content and :timestamp keys.
  """
  @spec get_messages() :: [map()]
  def get_messages do
    GenServer.call(__MODULE__, :get_messages)
  end

  # Server Callbacks

  @impl true
  def init(_arg) do
    {:ok, %{messages: []}}
  end

  @impl true
  def handle_call({:send_message, content}, _from, state) do
    message = %{
      content: content,
      timestamp: DateTime.utc_now()
    }

    # Add new message and keep only the last @max_messages
    messages = [message | state.messages] |> Enum.take(@max_messages)

    # Broadcast the new message to all subscribers
    Phoenix.PubSub.broadcast(
      ColonyGame.PubSub,
      "chat:lobby",
      {:new_chat_message, message}
    )

    {:reply, :ok, %{state | messages: messages}}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    # Return messages in chronological order (oldest first)
    {:reply, Enum.reverse(state.messages), state}
  end
end
