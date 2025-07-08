defmodule FinancialAdvisorAi.AI.TokenRefreshJob do
  @moduledoc """
  Oban job for periodically refreshing OAuth tokens that are close to expiry.

  This job runs every 30 minutes and checks all integrations for tokens
  that will expire within the next hour, refreshing them automatically.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Ecto.Query, warn: false
  alias FinancialAdvisorAi.{Repo, AI}
  alias FinancialAdvisorAi.AI.Integration
  alias FinancialAdvisorAi.Integrations.TokenRefreshService

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{"user_id" => user_id, "provider" => provider} ->
        # Refresh a specific integration
        refresh_specific_integration(user_id, provider)

      %{"user_id" => user_id} ->
        # Refresh all integrations for a specific user
        refresh_user_integrations(user_id)

      _ ->
        # Refresh all integrations that need refreshing
        refresh_all_expiring_tokens()
    end
  end

  @doc """
  Schedules a job to refresh all tokens that are expiring soon.
  """
  def schedule_refresh_all_tokens() do
    %{}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules a job to refresh a specific user's integrations.
  """
  def schedule_user_refresh(user_id) do
    %{"user_id" => user_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules a job to refresh a specific integration.
  """
  def schedule_integration_refresh(user_id, provider) do
    %{"user_id" => user_id, "provider" => provider}
    |> new()
    |> Oban.insert()
  end

  # Private functions

  defp refresh_all_expiring_tokens() do
    Logger.info("Starting periodic token refresh check...")

    integrations_needing_refresh = get_integrations_needing_refresh()

    Logger.info(
      "Found #{length(integrations_needing_refresh)} integrations needing token refresh"
    )

    results = Enum.map(integrations_needing_refresh, &refresh_integration/1)

    success_count = Enum.count(results, fn {status, _} -> status == :ok end)
    error_count = Enum.count(results, fn {status, _} -> status == :error end)

    Logger.info("Token refresh completed: #{success_count} successful, #{error_count} failed")

    :ok
  end

  defp refresh_user_integrations(user_id) do
    Logger.info("Refreshing tokens for user #{user_id}")

    integrations =
      from(i in Integration,
        where: i.user_id == ^user_id and not is_nil(i.expires_at),
        select: i
      )
      |> Repo.all()
      |> Enum.filter(&Integration.token_expires_soon?/1)

    Logger.info("Found #{length(integrations)} integrations to refresh for user #{user_id}")

    Enum.each(integrations, &refresh_integration/1)

    :ok
  end

  defp refresh_specific_integration(user_id, provider) do
    Logger.info("Refreshing #{provider} integration for user #{user_id}")

    case AI.get_integration(user_id, provider) do
      nil ->
        Logger.warning("Integration not found: #{provider} for user #{user_id}")
        :ok

      integration ->
        refresh_integration(integration)
        :ok
    end
  end

  defp get_integrations_needing_refresh() do
    # Get integrations that expire within the next hour
    one_hour_from_now = DateTime.utc_now() |> DateTime.add(60 * 60, :second)

    from(i in Integration,
      where: not is_nil(i.expires_at) and i.expires_at <= ^one_hour_from_now,
      select: i
    )
    |> Repo.all()
    |> Enum.filter(&Integration.token_expires_soon?/1)
  end

  defp refresh_integration(%Integration{} = integration) do
    case TokenRefreshService.refresh_if_needed(integration) do
      {:ok, updated_integration} ->
        if updated_integration.id != integration.id do
          Logger.info(
            "Successfully refreshed #{integration.provider} token for user #{integration.user_id}"
          )
        end

        {:ok, updated_integration}

      {:error, :no_refresh_token} ->
        Logger.warning(
          "Cannot refresh #{integration.provider} token for user #{integration.user_id}: no refresh token available"
        )

        {:error, :no_refresh_token}

      {:error, :invalid_refresh_token} ->
        Logger.error(
          "Invalid refresh token for #{integration.provider} integration user #{integration.user_id} - requires re-authentication"
        )

        # Could potentially notify the user here
        {:error, :invalid_refresh_token}

      {:error, reason} ->
        Logger.error(
          "Failed to refresh #{integration.provider} token for user #{integration.user_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
