defmodule Elixirchat.Chat.StarredMessage do
  @moduledoc """
  Schema for user-starred messages.
  Starred messages are personal bookmarks - only visible to the user who starred them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message
  alias Elixirchat.Accounts.User

  schema "starred_messages" do
    field :starred_at, :utc_datetime

    belongs_to :message, Message
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Creates a changeset for a starred message.
  """
  def changeset(starred_message, attrs) do
    starred_message
    |> cast(attrs, [:starred_at, :message_id, :user_id])
    |> validate_required([:starred_at, :message_id, :user_id])
    |> unique_constraint([:message_id, :user_id], message: "message already starred")
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end
end
