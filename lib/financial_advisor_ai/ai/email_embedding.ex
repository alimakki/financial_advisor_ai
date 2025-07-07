defmodule FinancialAdvisorAi.AI.EmailEmbedding do
  @moduledoc """
  Email embedding for the Financial Advisor AI web application.
  """

  use FinancialAdvisorAi, :db_schema

  schema "email_embeddings" do
    field :email_id, :string
    field :subject, :string
    field :content, :string
    field :sender, :string
    field :recipient, :string
    field :date, :utc_datetime
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(email_embedding, attrs) do
    email_embedding
    |> cast(attrs, [
      :id,
      :email_id,
      :subject,
      :content,
      :sender,
      :recipient,
      :embedding,
      :metadata,
      :user_id,
      :date
    ])
    |> validate_required([:email_id, :user_id])
  end
end
