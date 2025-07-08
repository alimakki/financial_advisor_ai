defmodule FinancialAdvisorAi.AI.AgentTools do
  @moduledoc """
  Tools for AI Agent to execute various tasks.
  Handles email, calendar, HubSpot, and follow-up tasks.
  """

  require Logger

  alias FinancialAdvisorAi.Integrations.{GmailService, CalendarService, HubspotService}
  alias FinancialAdvisorAi.AI.{LlmService, RagService}

  @doc """
  Executes an email task (sending emails).
  """
  def execute_email_task(parameters, user_id) do
    to = Map.get(parameters, "to")
    subject = Map.get(parameters, "subject")
    body = Map.get(parameters, "body")

    case GmailService.send_email(user_id, to, subject, body) do
      {:ok, result} ->
        Logger.info("Email sent successfully to #{to}")

        {:ok,
         %{
           type: "email_sent",
           recipient: to,
           subject: subject,
           message_id: result["id"]
         }}

      {:error, :not_connected} ->
        {:error, "Gmail not connected. Please connect your Gmail account."}

      {:error, reason} ->
        Logger.error("Failed to send email: #{inspect(reason)}")
        {:retry, reason}
    end
  end

  @doc """
  Executes a calendar task (scheduling meetings).
  """
  def execute_calendar_task(parameters, user_id) do
    client_email = Map.get(parameters, "client_email")
    subject = Map.get(parameters, "subject")
    duration_minutes = Map.get(parameters, "duration_minutes", 60)
    preferred_times = Map.get(parameters, "preferred_times", [])

    case CalendarService.schedule_meeting_with_client(
           user_id,
           client_email,
           subject,
           duration_minutes,
           preferred_times
         ) do
      {:ok, event} ->
        Logger.info("Meeting scheduled successfully with #{client_email}")

        # Send confirmation email
        send_meeting_confirmation(user_id, client_email, event)

        {:ok,
         %{
           type: "meeting_scheduled",
           event_id: event.id,
           client_email: client_email,
           start_time: event.start_time,
           end_time: event.end_time
         }}

      {:error, :not_connected} ->
        {:error, "Google Calendar not connected. Please connect your Google account."}

      {:error, :no_available_slots} ->
        {:error, "No available time slots found. Please suggest specific times."}

      {:error, reason} ->
        Logger.error("Failed to schedule meeting: #{inspect(reason)}")
        {:retry, reason}
    end
  end

  @doc """
  Executes a HubSpot task (creating contacts, adding notes).
  """
  def execute_hubspot_task(parameters, user_id) do
    action = Map.get(parameters, "action", "create_contact")

    case action do
      "create_contact" ->
        execute_create_contact(parameters, user_id)

      "add_note" ->
        execute_add_note(parameters, user_id)

      "update_contact" ->
        execute_update_contact(parameters, user_id)

      _ ->
        {:error, "Unknown HubSpot action: #{action}"}
    end
  end

  @doc """
  Executes a follow-up task (proactive actions based on events).
  """
  def execute_follow_up_task(parameters, user_id) do
    event = Map.get(parameters, "event")
    instruction = Map.get(parameters, "instruction")

    case event["type"] do
      "gmail" ->
        execute_gmail_follow_up(event, instruction, user_id)

      "calendar" ->
        execute_calendar_follow_up(event, instruction, user_id)

      "hubspot" ->
        execute_hubspot_follow_up(event, instruction, user_id)

      _ ->
        {:error, "Unknown event type for follow-up: #{event["type"]}"}
    end
  end

  # Private functions

  defp execute_create_contact(parameters, user_id) do
    name = Map.get(parameters, "name")
    email = Map.get(parameters, "email")

    contact_data = %{
      firstname: extract_first_name(name),
      lastname: extract_last_name(name),
      email: email
    }

    case HubspotService.create_contact(user_id, contact_data) do
      {:ok, contact} ->
        Logger.info("Contact created successfully: #{name} (#{email})")

        {:ok,
         %{
           type: "contact_created",
           contact_id: contact.id,
           name: name,
           email: email
         }}

      {:error, :not_connected} ->
        {:error, "HubSpot not connected. Please connect your HubSpot account."}

      {:error, {409, %{"message" => message}}} ->
        # Contact already exists - extract existing ID if possible
        existing_id = extract_existing_contact_id(message)
        Logger.info("Contact already exists: #{name} (#{email}), existing ID: #{existing_id}")

        {:ok,
         %{
           type: "contact_already_exists",
           contact_id: existing_id,
           name: name,
           email: email,
           message: "Contact already exists in HubSpot"
         }}

      {:error, reason} ->
        Logger.error("Failed to create contact: #{inspect(reason)}")
        {:retry, reason}
    end
  end

  defp execute_add_note(parameters, user_id) do
    contact_id = Map.get(parameters, "contact_id")
    note_content = Map.get(parameters, "note_content")

    case HubspotService.create_note(user_id, contact_id, note_content) do
      {:ok, note} ->
        Logger.info("Note added successfully to contact #{contact_id}")

        {:ok,
         %{
           type: "note_added",
           note_id: note["id"],
           contact_id: contact_id
         }}

      {:error, :not_connected} ->
        {:error, "HubSpot not connected. Please connect your HubSpot account."}

      {:error, reason} ->
        Logger.error("Failed to add note: #{inspect(reason)}")
        {:retry, reason}
    end
  end

  defp execute_update_contact(parameters, user_id) do
    contact_id = Map.get(parameters, "contact_id")
    updates = Map.get(parameters, "updates", %{})

    case HubspotService.update_contact(user_id, contact_id, updates) do
      {:ok, _contact} ->
        Logger.info("Contact updated successfully: #{contact_id}")

        {:ok,
         %{
           type: "contact_updated",
           contact_id: contact_id,
           updates: updates
         }}

      {:error, :not_connected} ->
        {:error, "HubSpot not connected. Please connect your HubSpot account."}

      {:error, reason} ->
        Logger.error("Failed to update contact: #{inspect(reason)}")
        {:retry, reason}
    end
  end

  defp execute_gmail_follow_up(event, instruction, user_id) do
    # Process Gmail event based on instruction
    instruction_text = String.downcase(instruction.instruction)

    cond do
      String.contains?(instruction_text, ["create", "contact", "hubspot"]) ->
        create_hubspot_contact_from_email(event, user_id)

      String.contains?(instruction_text, ["respond", "email"]) ->
        generate_email_response(event, user_id)

      true ->
        {:ok, %{type: "gmail_follow_up", action: "generic", event: event}}
    end
  end

  defp execute_calendar_follow_up(event, instruction, user_id) do
    # Process Calendar event based on instruction
    instruction_text = String.downcase(instruction.instruction)

    cond do
      String.contains?(instruction_text, ["send", "email", "attendees"]) ->
        send_meeting_notification(event, user_id)

      String.contains?(instruction_text, ["add", "note", "hubspot"]) ->
        add_meeting_note_to_hubspot(event, user_id)

      true ->
        {:ok, %{type: "calendar_follow_up", action: "generic", event: event}}
    end
  end

  defp execute_hubspot_follow_up(event, instruction, user_id) do
    # Process HubSpot event based on instruction
    instruction_text = String.downcase(instruction.instruction)

    if String.contains?(instruction_text, ["send", "email", "thank", "you"]) do
      send_thank_you_email(event, user_id)
    else
      {:ok, %{type: "hubspot_follow_up", action: "generic", event: event}}
    end
  end

  defp create_hubspot_contact_from_email(event, user_id) do
    email_data = event["data"]
    sender_email = extract_email_from_address(email_data["from"])
    sender_name = extract_name_from_address(email_data["from"])

    # Check if contact already exists
    case HubspotService.search_contacts(user_id, sender_email) do
      {:ok, []} ->
        # Create new contact
        contact_data = %{
          firstname: extract_first_name(sender_name),
          lastname: extract_last_name(sender_name),
          email: sender_email,
          notes: "Contact created automatically from email: #{email_data["subject"]}"
        }

        case HubspotService.create_contact(user_id, contact_data) do
          {:ok, contact} ->
            Logger.info("Auto-created HubSpot contact: #{sender_name} (#{sender_email})")

            {:ok,
             %{
               type: "auto_contact_created",
               contact_id: contact.id,
               email: sender_email,
               name: sender_name
             }}

          {:error, {409, %{"message" => message}}} ->
            # Contact already exists - extract existing ID if possible
            existing_id = extract_existing_contact_id(message)

            Logger.info(
              "Contact already exists during auto-creation: #{sender_name} (#{sender_email}), existing ID: #{existing_id}"
            )

            {:ok,
             %{
               type: "contact_already_exists",
               contact_id: existing_id,
               email: sender_email,
               name: sender_name,
               message: "Contact already exists in HubSpot"
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, _existing_contacts} ->
        # Contact already exists
        {:ok, %{type: "contact_exists", email: sender_email}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_email_response(event, user_id) do
    email_data = event["data"]

    # Use LLM to generate appropriate response
    context = RagService.search_context(user_id, email_data["subject"])

    prompt = """
    Generate a professional response to this email:

    From: #{email_data["from"]}
    Subject: #{email_data["subject"]}
    Body: #{email_data["body"]}

    Context from previous communications:
    #{inspect(context)}

    Write a helpful, professional response as a financial advisor.
    """

    case LlmService.generate_response_without_tools(prompt, context) do
      {:ok, response} ->
        # Send the email
        reply_subject =
          if String.starts_with?(email_data["subject"], "Re:") do
            email_data["subject"]
          else
            "Re: #{email_data["subject"]}"
          end

        sender_email = extract_email_from_address(email_data["from"])

        case GmailService.send_email(user_id, sender_email, reply_subject, response) do
          {:ok, result} ->
            Logger.info("Auto-replied to email from #{sender_email}")

            {:ok,
             %{
               type: "email_auto_replied",
               recipient: sender_email,
               subject: reply_subject,
               message_id: result["id"]
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason, fallback_response} ->
        {:error, reason, fallback_response}
    end
  end

  defp send_meeting_notification(event, user_id) do
    # Extract attendees from calendar event
    attendees = event["data"]["attendees"] || []
    subject = event["data"]["summary"]
    start_time = event["data"]["start_time"]

    # Generate meeting notification email
    email_body = """
    Hello,

    You have an upcoming meeting scheduled:

    Subject: #{subject}
    Time: #{start_time}

    Please let me know if you need to reschedule.

    Best regards,
    Your Financial Advisor
    """

    # Send to all attendees
    results =
      Enum.map(attendees, fn attendee ->
        case GmailService.send_email(
               user_id,
               attendee["email"],
               "Meeting Reminder: #{subject}",
               email_body
             ) do
          {:ok, result} ->
            Logger.info("Meeting notification sent to #{attendee["email"]}")
            {:ok, result}

          {:error, reason} ->
            Logger.error(
              "Failed to send meeting notification to #{attendee["email"]}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    {:ok, %{type: "meeting_notifications_sent", results: results}}
  end

  defp add_meeting_note_to_hubspot(event, user_id) do
    # Extract meeting details
    subject = event["data"]["summary"]
    start_time = event["data"]["start_time"]
    attendees = event["data"]["attendees"] || []

    note_content = "Meeting scheduled: #{subject} at #{start_time}"

    # Add note to all attendees who are contacts
    results =
      Enum.map(attendees, fn attendee ->
        case HubspotService.search_contacts(user_id, attendee["email"]) do
          {:ok, [contact | _]} ->
            HubspotService.create_note(user_id, contact.id, note_content)

          {:ok, []} ->
            # Contact not found, skip
            {:ok, :skipped}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    {:ok, %{type: "meeting_notes_added", results: results}}
  end

  defp send_thank_you_email(event, user_id) do
    # Extract contact details from HubSpot event
    contact_data = event["data"]
    contact_email = contact_data["email"]
    contact_name = contact_data["firstname"] || "there"

    # Generate thank you email
    email_body = """
    Hello #{contact_name},

    Thank you for becoming a client! We're excited to work with you and help you achieve your financial goals.

    I'll be in touch soon to schedule our first meeting to discuss your financial objectives and how we can best serve you.

    Best regards,
    Your Financial Advisor
    """

    case GmailService.send_email(
           user_id,
           contact_email,
           "Welcome - Thank you for choosing us!",
           email_body
         ) do
      {:ok, result} ->
        Logger.info("Thank you email sent to new client: #{contact_email}")

        {:ok,
         %{
           type: "thank_you_email_sent",
           recipient: contact_email,
           message_id: result["id"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_meeting_confirmation(user_id, client_email, event) do
    # Generate meeting confirmation email
    email_body = """
    Hello,

    Your meeting has been scheduled successfully!

    Details:
    - Subject: #{event.summary}
    - Time: #{event.start_time}
    - Duration: #{calculate_duration(event.start_time, event.end_time)} minutes

    You should receive a calendar invitation shortly.

    Best regards,
    Your Financial Advisor
    """

    case GmailService.send_email(
           user_id,
           client_email,
           "Meeting Confirmed: #{event.summary}",
           email_body
         ) do
      {:ok, _result} ->
        Logger.info("Meeting confirmation sent to #{client_email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send meeting confirmation: #{inspect(reason)}")
        :error
    end
  end

  # Helper functions

  defp extract_first_name(full_name) when is_binary(full_name) do
    String.split(full_name, " ") |> List.first() |> String.trim()
  end

  defp extract_first_name(_), do: ""

  defp extract_last_name(full_name) when is_binary(full_name) do
    parts = String.split(full_name, " ")

    case parts do
      [_] -> ""
      [_ | rest] -> Enum.join(rest, " ") |> String.trim()
    end
  end

  defp extract_last_name(_), do: ""

  defp extract_email_from_address(address) when is_binary(address) do
    case Regex.run(~r/<([^>]+)>/, address) do
      [_, email] ->
        email

      _ ->
        case Regex.run(~r/([\w._%+-]+@[\w.-]+\.[A-Za-z]{2,})/, address) do
          [email | _] -> email
          _ -> address
        end
    end
  end

  defp extract_email_from_address(_), do: ""

  defp extract_name_from_address(address) when is_binary(address) do
    case Regex.run(~r/^([^<]+)</, address) do
      [_, name] ->
        String.trim(name)

      _ ->
        # If no name found, use email prefix
        email = extract_email_from_address(address)

        String.split(email, "@")
        |> List.first()
        |> String.replace(".", " ")
        |> String.capitalize()
    end
  end

  defp extract_name_from_address(_), do: ""

  defp calculate_duration(start_time, end_time) do
    case {DateTime.from_iso8601(start_time), DateTime.from_iso8601(end_time)} do
      {{:ok, start_dt, _}, {:ok, end_dt, _}} ->
        DateTime.diff(end_dt, start_dt, :second) |> div(60)

      _ ->
        # Default to 60 minutes
        60
    end
  end

  defp extract_existing_contact_id(message) when is_binary(message) do
    case Regex.run(~r/Existing ID: (\d+)/, message) do
      [_, contact_id] -> contact_id
      _ -> nil
    end
  end

  defp extract_existing_contact_id(_), do: nil
end
