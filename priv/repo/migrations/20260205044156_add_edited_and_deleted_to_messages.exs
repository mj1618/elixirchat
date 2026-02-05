defmodule Elixirchat.Repo.Migrations.AddEditedAndDeletedToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :edited_at, :utc_datetime, null: true
      add :deleted_at, :utc_datetime, null: true
    end
  end
end
