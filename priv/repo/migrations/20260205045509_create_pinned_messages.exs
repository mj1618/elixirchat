defmodule Elixirchat.Repo.Migrations.CreatePinnedMessages do
  use Ecto.Migration

  def change do
    create table(:pinned_messages) do
      add :pinned_at, :utc_datetime, null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :pinned_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:pinned_messages, [:message_id])
    create index(:pinned_messages, [:conversation_id])
  end
end
