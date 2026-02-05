defmodule Elixirchat.Repo.Migrations.CreateStarredMessages do
  use Ecto.Migration

  def change do
    create table(:starred_messages) do
      add :starred_at, :utc_datetime, null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:starred_messages, [:message_id, :user_id])
    create index(:starred_messages, [:user_id])
  end
end
