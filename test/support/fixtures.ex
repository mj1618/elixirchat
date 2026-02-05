defmodule Elixirchat.Fixtures do
  @moduledoc """
  Test fixtures for creating test data.
  """

  alias Elixirchat.Accounts
  alias Elixirchat.Chat

  @doc """
  Creates a user with the given attributes.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        username: "user_#{System.unique_integer([:positive])}",
        password: "password123"
      })
      |> Accounts.create_user()

    user
  end

  @doc """
  Creates a direct conversation between two users.
  """
  def conversation_fixture(user1, user2) do
    {:ok, conversation} = Chat.get_or_create_direct_conversation(user1.id, user2.id)
    conversation
  end

  @doc """
  Creates a message in a conversation.
  """
  def message_fixture(conversation, sender, attrs \\ %{}) do
    content = Map.get(attrs, :content, "Test message #{System.unique_integer([:positive])}")
    {:ok, message} = Chat.send_message(conversation.id, sender.id, content)
    message
  end
end
