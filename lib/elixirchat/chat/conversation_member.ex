defmodule Elixirchat.Chat.ConversationMember do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Conversation
  alias Elixirchat.Accounts.User

  schema "conversation_members" do
    field :last_read_at, :utc_datetime
    field :pinned_at, :utc_datetime
    field :archived_at, :utc_datetime

    belongs_to :conversation, Conversation
    belongs_to :user, User

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:conversation_id, :user_id, :last_read_at])
    |> validate_required([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:conversation_id, :user_id])
  end

  def pin_changeset(member, attrs) do
    member
    |> cast(attrs, [:pinned_at])
  end

  @doc """
  Changeset for archiving/unarchiving a conversation membership.
  """
  def archive_changeset(member, attrs) do
    member
    |> cast(attrs, [:archived_at])
  end
end
