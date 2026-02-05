defmodule Elixirchat.Repo.Migrations.CreateMutedConversations do
  use Ecto.Migration

  def change do
    create table(:muted_conversations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:muted_conversations, [:user_id, :conversation_id])
    create index(:muted_conversations, [:user_id])
  end
end
