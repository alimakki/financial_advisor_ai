defmodule FinancialAdvisorAi.AI.Conversation do
  use FinancialAdvisorAi, :db_schema

  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    has_many :messages, FinancialAdvisorAi.AI.Message
    has_many :tasks, FinancialAdvisorAi.AI.Task

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :status, :metadata, :user_id])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, ["active", "archived", "completed"])
  end
end
