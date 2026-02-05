defmodule Elixirchat.Chat.Attachment do
  @moduledoc """
  Schema for file/image attachments on messages.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message

  @allowed_types ~w(image/jpeg image/png image/gif image/webp application/pdf text/plain text/markdown)
  @max_size 10 * 1024 * 1024  # 10MB

  schema "attachments" do
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :message, Message

    timestamps()
  end

  @doc """
  Creates a changeset for an attachment.
  """
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :original_filename, :content_type, :size, :message_id])
    |> validate_required([:filename, :original_filename, :content_type, :size])
    |> validate_inclusion(:content_type, @allowed_types, message: "file type not allowed")
    |> validate_number(:size, less_than_or_equal_to: @max_size, message: "file too large (max 10MB)")
    |> foreign_key_constraint(:message_id)
  end

  @doc """
  Returns true if the attachment is an image.
  """
  def image?(attachment) do
    String.starts_with?(attachment.content_type, "image/")
  end

  @doc """
  Returns the list of allowed content types.
  """
  def allowed_types, do: @allowed_types

  @doc """
  Returns the maximum file size in bytes.
  """
  def max_size, do: @max_size

  @doc """
  Returns allowed file extensions for the upload configuration.
  """
  def allowed_extensions do
    ~w(.jpg .jpeg .png .gif .webp .pdf .txt .md)
  end
end
