defmodule FinancialAdvisorAi.AI.Integration do
  @moduledoc """
  Integration for the Financial Advisor AI web application.
  """

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
      :id,
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

  @doc """
  Checks if the integration's access token is expired.
  """
  def token_expired?(%__MODULE__{expires_at: nil}), do: false

  def token_expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  @doc """
  Checks if the integration's access token will expire soon (within the given buffer time).
  Default buffer is 5 minutes.
  """
  def token_expires_soon?(%__MODULE__{} = integration, buffer_minutes \\ 5) do
    case integration.expires_at do
      nil -> false
      expires_at ->
        buffer_time = buffer_minutes * 60  # Convert to seconds
        threshold = DateTime.utc_now() |> DateTime.add(buffer_time, :second)
        DateTime.compare(expires_at, threshold) != :gt
    end
  end

  @doc """
  Checks if the integration has a valid access token (not expired and not expiring soon).
  """
  def has_valid_token?(%__MODULE__{} = integration) do
    not token_expired?(integration) and not token_expires_soon?(integration)
  end

  @doc """
  Returns the time remaining until token expiry in seconds.
  Returns nil if no expiry time is set, or a negative number if already expired.
  """
  def time_until_expiry(%__MODULE__{expires_at: nil}), do: nil

  def time_until_expiry(%__MODULE__{expires_at: expires_at}) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second)
  end
end
