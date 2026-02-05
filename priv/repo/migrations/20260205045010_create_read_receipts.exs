defmodule Elixirchat.Repo.Migrations.CreateReadReceipts do
  use Ecto.Migration

  def change do
    create table(:read_receipts) do
      add :read_at, :utc_datetime, null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:read_receipts, [:message_id, :user_id])
    create index(:read_receipts, [:message_id])
    create index(:read_receipts, [:user_id])
  end
end
