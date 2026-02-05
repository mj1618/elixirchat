defmodule Elixirchat.Repo.Migrations.CreateThreadReplies do
  use Ecto.Migration

  def change do
    create table(:thread_replies) do
      add :content, :text, null: false
      add :also_sent_to_channel, :boolean, default: false, null: false
      add :parent_message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:thread_replies, [:parent_message_id])
    create index(:thread_replies, [:user_id])
  end
end
