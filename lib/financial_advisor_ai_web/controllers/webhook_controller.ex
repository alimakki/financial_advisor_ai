defmodule FinancialAdvisorAiWeb.WebhookController do
  use FinancialAdvisorAiWeb, :controller

  alias FinancialAdvisorAi.Integrations.EventProcessor

  @doc """
  Receives webhook events from external providers (Gmail, Google Calendar, Hubspot).
  The provider is specified in the URL as /api/webhooks/:provider
  """
  def handle(conn, %{"provider" => provider} = params) do
    case EventProcessor.process_webhook(provider, params, conn.req_headers) do
      {:ok, _} ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        send_resp(conn, 400, "error: #{inspect(reason)}")
    end
  end

  def gmail_webhook(conn, params) do
    # Extract user context from headers or authentication
    user_id = get_user_id_from_webhook(conn)

    if user_id do
      # Process Gmail webhook with user context
      event = Map.put(params, "user_id", user_id)
      FinancialAdvisorAi.Integrations.EventProcessor.process_user_event(user_id, "gmail", event)
    else
      # Fallback to generic processing
      FinancialAdvisorAi.Integrations.EventProcessor.process_event("gmail", params)
    end

    send_resp(conn, 200, "OK")
  end

  def calendar_webhook(conn, params) do
    # Extract user context from headers or authentication
    user_id = get_user_id_from_webhook(conn)

    if user_id do
      # Process Calendar webhook with user context
      event = Map.put(params, "user_id", user_id)

      FinancialAdvisorAi.Integrations.EventProcessor.process_user_event(
        user_id,
        "calendar",
        event
      )
    else
      # Fallback to generic processing
      FinancialAdvisorAi.Integrations.EventProcessor.process_event("calendar", params)
    end

    send_resp(conn, 200, "OK")
  end

  def hubspot_webhook(conn, params) do
    # Extract user context from headers or authentication
    user_id = get_user_id_from_webhook(conn)

    if user_id do
      # Process HubSpot webhook with user context
      event = Map.put(params, "user_id", user_id)
      FinancialAdvisorAi.Integrations.EventProcessor.process_user_event(user_id, "hubspot", event)
    else
      # Fallback to generic processing
      FinancialAdvisorAi.Integrations.EventProcessor.process_event("hubspot", params)
    end

    send_resp(conn, 200, "OK")
  end

  # Helper function to extract user_id from webhook context
  defp get_user_id_from_webhook(conn) do
    # This would extract user_id from headers, query params, or other webhook-specific context
    # Implementation depends on how the webhooks are configured
    get_req_header(conn, "x-user-id") |> List.first() ||
      conn.query_params["user_id"] ||
      conn.path_params["user_id"]
  end
end
