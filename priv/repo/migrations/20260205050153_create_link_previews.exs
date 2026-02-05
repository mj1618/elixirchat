defmodule Elixirchat.Repo.Migrations.CreateLinkPreviews do
  use Ecto.Migration

  def change do
    # Create link_previews table for caching fetched metadata
    create table(:link_previews) do
      add :url, :string, null: false
      add :url_hash, :string, null: false
      add :title, :string
      add :description, :text
      add :image_url, :string
      add :site_name, :string
      add :fetched_at, :utc_datetime

      timestamps()
    end

    create unique_index(:link_previews, [:url_hash])

    # Create join table for many-to-many relationship
    create table(:message_link_previews) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :link_preview_id, references(:link_previews, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:message_link_previews, [:message_id])
    create unique_index(:message_link_previews, [:message_id, :link_preview_id])
  end
end
