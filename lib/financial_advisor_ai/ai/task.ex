defmodule FinancialAdvisorAi.AI.Task do
  use FinancialAdvisorAi, :db_schema

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :task_type, :string
    field :parameters, :map, default: %{}
    field :result, :map
    field :error_message, :string
    field :scheduled_for, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    belongs_to :conversation, FinancialAdvisorAi.AI.Conversation

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :id,
      :title,
      :description,
      :status,
      :task_type,
      :parameters,
      :result,
      :error_message,
      :scheduled_for,
      :completed_at,
      :user_id,
      :conversation_id
    ])
    |> validate_required([:title, :user_id])
    |> validate_inclusion(:status, ["pending", "in_progress", "completed", "failed"])
  end
end
