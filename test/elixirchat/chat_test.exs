defmodule Elixirchat.ChatTest do
  use Elixirchat.DataCase, async: true

  alias Elixirchat.Chat
  alias Elixirchat.Chat.Message

  import Elixirchat.Fixtures

  describe "create_direct_conversation/2" do
    test "creates a direct conversation between two users" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert conversation.type == "direct"
      assert Chat.member?(conversation.id, user1.id)
      assert Chat.member?(conversation.id, user2.id)
    end
  end

  describe "get_or_create_direct_conversation/2" do
    test "creates a new conversation when none exists" do
      user1 = user_fixture()
      user2 = user_fixture()

      assert {:ok, conversation} = Chat.get_or_create_direct_conversation(user1.id, user2.id)
      assert conversation.type == "direct"
    end

    test "returns existing conversation when one exists" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, conversation1} = Chat.get_or_create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.get_or_create_direct_conversation(user1.id, user2.id)

      assert conversation1.id == conversation2.id
    end

    test "returns same conversation regardless of user order" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, conversation1} = Chat.get_or_create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.get_or_create_direct_conversation(user2.id, user1.id)

      assert conversation1.id == conversation2.id
    end
  end

  describe "get_conversation!/1" do
    test "returns conversation with members preloaded" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      fetched = Chat.get_conversation!(conversation.id)

      assert fetched.id == conversation.id
      assert length(fetched.members) == 2
    end

    test "raises when conversation does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!(999_999)
      end
    end
  end

  describe "list_user_conversations/1" do
    test "returns conversations for a user" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conv1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conv2} = Chat.create_direct_conversation(user1.id, user3.id)

      conversations = Chat.list_user_conversations(user1.id)

      assert length(conversations) == 2
      ids = Enum.map(conversations, & &1.id)
      assert conv1.id in ids
      assert conv2.id in ids
    end

    test "returns empty list when user has no conversations" do
      user = user_fixture()
      assert Chat.list_user_conversations(user.id) == []
    end

    test "includes last_message and unread_count" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      Chat.send_message(conversation.id, user2.id, "Hello!")

      conversations = Chat.list_user_conversations(user1.id)
      conv = hd(conversations)

      assert conv.last_message.content == "Hello!"
      assert conv.unread_count == 1
    end
  end

  describe "send_message/3" do
    test "creates a message in the conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert {:ok, %Message{} = message} = Chat.send_message(conversation.id, user1.id, "Hello!")
      assert message.content == "Hello!"
      assert message.sender_id == user1.id
      assert message.conversation_id == conversation.id
    end

    test "returns sender preloaded" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      {:ok, message} = Chat.send_message(conversation.id, user1.id, "Hello!")
      assert message.sender.username == user1.username
    end

    test "fails with empty content" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert {:error, changeset} = Chat.send_message(conversation.id, user1.id, "")
      assert "can't be blank" in errors_on(changeset).content
    end

    test "fails with content longer than 5000 characters" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      long_content = String.duplicate("a", 5001)

      assert {:error, changeset} = Chat.send_message(conversation.id, user1.id, long_content)
      assert "should be at most 5000 character(s)" in errors_on(changeset).content
    end
  end

  describe "list_messages/2" do
    test "returns messages for a conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "Message 1")
      Chat.send_message(conversation.id, user2.id, "Message 2")
      Chat.send_message(conversation.id, user1.id, "Message 3")

      messages = Chat.list_messages(conversation.id)

      assert length(messages) == 3
      contents = Enum.map(messages, & &1.content)
      assert "Message 1" in contents
      assert "Message 2" in contents
      assert "Message 3" in contents
    end

    test "returns messages in chronological order" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "First")
      Chat.send_message(conversation.id, user2.id, "Second")
      Chat.send_message(conversation.id, user1.id, "Third")

      messages = Chat.list_messages(conversation.id)

      assert Enum.at(messages, 0).content == "First"
      assert Enum.at(messages, 1).content == "Second"
      assert Enum.at(messages, 2).content == "Third"
    end

    test "respects limit option" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      for i <- 1..10 do
        Chat.send_message(conversation.id, user1.id, "Message #{i}")
      end

      messages = Chat.list_messages(conversation.id, limit: 5)
      assert length(messages) == 5
    end

    test "returns empty list when no messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert Chat.list_messages(conversation.id) == []
    end
  end

  describe "member?/2" do
    test "returns true when user is a member" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert Chat.member?(conversation.id, user1.id) == true
      assert Chat.member?(conversation.id, user2.id) == true
    end

    test "returns false when user is not a member" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert Chat.member?(conversation.id, user3.id) == false
    end
  end

  describe "mark_conversation_read/2" do
    test "marks conversation as read" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)
      Chat.send_message(conversation.id, user2.id, "Hello!")

      # Initially unread
      conversations = Chat.list_user_conversations(user1.id)
      assert hd(conversations).unread_count == 1

      # Mark as read
      Chat.mark_conversation_read(conversation.id, user1.id)

      # Now no unread messages
      conversations = Chat.list_user_conversations(user1.id)
      assert hd(conversations).unread_count == 0
    end

    test "returns error for non-member" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      assert {:error, :not_found} = Chat.mark_conversation_read(conversation.id, user3.id)
    end
  end

  describe "get_other_user/2" do
    test "returns the other user in a direct conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      conversation = Chat.get_conversation!(conversation.id)
      other_user = Chat.get_other_user(conversation, user1.id)

      assert other_user.id == user2.id
    end

    test "returns nil for non-direct conversation" do
      # Create a conversation struct that's not a direct type
      assert Chat.get_other_user(%{type: "group"}, 1) == nil
    end
  end

  describe "search_users/2" do
    test "finds users by username prefix" do
      user1 = user_fixture(%{username: "alice"})
      _user2 = user_fixture(%{username: "bob"})
      searcher = user_fixture(%{username: "searcher"})

      results = Chat.search_users("ali", searcher.id)

      assert length(results) == 1
      assert hd(results).id == user1.id
    end

    test "excludes current user from results" do
      searcher = user_fixture(%{username: "alice"})

      results = Chat.search_users("alice", searcher.id)

      assert results == []
    end

    test "is case insensitive" do
      _user1 = user_fixture(%{username: "Alice"})
      searcher = user_fixture(%{username: "searcher"})

      results = Chat.search_users("ALICE", searcher.id)

      assert length(results) == 1
    end

    test "returns empty list for empty query" do
      searcher = user_fixture()

      assert Chat.search_users("", searcher.id) == []
    end

    test "limits results to 10" do
      searcher = user_fixture(%{username: "searcher"})
      for i <- 1..15 do
        user_fixture(%{username: "testuser#{i}"})
      end

      results = Chat.search_users("testuser", searcher.id)

      assert length(results) == 10
    end
  end

  describe "subscribe/1 and broadcasting" do
    test "subscribes to conversation topic" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      # Subscribe to the conversation
      :ok = Chat.subscribe(conversation.id)

      # Send a message (which should broadcast)
      {:ok, message} = Chat.send_message(conversation.id, user1.id, "Hello!")

      # Verify we receive the broadcast
      assert_receive {:new_message, received_message}
      assert received_message.id == message.id
    end
  end

  describe "typing indicators" do
    test "broadcast_typing_start/2 broadcasts user typing event" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      # Subscribe to the conversation
      :ok = Chat.subscribe(conversation.id)

      # Broadcast typing start
      :ok = Chat.broadcast_typing_start(conversation.id, user1)

      # Verify we receive the broadcast
      assert_receive {:user_typing, %{user_id: user_id, username: username}}
      assert user_id == user1.id
      assert username == user1.username
    end

    test "broadcast_typing_stop/2 broadcasts user stopped typing event" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      # Subscribe to the conversation
      :ok = Chat.subscribe(conversation.id)

      # Broadcast typing stop
      :ok = Chat.broadcast_typing_stop(conversation.id, user1.id)

      # Verify we receive the broadcast
      assert_receive {:user_stopped_typing, %{user_id: user_id}}
      assert user_id == user1.id
    end
  end

  describe "search_messages/2" do
    test "finds messages matching search query" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "Hello world")
      Chat.send_message(conversation.id, user2.id, "Hi there")
      Chat.send_message(conversation.id, user1.id, "Another hello message")

      results = Chat.search_messages(conversation.id, "hello")

      assert length(results) == 2
      contents = Enum.map(results, & &1.content)
      assert "Hello world" in contents
      assert "Another hello message" in contents
    end

    test "search is case insensitive" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "HELLO WORLD")

      results = Chat.search_messages(conversation.id, "hello")

      assert length(results) == 1
      assert hd(results).content == "HELLO WORLD"
    end

    test "returns empty list for query less than 2 characters" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "Hello world")

      assert Chat.search_messages(conversation.id, "h") == []
      assert Chat.search_messages(conversation.id, "") == []
    end

    test "returns messages ordered by most recent first" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "First test message")
      Chat.send_message(conversation.id, user2.id, "Second test message")
      Chat.send_message(conversation.id, user1.id, "Third test message")

      results = Chat.search_messages(conversation.id, "test")

      assert length(results) == 3
      # Results are ordered by descending inserted_at, so the order should be
      # newest to oldest. Since timestamps may be identical in tests, we just
      # verify all messages are present and result is sorted descending.
      contents = Enum.map(results, & &1.content)
      assert "First test message" in contents
      assert "Second test message" in contents
      assert "Third test message" in contents

      # Verify the ordering is descending by inserted_at
      timestamps = Enum.map(results, & &1.inserted_at)
      assert timestamps == Enum.sort(timestamps, {:desc, NaiveDateTime})
    end

    test "limits results to 20" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      for i <- 1..25 do
        Chat.send_message(conversation.id, user1.id, "Test message #{i}")
      end

      results = Chat.search_messages(conversation.id, "Test message")

      assert length(results) == 20
    end

    test "escapes special LIKE characters in query" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "50% discount")
      Chat.send_message(conversation.id, user2.id, "No discount")

      # The % character should be escaped and treated literally
      results = Chat.search_messages(conversation.id, "50%")

      assert length(results) == 1
      assert hd(results).content == "50% discount"
    end

    test "preloads sender information" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, conversation} = Chat.create_direct_conversation(user1.id, user2.id)

      Chat.send_message(conversation.id, user1.id, "Hello world")

      results = Chat.search_messages(conversation.id, "hello")

      assert length(results) == 1
      message = hd(results)
      assert message.sender.id == user1.id
      assert message.sender.username == user1.username
    end
  end

  describe "forward_message/4" do
    test "forwards a message to another conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user1.id, user3.id)

      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "Hello from original!")

      {:ok, forwarded_message} = Chat.forward_message(original_message.id, conversation2.id, user1.id)

      assert forwarded_message.content == "Hello from original!"
      assert forwarded_message.conversation_id == conversation2.id
      assert forwarded_message.sender_id == user1.id
      assert forwarded_message.forwarded_from_message_id == original_message.id
      assert forwarded_message.forwarded_from_user_id == user1.id
    end

    test "preloads forwarded_from_user on forwarded message" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user1.id, user3.id)

      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "Test message")

      {:ok, forwarded_message} = Chat.forward_message(original_message.id, conversation2.id, user1.id)

      # forwarded_from_user should be preloaded
      assert forwarded_message.forwarded_from_user.id == user1.id
      assert forwarded_message.forwarded_from_user.username == user1.username
    end

    test "returns error when forwarding deleted message" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user1.id, user3.id)

      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "To be deleted")

      # Mark message as deleted directly (avoiding time limit check in delete_message)
      original_message
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      |> Elixirchat.Repo.update!()

      assert {:error, :message_deleted} = Chat.forward_message(original_message.id, conversation2.id, user1.id)
    end

    test "returns error when sender is not a member of target conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()
      user4 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user3.id, user4.id)

      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "Cannot forward this")

      # user1 is not a member of conversation2
      assert {:error, :not_member} = Chat.forward_message(original_message.id, conversation2.id, user1.id)
    end

    test "allows forwarding message from another user" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user2.id, user3.id)

      # user1 sends original message
      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "Forward me!")

      # user2 forwards user1's message to conversation2
      {:ok, forwarded_message} = Chat.forward_message(original_message.id, conversation2.id, user2.id)

      # The forwarded message should be sent by user2 but show it was originally from user1
      assert forwarded_message.sender_id == user2.id
      assert forwarded_message.forwarded_from_user_id == user1.id
    end

    test "broadcasts forwarded message to target conversation" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      {:ok, conversation1} = Chat.create_direct_conversation(user1.id, user2.id)
      {:ok, conversation2} = Chat.create_direct_conversation(user1.id, user3.id)

      {:ok, original_message} = Chat.send_message(conversation1.id, user1.id, "To be forwarded")

      # Subscribe to target conversation
      :ok = Chat.subscribe(conversation2.id)

      {:ok, forwarded_message} = Chat.forward_message(original_message.id, conversation2.id, user1.id)

      # Should receive broadcast
      assert_receive {:new_message, received_message}
      assert received_message.id == forwarded_message.id
      assert received_message.forwarded_from_message_id == original_message.id
    end
  end
end
