defmodule FinancialAdvisorAi.Integrations.EventProcessor do
  @moduledoc """
  Handles incoming events from webhooks or polling for Gmail, Google Calendar, and Hubspot.
  Processes the event, checks ongoing instructions, and triggers the agent if needed.
  """

  @doc """
  Processes a webhook event from the given provider.
  - provider: "gmail", "calendar", or "hubspot"
  - params: the event payload
  - headers: the request headers
  Returns :ok or {:error, reason}
  """
  def process_webhook(provider, params, headers) do
    process_event(provider, params)
  end

  @doc """
  Processes an event from polling or webhook for the given provider.
  - provider: "gmail", "calendar", or "hubspot"
  - event: the event payload
  Returns :ok or {:error, reason}
  """
  def process_event("gmail", event), do: process_gmail_event(event)
  def process_event("calendar", event), do: process_calendar_event(event)
  def process_event("hubspot", event), do: process_hubspot_event(event)
  def process_event(_provider, _event), do: {:error, :unknown_provider}

  # Gmail event processing
  defp process_gmail_event(event) do
    # TODO: Parse event, deduplicate, check ongoing instructions, trigger agent
    {:ok, :not_implemented}
  end

  # Google Calendar event processing
  defp process_calendar_event(event) do
    # TODO: Parse event, deduplicate, check ongoing instructions, trigger agent
    {:ok, :not_implemented}
  end

  # Hubspot event processing
  defp process_hubspot_event(event) do
    # TODO: Parse event, deduplicate, check ongoing instructions, trigger agent
    {:ok, :not_implemented}
  end

  # Event deduplication stub
  defp already_processed?(_provider, _event_id), do: false
end
