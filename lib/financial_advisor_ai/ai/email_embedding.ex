defmodule FinancialAdvisorAi.AI.EmailEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_embeddings" do
    field :email_id, :string
    field :subject, :string
    field :content, :string
    field :sender, :string
    field :recipient, :string
    field :embedding, :binary
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(email_embedding, attrs) do
    email_embedding
    |> cast(attrs, [
      :email_id,
      :subject,
      :content,
      :sender,
      :recipient,
      :embedding,
      :metadata,
      :user_id
    ])
    |> validate_required([:email_id, :user_id])
  end
end
