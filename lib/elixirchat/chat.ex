defmodule Elixirchat.Chat do
  @moduledoc """
  The Chat context for managing conversations and messages.
  """

  import Ecto.Query, warn: false

  alias Elixirchat.Repo
  alias Elixirchat.Chat.{Conversation, ConversationMember, Message}
  alias Elixirchat.Accounts.User
  alias Elixirchat.Agent

  @doc """
  Gets a conversation by id with members preloaded.
  """
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(members: :user)
  end

  @doc """
  Gets or creates a direct conversation between two users.
  """
  def get_or_create_direct_conversation(user1_id, user2_id) do
    # Find existing direct conversation between these two users
    query =
      from c in Conversation,
        where: c.type == "direct",
        join: m1 in ConversationMember, on: m1.conversation_id == c.id and m1.user_id == ^user1_id,
        join: m2 in ConversationMember, on: m2.conversation_id == c.id and m2.user_id == ^user2_id,
        select: c

    case Repo.one(query) do
      nil -> create_direct_conversation(user1_id, user2_id)
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Creates a direct conversation between two users.
  """
  def create_direct_conversation(user1_id, user2_id) do
    Repo.transaction(fn ->
      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{type: "direct"})
        |> Repo.insert()

      {:ok, _} =
        %ConversationMember{}
        |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user1_id})
        |> Repo.insert()

      {:ok, _} =
        %ConversationMember{}
        |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user2_id})
        |> Repo.insert()

      conversation
    end)
  end

  @doc """
  Lists all conversations for a user with last message and other member info.
  """
  def list_user_conversations(user_id) do
    query =
      from c in Conversation,
        join: m in ConversationMember, on: m.conversation_id == c.id,
        where: m.user_id == ^user_id,
        preload: [members: :user],
        order_by: [desc: c.updated_at]

    conversations = Repo.all(query)

    # Fetch last message for each conversation
    Enum.map(conversations, fn conv ->
      last_message = get_last_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      Map.merge(conv, %{last_message: last_message, unread_count: unread_count})
    end)
  end

  @doc """
  Gets the last message in a conversation.
  """
  def get_last_message(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.inserted_at],
      limit: 1,
      preload: [:sender]
    )
    |> Repo.one()
  end

  @doc """
  Gets unread message count for a user in a conversation.
  """
  def get_unread_count(conversation_id, user_id) do
    member =
      from(m in ConversationMember,
        where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
      )
      |> Repo.one()

    case member do
      nil ->
        0

      %{last_read_at: nil} ->
        from(m in Message,
          where: m.conversation_id == ^conversation_id and m.sender_id != ^user_id
        )
        |> Repo.aggregate(:count)

      %{last_read_at: last_read_at} ->
        from(m in Message,
          where:
            m.conversation_id == ^conversation_id and
              m.sender_id != ^user_id and
              m.inserted_at > ^last_read_at
        )
        |> Repo.aggregate(:count)
    end
  end

  @doc """
  Lists messages in a conversation.
  """
  def list_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.inserted_at],
        preload: [:sender]

    query =
      if before_id do
        from m in query, where: m.id < ^before_id
      else
        query
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Sends a message in a conversation.
  """
  def send_message(conversation_id, sender_id, content) do
    result =
      %Message{}
      |> Message.changeset(%{
        content: content,
        conversation_id: conversation_id,
        sender_id: sender_id
      })
      |> Repo.insert()

    case result do
      {:ok, message} ->
        # Update conversation's updated_at timestamp
        Repo.get!(Conversation, conversation_id)
        |> Ecto.Changeset.change(%{updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
        |> Repo.update()

        # Preload sender for the response
        message = Repo.preload(message, :sender)

        # Broadcast the message
        broadcast_message(conversation_id, message)

        # Check for @agent mention and process asynchronously
        # Don't process agent messages to avoid infinite loops
        unless Agent.is_agent?(sender_id) do
          maybe_process_agent_mention(conversation_id, content)
        end

        {:ok, message}

      error ->
        error
    end
  end

  # Spawns an async task to process @agent mentions
  defp maybe_process_agent_mention(conversation_id, content) do
    if Agent.contains_mention?(content) do
      Task.Supervisor.start_child(
        Elixirchat.TaskSupervisor,
        fn -> Agent.process_message(conversation_id, content) end
      )
    end

    :ok
  end

  @doc """
  Marks a conversation as read for a user.
  """
  def mark_conversation_read(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      member ->
        member
        |> ConversationMember.changeset(%{last_read_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a user is a member of a conversation.
  """
  def member?(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets the other user in a direct conversation.
  """
  def get_other_user(%Conversation{type: "direct", members: members}, current_user_id) do
    members
    |> Enum.find(fn m -> m.user_id != current_user_id end)
    |> case do
      nil -> nil
      member -> member.user
    end
  end

  def get_other_user(_, _), do: nil

  @doc """
  Subscribes to conversation updates.
  """
  def subscribe(conversation_id) do
    Phoenix.PubSub.subscribe(Elixirchat.PubSub, "conversation:#{conversation_id}")
  end

  defp broadcast_message(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:new_message, message}
    )
  end

  @doc """
  Broadcasts that a user started typing in a conversation.
  """
  def broadcast_typing_start(conversation_id, user) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:user_typing, %{user_id: user.id, username: user.username}}
    )
  end

  @doc """
  Broadcasts that a user stopped typing in a conversation.
  """
  def broadcast_typing_stop(conversation_id, user_id) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:user_stopped_typing, %{user_id: user_id}}
    )
  end

  @doc """
  Searches users by username (excluding the current user).
  """
  def search_users(query, current_user_id) when byte_size(query) > 0 do
    search_term = "%#{query}%"

    from(u in User,
      where: u.id != ^current_user_id,
      where: ilike(u.username, ^search_term),
      limit: 10,
      order_by: u.username
    )
    |> Repo.all()
  end

  def search_users(_, _), do: []

  # ===============================
  # Group Chat Functions
  # ===============================

  @doc """
  Creates a group conversation with a name and initial members.
  The creator is automatically added as a member.
  """
  def create_group_conversation(name, member_ids) when is_list(member_ids) and length(member_ids) >= 1 do
    Repo.transaction(fn ->
      # Create the conversation
      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{type: "group", name: name})
        |> Repo.insert()

      # Add all members
      Enum.each(member_ids, fn user_id ->
        {:ok, _} =
          %ConversationMember{}
          |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user_id})
          |> Repo.insert()
      end)

      conversation |> Repo.preload(members: :user)
    end)
  end

  def create_group_conversation(_, _), do: {:error, :invalid_members}

  @doc """
  Adds a user to an existing group conversation.
  """
  def add_member_to_group(conversation_id, user_id) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      %ConversationMember{}
      |> ConversationMember.changeset(%{conversation_id: conversation_id, user_id: user_id})
      |> Repo.insert()
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Removes a user from a group conversation (or allows a user to leave).
  """
  def remove_member_from_group(conversation_id, user_id) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      from(m in ConversationMember,
        where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        member -> Repo.delete(member)
      end
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Updates the name of a group conversation.
  """
  def update_group_name(conversation_id, new_name) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      conversation
      |> Conversation.changeset(%{name: new_name})
      |> Repo.update()
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Lists all members of a conversation.
  """
  def list_group_members(conversation_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  @doc """
  Gets the member count for a conversation.
  """
  def get_member_count(conversation_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id
    )
    |> Repo.aggregate(:count)
  end
end
