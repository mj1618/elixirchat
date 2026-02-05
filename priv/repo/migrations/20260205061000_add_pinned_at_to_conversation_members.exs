defmodule Elixirchat.Repo.Migrations.AddPinnedAtToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :pinned_at, :utc_datetime, null: true
    end

    create index(:conversation_members, [:user_id, :pinned_at])
  end
end
