defmodule FinancialAdvisorAi.Auth.Strategy.Hubspot do
  @moduledoc """
  Hubspot Strategy for Überauth.
  """

  use Ueberauth.Strategy, uid_field: :hub_id, default_scope: "contacts oauth"

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @hubspot_authorize_url "https://app.hubspot.com/oauth/authorize"
  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"

  # Handles the initial request phase (redirect to HubSpot)
  def handle_request!(conn) do
    client_id = System.get_env("HUBSPOT_CLIENT_ID")
    redirect_uri = Ueberauth.Strategy.Helpers.callback_url(conn)
    scope = option(conn, :default_scope) || "contacts oauth"

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: scope,
      response_type: "code"
    }

    url = @hubspot_authorize_url <> "?" <> URI.encode_query(params)
    redirect!(conn, url)
  end

  # Handles the callback phase (exchange code for token)
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    client_id = System.get_env("HUBSPOT_CLIENT_ID")
    client_secret = System.get_env("HUBSPOT_CLIENT_SECRET")
    redirect_uri = Ueberauth.Strategy.Helpers.callback_url(conn)

    params = %{
      grant_type: "authorization_code",
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      code: code
    }

    case Req.post(@hubspot_token_url, form: params) do
      {:ok, %{status: 200, body: body}} ->
        put_private(conn, :ueberauth_auth, build_auth(body))

      {:ok, %{status: status, body: body}} ->
        set_errors!(conn, [
          Ueberauth.Strategy.Helpers.error("token_error", inspect({status, body}))
        ])

      {:error, error} ->
        set_errors!(conn, [Ueberauth.Strategy.Helpers.error("token_error", inspect(error))])
    end
  end

  def handle_callback!(conn),
    do: set_errors!(conn, [Ueberauth.Strategy.Helpers.error("missing_code", "No code received")])

  defp build_auth(token_data) do
    %Ueberauth.Auth{
      provider: :hubspot,
      uid: token_data["hub_id"],
      info: %Info{
        email: nil,
        name: nil
      },
      credentials: %Credentials{
        token: token_data["access_token"],
        refresh_token: token_data["refresh_token"],
        expires_at: DateTime.utc_now() |> DateTime.add(token_data["expires_in"] || 0, :second),
        expires: true,
        scopes: String.split(token_data["scope"] || "", " ")
      },
      extra: %Extra{raw_info: token_data}
    }
  end

  defp option(conn, key) do
    Ueberauth.Strategy.Helpers.options(conn) |> Keyword.get(key)
  end
end
