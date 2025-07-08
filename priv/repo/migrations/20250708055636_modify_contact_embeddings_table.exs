defmodule FinancialAdvisorAi.Repo.Migrations.ModifyContactEmbeddingsTable do
  use Ecto.Migration

  def change do
    alter table(:contact_embeddings) do
      # Remove the notes field since notes will be in separate table
      remove :notes

      # Update content field to not include notes
      modify :content, :text, null: false

      # Add a flag to indicate if notes have been processed separately
      add :notes_processed, :boolean, default: false
    end

    # Add index for the new flag
    create index(:contact_embeddings, [:notes_processed])
  end
end
