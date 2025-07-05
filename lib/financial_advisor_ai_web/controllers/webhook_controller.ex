defmodule FinancialAdvisorAiWeb.WebhookController do
  use FinancialAdvisorAiWeb, :controller

  alias FinancialAdvisorAi.Integrations.EventProcessor

  @doc """
  Receives webhook events from external providers (Gmail, Google Calendar, Hubspot).
  The provider is specified in the URL as /api/webhooks/:provider
  """
  def handle(conn, %{"provider" => provider} = params) do
    case EventProcessor.process_webhook(provider, params, conn.req_headers) do
      :ok ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        send_resp(conn, 400, "error: #{inspect(reason)}")
    end
  end
end
