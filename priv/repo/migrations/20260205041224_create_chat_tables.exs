defmodule Elixirchat.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :type, :string, null: false, default: "direct"  # "direct" or "group"
      add :name, :string  # Optional, used for group chats

      timestamps()
    end

    create table(:conversation_members) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime

      timestamps()
    end

    create index(:conversation_members, [:conversation_id])
    create index(:conversation_members, [:user_id])
    create unique_index(:conversation_members, [:conversation_id, :user_id])

    create table(:messages) do
      add :content, :text, null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:sender_id])
    create index(:messages, [:inserted_at])
  end
end
