defmodule Elixirchat.Chat.GroupInvite do
  @moduledoc """
  Schema for group invite links.
  Allows users to share invite links to join group chats.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Accounts.User
  alias Elixirchat.Chat.Conversation

  schema "group_invites" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :max_uses, :integer
    field :use_count, :integer, default: 0

    belongs_to :conversation, Conversation
    belongs_to :created_by, User

    timestamps()
  end

  @doc """
  Changeset for creating/updating a group invite.
  """
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:token, :conversation_id, :created_by_id, :expires_at, :max_uses, :use_count])
    |> validate_required([:token, :conversation_id])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:created_by_id)
  end

  @doc """
  Generates a secure random token for invite links.
  Returns a URL-safe base64 encoded string.
  """
  def generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
