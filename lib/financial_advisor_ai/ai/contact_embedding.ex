defmodule FinancialAdvisorAi.AI.ContactEmbedding do
  @moduledoc """
  Contact embedding for the Financial Advisor AI web application.
  Stores HubSpot contact data with embeddings for RAG search.
  """

  use FinancialAdvisorAi, :db_schema

  schema "contact_embeddings" do
    field :contact_id, :string
    field :firstname, :string
    field :lastname, :string
    field :email, :string
    field :company, :string
    field :phone, :string
    field :lifecycle_stage, :string
    field :lead_status, :string
    # Combined content for embedding (without notes)
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :notes_last_processed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    has_many :contact_notes, FinancialAdvisorAi.AI.ContactNote

    timestamps()
  end

  def changeset(contact_embedding, attrs) do
    contact_embedding
    |> cast(attrs, [
      :contact_id,
      :firstname,
      :lastname,
      :email,
      :company,
      :phone,
      :lifecycle_stage,
      :lead_status,
      :content,
      :embedding,
      :notes_last_processed_at,
      :metadata,
      :user_id
    ])
    |> validate_required([:contact_id, :user_id])
    |> unique_constraint(:contact_id, name: :contact_embeddings_user_id_contact_id_index)
  end
end
