defmodule ColonyGame.Game.ChatServerTest do
  use ExUnit.Case, async: false

  alias ColonyGame.Game.ChatServer

  # Since ChatServer uses a named GenServer, we need to handle setup/teardown carefully

  setup do
    # Stop the server if it's running (from application supervision)
    if Process.whereis(ChatServer) do
      GenServer.stop(ChatServer, :normal)
      # Wait a moment for cleanup
      Process.sleep(10)
    end

    # Start a fresh server for each test
    {:ok, pid} = ChatServer.start_link([])

    on_exit(fn ->
      # Clean up after each test
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal)
      end
    end)

    {:ok, server_pid: pid}
  end

  describe "start_link/1" do
    test "starts the server successfully", %{server_pid: pid} do
      assert Process.alive?(pid)
      assert Process.whereis(ChatServer) == pid
    end

    test "initializes with empty messages" do
      messages = ChatServer.get_messages()
      assert messages == []
    end
  end

  describe "send_message/1" do
    test "sends a message successfully" do
      result = ChatServer.send_message("Hello, colony!")
      assert result == :ok
    end

    test "rejects empty messages" do
      result = ChatServer.send_message("")
      assert result == {:error, :empty_message}
    end

    test "rejects whitespace-only messages" do
      result = ChatServer.send_message("   ")
      assert result == {:error, :empty_message}
    end

    test "rejects messages longer than 500 characters" do
      long_message = String.duplicate("a", 501)
      result = ChatServer.send_message(long_message)
      assert result == {:error, :message_too_long}
    end

    test "accepts messages exactly 500 characters" do
      message = String.duplicate("a", 500)
      result = ChatServer.send_message(message)
      assert result == :ok
    end

    test "rejects non-string input" do
      result = ChatServer.send_message(123)
      assert result == {:error, :invalid_message}

      result = ChatServer.send_message(nil)
      assert result == {:error, :invalid_message}

      result = ChatServer.send_message(%{})
      assert result == {:error, :invalid_message}
    end

    test "trims whitespace from messages" do
      ChatServer.send_message("  hello  ")
      [message] = ChatServer.get_messages()
      assert message.content == "hello"
    end
  end

  describe "get_messages/0" do
    test "returns messages in chronological order (oldest first)" do
      ChatServer.send_message("first")
      ChatServer.send_message("second")
      ChatServer.send_message("third")

      messages = ChatServer.get_messages()

      assert length(messages) == 3
      assert Enum.at(messages, 0).content == "first"
      assert Enum.at(messages, 1).content == "second"
      assert Enum.at(messages, 2).content == "third"
    end

    test "each message has content and timestamp" do
      ChatServer.send_message("test message")

      [message] = ChatServer.get_messages()

      assert Map.has_key?(message, :content)
      assert Map.has_key?(message, :timestamp)
      assert message.content == "test message"
      assert %DateTime{} = message.timestamp
    end

    test "messages do NOT contain player identifiers" do
      ChatServer.send_message("anonymous message")

      [message] = ChatServer.get_messages()

      # Verify no player-identifying fields exist
      refute Map.has_key?(message, :player_id)
      refute Map.has_key?(message, :user_id)
      refute Map.has_key?(message, :sender)
      refute Map.has_key?(message, :author)
      refute Map.has_key?(message, :from)

      # Only expected keys should be present
      assert Map.keys(message) |> Enum.sort() == [:content, :timestamp]
    end
  end

  describe "message limit" do
    test "keeps only the last 50 messages" do
      # Send 60 messages
      for i <- 1..60 do
        ChatServer.send_message("message #{i}")
      end

      messages = ChatServer.get_messages()

      assert length(messages) == 50
      # First message should be "message 11" (messages 1-10 were dropped)
      assert Enum.at(messages, 0).content == "message 11"
      # Last message should be "message 60"
      assert Enum.at(messages, 49).content == "message 60"
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts new messages to subscribers" do
      # Subscribe to chat updates
      Phoenix.PubSub.subscribe(ColonyGame.PubSub, "chat:lobby")

      ChatServer.send_message("broadcast test")

      # Should receive the message
      assert_receive {:new_chat_message, message}, 1000
      assert message.content == "broadcast test"
      assert %DateTime{} = message.timestamp
    end

    test "broadcast message does not contain player identifier" do
      Phoenix.PubSub.subscribe(ColonyGame.PubSub, "chat:lobby")

      ChatServer.send_message("anonymous broadcast")

      assert_receive {:new_chat_message, message}, 1000

      # Verify anonymity in broadcast
      refute Map.has_key?(message, :player_id)
      refute Map.has_key?(message, :user_id)
      refute Map.has_key?(message, :sender)
      assert Map.keys(message) |> Enum.sort() == [:content, :timestamp]
    end
  end

  describe "concurrent access" do
    test "handles multiple simultaneous message sends" do
      # Spawn multiple concurrent message sends
      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            ChatServer.send_message("concurrent message #{i}")
          end)
        end)

      # Collect results
      results = Enum.map(tasks, &Task.await/1)

      # All sends should succeed
      assert Enum.all?(results, fn r -> r == :ok end)

      # All messages should be stored
      messages = ChatServer.get_messages()
      assert length(messages) == 20
    end
  end

  describe "server resilience" do
    test "server continues working after receiving invalid messages" do
      # Send some invalid messages
      ChatServer.send_message("")
      ChatServer.send_message(nil)
      ChatServer.send_message(123)

      # Server should still work
      assert ChatServer.send_message("valid message") == :ok
      assert length(ChatServer.get_messages()) == 1
    end
  end
end
