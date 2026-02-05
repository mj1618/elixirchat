defmodule Elixirchat.Chat.LinkPreview do
  @moduledoc """
  Schema for cached link preview metadata.
  Stores Open Graph and HTML metadata fetched from URLs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Elixirchat.Chat.Message

  schema "link_previews" do
    field :url, :string
    field :url_hash, :string
    field :title, :string
    field :description, :string
    field :image_url, :string
    field :site_name, :string
    field :fetched_at, :utc_datetime

    many_to_many :messages, Message, join_through: "message_link_previews"

    timestamps()
  end

  def changeset(link_preview, attrs) do
    link_preview
    |> cast(attrs, [:url, :title, :description, :image_url, :site_name, :fetched_at])
    |> validate_required([:url])
    |> generate_url_hash()
    |> unique_constraint(:url_hash)
  end

  defp generate_url_hash(changeset) do
    case get_change(changeset, :url) do
      nil -> changeset
      url -> put_change(changeset, :url_hash, hash_url(url))
    end
  end

  @doc """
  Generates a SHA256 hash for a URL (used for deduplication).
  """
  def hash_url(url) do
    :crypto.hash(:sha256, url)
    |> Base.encode16(case: :lower)
  end
end
