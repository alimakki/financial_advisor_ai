defmodule FinancialAdvisorAi.Repo.Migrations.ReplaceNotesProcessedWithTimestamp do
  use Ecto.Migration

  def change do
    alter table(:contact_embeddings) do
      # Remove the notes_processed boolean flag
      remove :notes_processed

      # Add timestamp to track when notes were last processed
      add :notes_last_processed_at, :utc_datetime_usec
    end

    # Remove the old index for notes_processed
    drop_if_exists index(:contact_embeddings, [:notes_processed])

    # Add index for the new timestamp field
    create index(:contact_embeddings, [:notes_last_processed_at])
  end
end
