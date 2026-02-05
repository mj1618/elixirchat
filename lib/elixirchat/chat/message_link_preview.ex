defmodule Elixirchat.Chat.MessageLinkPreview do
  @moduledoc """
  Join table schema for the many-to-many relationship between messages and link previews.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Message, LinkPreview}

  schema "message_link_previews" do
    belongs_to :message, Message
    belongs_to :link_preview, LinkPreview

    timestamps()
  end

  def changeset(message_link_preview, attrs) do
    message_link_preview
    |> cast(attrs, [:message_id, :link_preview_id])
    |> validate_required([:message_id, :link_preview_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:link_preview_id)
    |> unique_constraint([:message_id, :link_preview_id])
  end
end
