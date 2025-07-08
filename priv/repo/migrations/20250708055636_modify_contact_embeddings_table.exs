defmodule FinancialAdvisorAi.Repo.Migrations.ModifyContactEmbeddingsTable do
  use Ecto.Migration

  def change do
    alter table(:contact_embeddings) do
      # Remove the notes field since notes will be in separate table
      remove :notes

      # Update content field to not include notes
      modify :content, :text, null: false

      # Add timestamp to track when notes were last processed
      add :notes_last_processed_at, :utc_datetime_usec
    end

    # Add index for the new timestamp field
    create index(:contact_embeddings, [:notes_last_processed_at])
  end
end
