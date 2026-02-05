defmodule Elixirchat.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  def change do
    create table(:reactions) do
      add :emoji, :string, null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:reactions, [:message_id, :user_id, :emoji])
    create index(:reactions, [:message_id])
  end
end
