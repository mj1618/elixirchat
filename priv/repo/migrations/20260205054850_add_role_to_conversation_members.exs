defmodule Elixirchat.Repo.Migrations.AddRoleToConversationMembers do
  use Ecto.Migration

  def change do
    alter table(:conversation_members) do
      add :role, :string, default: "member", null: false
    end

    # Set the oldest member as owner for existing group conversations
    # This ensures existing groups have proper ownership
    execute """
      UPDATE conversation_members cm
      SET role = 'owner'
      WHERE cm.id IN (
        SELECT DISTINCT ON (cm2.conversation_id) cm2.id
        FROM conversation_members cm2
        JOIN conversations c ON c.id = cm2.conversation_id
        WHERE c.type = 'group'
        ORDER BY cm2.conversation_id, cm2.inserted_at ASC
      )
    """, ""
  end
end
