defmodule Elixirchat.Chat.MutedConversation do
  @moduledoc """
  Schema for tracking muted conversations per user.
  When a conversation is muted, the user won't receive browser notifications
  for new messages in that conversation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.Conversation

  schema "muted_conversations" do
    belongs_to :user, User
    belongs_to :conversation, Conversation

    timestamps(updated_at: false)
  end

  @doc """
  Creates a changeset for a muted conversation record.
  """
  def changeset(muted_conversation, attrs) do
    muted_conversation
    |> cast(attrs, [:user_id, :conversation_id])
    |> validate_required([:user_id, :conversation_id])
    |> unique_constraint([:user_id, :conversation_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:conversation_id)
  end
end
