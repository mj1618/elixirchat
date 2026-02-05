defmodule Elixirchat.Chat.ScheduledMessage do
  @moduledoc """
  Schema for scheduled messages.
  Allows users to compose messages that will be sent at a future time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.{Conversation, Message}
  alias Elixirchat.Accounts.User

  schema "scheduled_messages" do
    field :content, :string
    field :scheduled_for, :utc_datetime
    field :sent_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :conversation, Conversation
    belongs_to :sender, User
    belongs_to :reply_to, Message

    timestamps()
  end

  @doc """
  Changeset for creating/updating a scheduled message.
  """
  def changeset(scheduled_message, attrs) do
    scheduled_message
    |> cast(attrs, [:content, :scheduled_for, :sent_at, :cancelled_at, :conversation_id, :sender_id, :reply_to_id])
    |> validate_required([:content, :scheduled_for, :conversation_id, :sender_id])
    |> validate_length(:content, min: 1, max: 10000)
    |> validate_scheduled_for_future()
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  @doc """
  Changeset for updating a scheduled message (content and/or time).
  Only works if the message hasn't been sent or cancelled.
  """
  def update_changeset(scheduled_message, attrs) do
    scheduled_message
    |> cast(attrs, [:content, :scheduled_for])
    |> validate_length(:content, min: 1, max: 10000)
    |> validate_scheduled_for_future()
  end

  @doc """
  Changeset for cancelling a scheduled message.
  """
  def cancel_changeset(scheduled_message, attrs) do
    scheduled_message
    |> cast(attrs, [:cancelled_at])
    |> validate_required([:cancelled_at])
  end

  @doc """
  Changeset for marking a scheduled message as sent.
  """
  def sent_changeset(scheduled_message, attrs) do
    scheduled_message
    |> cast(attrs, [:sent_at])
    |> validate_required([:sent_at])
  end

  defp validate_scheduled_for_future(changeset) do
    scheduled_for = get_field(changeset, :scheduled_for)
    
    if scheduled_for && DateTime.compare(scheduled_for, DateTime.utc_now()) != :gt do
      add_error(changeset, :scheduled_for, "must be in the future")
    else
      changeset
    end
  end
end
