defmodule Elixirchat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Conversation, Reaction, Attachment, LinkPreview, ThreadReply}
  alias Elixirchat.Accounts.User

  schema "messages" do
    field :content, :string
    field :edited_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :thread_reply_count, :integer, virtual: true, default: 0

    belongs_to :conversation, Conversation
    belongs_to :sender, User, foreign_key: :sender_id
    belongs_to :reply_to, __MODULE__
    belongs_to :forwarded_from_message, __MODULE__
    belongs_to :forwarded_from_user, User
    has_many :reactions, Reaction
    has_many :attachments, Attachment
    has_many :thread_replies, ThreadReply, foreign_key: :parent_message_id
    many_to_many :link_previews, LinkPreview, join_through: "message_link_previews"

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :conversation_id, :sender_id, :reply_to_id])
    |> sanitize_content()
    |> validate_required([:content, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  @doc """
  Changeset for editing a message's content.
  """
  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :edited_at])
    |> sanitize_content()
    |> validate_required([:content, :edited_at])
    |> validate_length(:content, min: 1, max: 5000)
  end

  # Sanitize content by removing null bytes and other dangerous control characters
  # Preserves newlines, tabs, and standard printable characters
  defp sanitize_content(changeset) do
    case get_change(changeset, :content) do
      nil -> changeset
      content ->
        sanitized = content
          # Remove null bytes
          |> String.replace(<<0>>, "")
          # Remove other dangerous control characters (keep \n, \r, \t)
          |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
          # Normalize unicode to prevent homograph attacks
          |> String.normalize(:nfc)

        put_change(changeset, :content, sanitized)
    end
  end

  @doc """
  Changeset for soft deleting a message.
  """
  def delete_changeset(message, attrs) do
    message
    |> cast(attrs, [:deleted_at])
    |> validate_required([:deleted_at])
  end

  @doc """
  Changeset for forwarding a message.
  """
  def forward_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :conversation_id, :sender_id, :forwarded_from_message_id, :forwarded_from_user_id])
    |> sanitize_content()
    |> validate_required([:content, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:forwarded_from_message_id)
    |> foreign_key_constraint(:forwarded_from_user_id)
  end
end
