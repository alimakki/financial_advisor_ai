defmodule FinancialAdvisorAi.Integrations.TokenRefreshService do
  @moduledoc """
  Service for refreshing OAuth access tokens for integrations.

  Handles token refresh for both Google and HubSpot integrations,
  including automatic refresh when tokens are close to expiry.
  """

  require Logger
  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.Integration

  @doc """
  Refreshes an integration's access token if it's expired or close to expiry.

  Returns:
  - `{:ok, updated_integration}` if refresh was successful
  - `{:ok, integration}` if refresh was not needed
  - `{:error, reason}` if refresh failed
  """
  def refresh_if_needed(%Integration{} = integration) do
    cond do
      is_nil(integration.expires_at) ->
        # No expiry time set, assume token is still valid
        {:ok, integration}

      token_expires_soon?(integration) ->
        Logger.info("Refreshing token for #{integration.provider} integration for user #{integration.user_id}")
        refresh_token(integration)

      true ->
        {:ok, integration}
    end
  end

  @doc """
  Forces a token refresh for the given integration.
  """
  def refresh_token(%Integration{provider: "google"} = integration) do
    refresh_google_token(integration)
  end

  def refresh_token(%Integration{provider: "hubspot"} = integration) do
    refresh_hubspot_token(integration)
  end

  def refresh_token(%Integration{provider: provider}) do
    {:error, "Unsupported provider: #{provider}"}
  end

  @doc """
  Checks if a token is expired or will expire soon (within 5 minutes).
  """
  def token_expires_soon?(%Integration{expires_at: nil}), do: false

  def token_expires_soon?(%Integration{expires_at: expires_at}) do
    # Consider token expired if it expires within 5 minutes
    buffer_time = 5 * 60  # 5 minutes in seconds
    threshold = DateTime.utc_now() |> DateTime.add(buffer_time, :second)

    DateTime.compare(expires_at, threshold) != :gt
  end

  @doc """
  Checks if a token is definitely expired.
  """
  def token_expired?(%Integration{expires_at: nil}), do: false

  def token_expired?(%Integration{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  # Private functions

  defp refresh_google_token(%Integration{} = integration) do
    if is_nil(integration.refresh_token) do
      Logger.error("No refresh token available for Google integration user #{integration.user_id}")
      {:error, :no_refresh_token}
    else
      perform_google_token_refresh(integration)
    end
  end

  defp perform_google_token_refresh(%Integration{} = integration) do

    params = %{
      grant_type: "refresh_token",
      refresh_token: integration.refresh_token,
      client_id: get_google_client_id(),
      client_secret: get_google_client_secret()
    }

    case Req.post("https://oauth2.googleapis.com/token", form: params) do
      {:ok, %{status: 200, body: body}} ->
        update_integration_tokens(integration, body)

      {:ok, %{status: 400, body: %{"error" => "invalid_grant"}}} ->
        Logger.error("Google refresh token invalid for user #{integration.user_id}, requires re-authentication")
        {:error, :invalid_refresh_token}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Google token refresh failed: #{status} - #{inspect(body)}")
        {:error, {status, body}}

      {:error, error} ->
        Logger.error("Google token refresh request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp refresh_hubspot_token(%Integration{} = integration) do
    if is_nil(integration.refresh_token) do
      Logger.error("No refresh token available for HubSpot integration user #{integration.user_id}")
      {:error, :no_refresh_token}
    else
      perform_hubspot_token_refresh(integration)
    end
  end

  defp perform_hubspot_token_refresh(%Integration{} = integration) do

    params = %{
      grant_type: "refresh_token",
      refresh_token: integration.refresh_token,
      client_id: get_hubspot_client_id(),
      client_secret: get_hubspot_client_secret()
    }

    case Req.post("https://api.hubapi.com/oauth/v1/token", form: params) do
      {:ok, %{status: 200, body: body}} ->
        update_integration_tokens(integration, body)

      {:ok, %{status: 400, body: %{"error" => "invalid_grant"}}} ->
        Logger.error("HubSpot refresh token invalid for user #{integration.user_id}, requires re-authentication")
        {:error, :invalid_refresh_token}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HubSpot token refresh failed: #{status} - #{inspect(body)}")
        {:error, {status, body}}

      {:error, error} ->
        Logger.error("HubSpot token refresh request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp update_integration_tokens(%Integration{} = integration, token_response) do
    attrs = %{
      access_token: token_response["access_token"],
      expires_at: calculate_expires_at(token_response["expires_in"])
    }

    # Some providers may return a new refresh token
    attrs = if token_response["refresh_token"] do
      Map.put(attrs, :refresh_token, token_response["refresh_token"])
    else
      attrs
    end

    case AI.upsert_integration(Map.merge(attrs, %{
      user_id: integration.user_id,
      provider: integration.provider
    })) do
      {:ok, updated_integration} ->
        Logger.info("Successfully refreshed #{integration.provider} token for user #{integration.user_id}")
        {:ok, updated_integration}

      {:error, changeset} ->
        Logger.error("Failed to update integration tokens: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expires_at(_), do: nil

  defp get_google_client_id, do: System.get_env("GOOGLE_CLIENT_ID")
  defp get_google_client_secret, do: System.get_env("GOOGLE_CLIENT_SECRET")
  defp get_hubspot_client_id, do: System.get_env("HUBSPOT_CLIENT_ID")
  defp get_hubspot_client_secret, do: System.get_env("HUBSPOT_CLIENT_SECRET")
end
