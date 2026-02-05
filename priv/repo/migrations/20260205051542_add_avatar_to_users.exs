defmodule Elixirchat.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_filename, :string
    end
  end
end
