defmodule Elixirchat.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status, :string, size: 100
      add :status_updated_at, :utc_datetime
    end
  end
end
