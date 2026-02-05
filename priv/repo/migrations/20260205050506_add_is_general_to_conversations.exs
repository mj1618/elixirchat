defmodule Elixirchat.Repo.Migrations.AddIsGeneralToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :is_general, :boolean, default: false, null: false
    end

    # Unique partial index ensures only one conversation can be the General group
    create unique_index(:conversations, [:is_general],
      where: "is_general = true",
      name: :conversations_is_general_unique_index
    )
  end
end
