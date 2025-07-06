defmodule FinancialAdvisorAi.AI.OngoingInstruction do
  use FinancialAdvisorAi, :db_schema

  schema "ongoing_instructions" do
    field :instruction, :string
    field :is_active, :boolean, default: true
    field :trigger_events, {:array, :string}, default: []
    field :priority, :integer, default: 1

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:instruction, :is_active, :trigger_events, :priority, :user_id])
    |> validate_required([:instruction, :user_id])
    |> validate_number(:priority, greater_than: 0)
  end
end
