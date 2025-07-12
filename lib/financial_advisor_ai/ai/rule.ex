defmodule FinancialAdvisorAi.AI.Rule do
  @moduledoc """
  Rule schema for the Financial Advisor AI web application.
  Stores automation rules that define when and how to perform actions.
  """

  use FinancialAdvisorAi, :db_schema

  schema "rules" do
    field :trigger, :string
    field :condition, :map, default: %{}
    field :actions, {:array, :map}, default: []

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:trigger, :condition, :actions, :user_id])
    |> validate_required([:trigger, :actions, :user_id])
    |> validate_trigger()
    |> validate_actions()
  end

  defp validate_trigger(changeset) do
    case get_field(changeset, :trigger) do
      nil ->
        changeset

      trigger ->
        valid_triggers = ["email_received", "calendar_event", "contact_created", "general"]

        if trigger in valid_triggers do
          changeset
        else
          add_error(changeset, :trigger, "must be one of: #{Enum.join(valid_triggers, ", ")}")
        end
    end
  end

  defp validate_actions(changeset) do
    case get_field(changeset, :actions) do
      nil ->
        changeset

      actions when is_list(actions) ->
        if Enum.all?(actions, &valid_action?/1) do
          changeset
        else
          add_error(changeset, :actions, "contains invalid action structure")
        end

      _ ->
        add_error(changeset, :actions, "must be a list of action maps")
    end
  end

  defp valid_action?(%{"type" => type}) when is_binary(type), do: true
  defp valid_action?(_), do: false
end
