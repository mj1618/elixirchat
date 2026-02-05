defmodule Elixirchat.Chat.ThreadReply do
  @moduledoc """
  Schema for thread replies - replies to messages that appear in a thread
  rather than the main conversation view.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message
  alias Elixirchat.Accounts.User

  schema "thread_replies" do
    field :content, :string
    field :also_sent_to_channel, :boolean, default: false

    belongs_to :parent_message, Message
    belongs_to :user, User

    timestamps()
  end

  def changeset(thread_reply, attrs) do
    thread_reply
    |> cast(attrs, [:content, :also_sent_to_channel, :parent_message_id, :user_id])
    |> validate_required([:content, :parent_message_id, :user_id])
    |> validate_length(:content, min: 1, max: 5000)
    |> foreign_key_constraint(:parent_message_id)
    |> foreign_key_constraint(:user_id)
  end
end
