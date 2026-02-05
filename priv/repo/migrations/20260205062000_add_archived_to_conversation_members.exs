defmodule Elixirchat.Repo.Migrations.AddArchivedToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :archived_at, :utc_datetime
    end

    create index(:conversation_members, [:user_id, :archived_at])
  end
end
