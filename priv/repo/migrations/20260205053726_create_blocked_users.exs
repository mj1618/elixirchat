defmodule Elixirchat.Repo.Migrations.CreateBlockedUsers do
  use Ecto.Migration

  def change do
    create table(:blocked_users) do
      add :blocked_at, :utc_datetime, null: false
      add :blocker_id, references(:users, on_delete: :delete_all), null: false
      add :blocked_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:blocked_users, [:blocker_id, :blocked_id])
    create index(:blocked_users, [:blocked_id])
  end
end
