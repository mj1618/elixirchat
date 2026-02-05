defmodule Elixirchat.Repo.Migrations.CreateGroupInvites do
  use Ecto.Migration

  def change do
    create table(:group_invites) do
      add :token, :string, null: false
      add :expires_at, :utc_datetime
      add :max_uses, :integer
      add :use_count, :integer, default: 0
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:group_invites, [:token])
    create index(:group_invites, [:conversation_id])
  end
end
