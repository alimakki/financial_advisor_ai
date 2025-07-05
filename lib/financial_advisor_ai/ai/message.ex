defmodule FinancialAdvisorAi.AI.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :tool_calls, :map
    field :tool_results, :map

    belongs_to :conversation, FinancialAdvisorAi.AI.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :tool_calls, :tool_results, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
