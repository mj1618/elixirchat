defmodule Elixirchat.Repo.Migrations.AddForwardingToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :forwarded_from_message_id, references(:messages, on_delete: :nilify_all)
      add :forwarded_from_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:messages, [:forwarded_from_message_id])
  end
end
