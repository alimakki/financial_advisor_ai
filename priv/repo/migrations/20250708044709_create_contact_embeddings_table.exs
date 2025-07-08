defmodule FinancialAdvisorAi.Repo.Migrations.CreateContactEmbeddingsTable do
  use Ecto.Migration

  def change do
    # Contact embeddings for RAG
    create table(:contact_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      # HubSpot contact ID
      add :contact_id, :string, null: false
      add :firstname, :string
      add :lastname, :string
      add :email, :string
      add :company, :string
      add :phone, :string
      add :lifecycle_stage, :string
      add :lead_status, :string
      add :notes, :text
      add :content, :text

      # Assuming OpenAI's embedding size
      add :embedding, :vector, size: 1536
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:contact_embeddings, [:user_id])
    create index(:contact_embeddings, [:contact_id])
    create index(:contact_embeddings, [:email])
    create unique_index(:contact_embeddings, [:user_id, :contact_id])
    # pgvector search
    create index(:contact_embeddings, [:embedding], using: :ivfflat)
  end
end
