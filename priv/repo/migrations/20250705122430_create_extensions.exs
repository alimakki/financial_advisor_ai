defmodule FinancialAdvisorAi.Repo.Migrations.CreateExtensions do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS vector"
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    execute "CREATE EXTENSION IF NOT EXISTS citext"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
