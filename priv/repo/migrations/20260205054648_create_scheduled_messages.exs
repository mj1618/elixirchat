defmodule Elixirchat.Repo.Migrations.CreateScheduledMessages do
  use Ecto.Migration

  def change do
    create table(:scheduled_messages) do
      add :content, :text, null: false
      add :scheduled_for, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:users, on_delete: :delete_all), null: false
      add :reply_to_id, references(:messages, on_delete: :nilify_all)

      timestamps()
    end

    create index(:scheduled_messages, [:sender_id])
    create index(:scheduled_messages, [:scheduled_for])
    create index(:scheduled_messages, [:conversation_id])
    # Index for finding due messages efficiently
    create index(:scheduled_messages, [:scheduled_for, :sent_at, :cancelled_at])
  end
end
