defmodule FinancialAdvisorAi.AI.Integration do
  use FinancialAdvisorAi, :db_schema

  schema "integrations" do
    field :provider, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :scope, :string
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :provider,
      :access_token,
      :refresh_token,
      :expires_at,
      :scope,
      :metadata,
      :user_id
    ])
    |> validate_required([:provider, :user_id])
    |> validate_inclusion(:provider, ["google", "hubspot"])
    |> unique_constraint([:user_id, :provider])
  end
end
