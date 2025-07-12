defmodule FinancialAdvisorAi.Repo.Migrations.AddRulesTable do
  use Ecto.Migration

  def change do
    create table(:rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # e.x. email_received
      add :trigger, :string
      # e.x. %{from_not_in_hubspot: true}
      add :condition, :map
      # e.x. [%{type: "add_contact"}, %{type: "log_note"}]
      add :actions, {:array, :map}

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:rules, [:user_id])
    create index(:rules, [:trigger])
    create index(:rules, [:trigger, :user_id])
  end
end
