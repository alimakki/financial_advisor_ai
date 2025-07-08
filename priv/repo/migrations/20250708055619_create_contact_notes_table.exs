defmodule FinancialAdvisorAi.Repo.Migrations.CreateContactNotesTable do
  use Ecto.Migration

  def change do
    create table(:contact_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      add :contact_embedding_id,
          references(:contact_embeddings, on_delete: :delete_all, type: :binary_id),
          null: false

      # HubSpot note ID for deduplication
      add :hubspot_note_id, :string
      add :content, :text, null: false

      # Assuming OpenAI's embedding size
      add :embedding, :vector, size: 1536
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:contact_notes, [:user_id])
    create index(:contact_notes, [:contact_embedding_id])
    create index(:contact_notes, [:hubspot_note_id])

    create unique_index(:contact_notes, [:hubspot_note_id],
             where: "hubspot_note_id IS NOT NULL",
             name: :contact_notes_unique_hubspot_note_id_index
           )

    # pgvector search
    create index(:contact_notes, [:embedding], using: :ivfflat)
  end
end
