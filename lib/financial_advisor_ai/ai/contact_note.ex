defmodule FinancialAdvisorAi.AI.ContactNote do
  @moduledoc """
  Contact note schema for storing individual HubSpot contact notes with embeddings for RAG search.
  Each contact can have multiple notes, and each note contains vector embeddings for semantic search.
  """

  use FinancialAdvisorAi, :db_schema

  schema "contact_notes" do
    field :hubspot_note_id, :string
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    belongs_to :contact_embedding, FinancialAdvisorAi.AI.ContactEmbedding

    timestamps()
  end

  def changeset(contact_note, attrs) do
    contact_note
    |> cast(attrs, [
      :hubspot_note_id,
      :content,
      :embedding,
      :metadata,
      :user_id,
      :contact_embedding_id
    ])
    |> validate_required([:content, :user_id, :contact_embedding_id])
    |> unique_constraint(:hubspot_note_id, name: :contact_notes_hubspot_note_id_index)
  end
end
