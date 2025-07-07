defmodule FinancialAdvisorAiWeb.OauthController do
  use FinancialAdvisorAiWeb, :controller

  alias FinancialAdvisorAi.AI

  @doc """
  Initiates OAuth flow for Google (Gmail + Calendar)
  """
  def google(conn, _params) do
    redirect(conn, external: build_google_auth_url())
  end

  @doc """
  Handles Google OAuth callback
  """
  def google_callback(conn, %{"code" => code}) do
    with {:ok, tokens} <- exchange_google_code_for_tokens(code),
         {:ok, user_info} <- fetch_google_user_info(tokens["access_token"]),
         {:ok, user} <- FinancialAdvisorAi.Accounts.get_or_create_user_from_google(user_info),
         integration_attrs <- build_integration_attrs(user, tokens),
         {:ok, _integration} <- AI.upsert_integration(integration_attrs) do
      FinancialAdvisorAiWeb.UserAuth.log_in_user(
        conn,
        user,
        %{}
      )
      |> put_flash(
        :info,
        "Successfully connected to Google! Gmail and Calendar access enabled."
      )
      |> redirect(to: ~p"/")
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Google authentication failed: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end

    # case exchange_google_code_for_tokens(code) do
    #   {:ok, tokens} ->
    #     # Fetch user info from Google
    #     case fetch_google_user_info(tokens["access_token"]) do
    #       {:ok, user_info} ->
    #         # Find or create user in DB
    #         case FinancialAdvisorAi.Accounts.get_or_create_user_from_google(user_info) do
    #           {:ok, user} ->
    #             integration_attrs =
    #               %{
    #                 user_id: user.id,
    #                 provider: "google",
    #                 access_token: tokens["access_token"],
    #                 refresh_token: tokens["refresh_token"],
    #                 expires_at: calculate_expires_at(tokens["expires_in"]),
    #                 scope: tokens["scope"],
    #                 metadata: %{
    #                   token_type: tokens["token_type"]
    #                 }
    #               }

    #             case AI.upsert_integration(integration_attrs) do
    #               {:ok, _integration} ->
    #                 FinancialAdvisorAiWeb.UserAuth.log_in_user(
    #                   conn,
    #                   user,
    #                   %{}
    #                 )
    #                 |> put_flash(
    #                   :info,
    #                   "Successfully connected to Google! Gmail and Calendar access enabled."
    #                 )
    #                 |> redirect(to: ~p"/")

    #               {:error, _changeset} ->
    #                 conn
    #                 |> put_flash(:error, "Failed to save Google integration. Please try again.")
    #                 |> redirect(to: ~p"/")
    #             end

    #           {:error, reason} ->
    #             conn
    #             |> put_flash(:error, "Failed to create or find user: #{inspect(reason)}")
    #             |> redirect(to: ~p"/")
    #         end

    #       {:error, reason} ->
    #         conn
    #         |> put_flash(:error, "Failed to fetch Google user info: #{inspect(reason)}")
    #         |> redirect(to: ~p"/")
    #     end

    #   {:error, reason} ->
    #     conn
    #     |> put_flash(:error, "Google authentication failed: #{inspect(reason)}")
    #     |> redirect(to: ~p"/")
    # end
  end

  def google_callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Google authentication was denied: #{error}")
    |> redirect(to: ~p"/")
  end

  defp build_integration_attrs(user, tokens) do
    %{
      user_id: user.id,
      provider: "google",
      access_token: tokens["access_token"],
      refresh_token: tokens["refresh_token"],
      expires_at: calculate_expires_at(tokens["expires_in"]),
      scope: tokens["scope"],
      metadata: %{
        token_type: tokens["token_type"]
      }
    }
  end



  @doc """
  Initiates OAuth flow for HubSpot
  """
  def hubspot(conn, _params) do
    redirect(conn, external: build_hubspot_auth_url())
  end

  @doc """
  Handles HubSpot OAuth callback
  """
  def hubspot_callback(conn, %{"code" => code}) do
    case exchange_hubspot_code_for_tokens(code) do
      {:ok, tokens} ->
        user_id = conn.assigns.current_scope.user.id

        integration_attrs = %{
          user_id: user_id,
          provider: "hubspot",
          access_token: tokens["access_token"],
          refresh_token: tokens["refresh_token"],
          expires_at: calculate_expires_at(tokens["expires_in"]),
          scope: tokens["scope"],
          metadata: %{
            hub_domain: tokens["hub_domain"],
            hub_id: tokens["hub_id"]
          }
        }

        case AI.upsert_integration(integration_attrs) do
          {:ok, _integration} ->
            FinancialAdvisorAiWeb.UserAuth.log_in_user(
              conn,
              conn.assigns.current_scope.user,
              %{}
            )
            |> put_flash(:info, "Successfully connected to HubSpot! CRM access enabled.")
            |> redirect(to: ~p"/")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to save HubSpot integration. Please try again.")
            |> redirect(to: ~p"/")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "HubSpot authentication failed: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end

  def hubspot_callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "HubSpot authentication was denied: #{error}")
    |> redirect(to: ~p"/")
  end

  # Private functions

  defp build_google_auth_url do
    client_id = get_google_client_id()
    redirect_uri = get_google_redirect_uri()

    scope =
      "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar"

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: scope,
      response_type: "code",
      access_type: "offline",
      prompt: "consent"
    }

    "https://accounts.google.com/o/oauth2/v2/auth?" <> URI.encode_query(params)
  end

  defp build_hubspot_auth_url do
    client_id = get_hubspot_client_id()
    redirect_uri = get_hubspot_redirect_uri()

    scope =
      "crm.import crm.lists.read crm.lists.write crm.objects.companies.read crm.objects.companies.write crm.objects.contacts.read crm.objects.contacts.write crm.objects.deals.read crm.objects.deals.write crm.objects.feedback_submissions.read crm.objects.goals.read crm.objects.goals.write crm.objects.leads.read crm.objects.leads.write crm.objects.line_items.read crm.objects.line_items.write crm.objects.listings.read crm.objects.listings.write crm.objects.marketing_events.read crm.objects.marketing_events.write crm.objects.orders.read crm.objects.products.read crm.objects.products.write crm.objects.quotes.read crm.objects.services.read crm.objects.users.read crm.objects.users.write oauth"

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: scope,
      response_type: "code"
    }

    "https://app.hubspot.com/oauth/authorize?" <> URI.encode_query(params)
  end

  defp exchange_google_code_for_tokens(code) do
    client_id = get_google_client_id()
    client_secret = get_google_client_secret()
    redirect_uri = get_google_redirect_uri()

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    case Req.post("https://oauth2.googleapis.com/token", form: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, error} -> {:error, error}
    end
  end

  defp exchange_hubspot_code_for_tokens(code) do
    client_id = get_hubspot_client_id()
    client_secret = get_hubspot_client_secret()
    redirect_uri = get_hubspot_redirect_uri()

    params = %{
      grant_type: "authorization_code",
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      code: code
    }

    case Req.post("https://api.hubapi.com/oauth/v1/token", form: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, error} -> {:error, error}
    end
  end

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expires_at(_), do: nil

  defp get_google_client_id, do: System.get_env("GOOGLE_CLIENT_ID")
  defp get_google_client_secret, do: System.get_env("GOOGLE_CLIENT_SECRET")

  defp get_google_redirect_uri do
    base_url = get_base_url()
    "#{base_url}/auth/google/callback"
  end

  defp get_hubspot_client_id, do: System.get_env("HUBSPOT_CLIENT_ID")
  defp get_hubspot_client_secret, do: System.get_env("HUBSPOT_CLIENT_SECRET")

  defp get_hubspot_redirect_uri do
    base_url = get_base_url()
    "#{base_url}/auth/hubspot/callback"
  end

  defp get_base_url do
    # In development, use localhost. In production, use actual domain
    case Application.get_env(:financial_advisor_ai, :environment) do
      :prod -> System.get_env("BASE_URL", "https://your-app.fly.dev")
      _ -> "http://localhost:4000"
    end
  end

  defp fetch_google_user_info(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Req.get("https://www.googleapis.com/oauth2/v2/userinfo", headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, error} -> {:error, error}
    end
  end
end
