defmodule FinancialAdvisorAi.Integrations.EventProcessor do
  @moduledoc """
  Handles incoming events from webhooks or polling for Gmail, Google Calendar, and Hubspot.
  Processes the event, checks ongoing instructions, and triggers the agent if needed.
  """

  require Logger
  alias FinancialAdvisorAi.AI.Agent
  alias FinancialAdvisorAi.AI.RagService

  @doc """
  Processes a webhook event from the given provider.
  - provider: "gmail", "calendar", or "hubspot"
  - params: the event payload
  - headers: the request headers
  Returns :ok or {:error, reason}
  """
  def process_webhook(provider, params, _headers) do
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

  @doc """
  Processes an event for a specific user.
  - user_id: the user ID
  - provider: "gmail", "calendar", or "hubspot"
  - event: the event payload
  Returns :ok or {:error, reason}
  """
  def process_user_event(user_id, provider, event) do
    # Store event for RAG if it's an email
    if provider == "gmail" do
      RagService.process_email_for_rag(user_id, event)
    end

    # Send event to user's agent for processing
    Agent.handle_event(user_id, provider, event)

    Logger.info("Processed #{provider} event for user #{user_id}")
    :ok
  end

  # Gmail event processing
  defp process_gmail_event(event) do
    # Extract user_id from event or context
    user_id = extract_user_id_from_event(event)

    if user_id do
      # Parse Gmail event
      parsed_event = parse_gmail_event(event)

      # Check if already processed
      if not already_processed?("gmail", parsed_event.id) do
        # Process for specific user
        process_user_event(user_id, "gmail", parsed_event)

        # Mark as processed
        mark_as_processed("gmail", parsed_event.id)
      end
    end

    :ok
  end

  # Google Calendar event processing
  defp process_calendar_event(event) do
    # Extract user_id from event or context
    user_id = extract_user_id_from_event(event)

    if user_id do
      # Parse Calendar event
      parsed_event = parse_calendar_event(event)

      # Check if already processed
      if not already_processed?("calendar", parsed_event.id) do
        # Process for specific user
        process_user_event(user_id, "calendar", parsed_event)

        # Mark as processed
        mark_as_processed("calendar", parsed_event.id)
      end
    end

    :ok
  end

  # Hubspot event processing
  defp process_hubspot_event(event) do
    # Extract user_id from event or context
    user_id = extract_user_id_from_event(event)

    if user_id do
      # Parse HubSpot event
      parsed_event = parse_hubspot_event(event)

      # Check if already processed
      if not already_processed?("hubspot", parsed_event.id) do
        # Process for specific user
        process_user_event(user_id, "hubspot", parsed_event)

        # Mark as processed
        mark_as_processed("hubspot", parsed_event.id)
      end
    end

    :ok
  end

  # Event parsing functions

  defp parse_gmail_event(event) do
    %{
      id: event["id"] || event[:id] || generate_event_id(),
      type: "gmail",
      action: event["action"] || "message_received",
      data: %{
        message_id: event["message_id"] || event[:message_id],
        thread_id: event["thread_id"] || event[:thread_id],
        subject: event["subject"] || event[:subject],
        from: event["from"] || event[:from],
        to: event["to"] || event[:to],
        body: event["body"] || event[:body],
        timestamp: event["timestamp"] || event[:timestamp] || DateTime.utc_now()
      }
    }
  end

  defp parse_calendar_event(event) do
    %{
      id: event["id"] || event[:id] || generate_event_id(),
      type: "calendar",
      action: event["action"] || "event_created",
      data: %{
        event_id: event["event_id"] || event[:event_id],
        summary: event["summary"] || event[:summary],
        start_time: event["start_time"] || event[:start_time],
        end_time: event["end_time"] || event[:end_time],
        attendees: event["attendees"] || event[:attendees] || [],
        location: event["location"] || event[:location],
        timestamp: event["timestamp"] || event[:timestamp] || DateTime.utc_now()
      }
    }
  end

  defp parse_hubspot_event(event) do
    %{
      id: event["id"] || event[:id] || generate_event_id(),
      type: "hubspot",
      action: event["action"] || "contact_created",
      data: %{
        contact_id: event["contact_id"] || event[:contact_id],
        email: event["email"] || event[:email],
        firstname: event["firstname"] || event[:firstname],
        lastname: event["lastname"] || event[:lastname],
        company: event["company"] || event[:company],
        timestamp: event["timestamp"] || event[:timestamp] || DateTime.utc_now()
      }
    }
  end

  # Helper functions

  defp extract_user_id_from_event(event) do
    # Try to extract user_id from various places in the event
    # If no user_id found, we might need to look up by email or other identifier
    event["user_id"] || event[:user_id] ||
      get_in(event, ["data", "user_id"]) ||
      get_in(event, [:data, :user_id]) ||
      lookup_user_id_by_email(event["from"] || event[:from])
  end

  defp lookup_user_id_by_email(email) when is_binary(email) do
    # This would typically lookup the user by their email
    # For now, we'll return nil and let the calling code handle it
    nil
  end

  defp lookup_user_id_by_email(_), do: nil

  defp generate_event_id do
    "event_#{System.unique_integer([:positive])}"
  end

  # Event deduplication
  defp already_processed?(provider, event_id) do
    # Simple in-memory deduplication - in production, use a database or cache
    case :ets.lookup(:processed_events, {provider, event_id}) do
      [] -> false
      _ -> true
    end
  rescue
    # ETS table doesn't exist, create it
    ArgumentError ->
      :ets.new(:processed_events, [:named_table, :set, :public])
      false
  end

  defp mark_as_processed(provider, event_id) do
    # Store with TTL of 1 hour to prevent endless growth
    :ets.insert(:processed_events, {{provider, event_id}, System.system_time(:second)})

    # Clean up old entries periodically
    cleanup_old_processed_events()
  end

  defp cleanup_old_processed_events do
    # Only cleanup 10% of the time to avoid constant cleanup
    if :rand.uniform(100) <= 10 do
      # 1 hour ago
      cutoff_time = System.system_time(:second) - 3600

      :ets.select_delete(:processed_events, [
        {{:"$1", :"$2"}, [{:<, :"$2", cutoff_time}], [true]}
      ])
    end
  end
end
