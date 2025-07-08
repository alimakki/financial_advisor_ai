defmodule FinancialAdvisorAi.Integrations.CalendarService do
  @moduledoc """
  Google Calendar integration service for managing calendar events and scheduling.
  """

  alias FinancialAdvisorAi.AI

  @calendar_base_url "https://www.googleapis.com/calendar/v3"

  def list_events(user_id, opts \\ []) do
    with {:ok, integration} <- get_google_integration(user_id),
         {:ok, response} <- make_calendar_request(integration, "/calendars/primary/events", opts) do
      {:ok, response["items"] || []}
    else
      error -> error
    end
  end

  def create_event(user_id, event_data) do
    with {:ok, integration} <- get_google_integration(user_id),
         {:ok, response} <-
           make_calendar_request(integration, "/calendars/primary/events", event_data, :post) do
      {:ok, parse_event(response)}
    else
      error -> error
    end
  end

  def get_event(user_id, event_id) do
    with {:ok, integration} <- get_google_integration(user_id),
         {:ok, response} <-
           make_calendar_request(integration, "/calendars/primary/events/#{event_id}") do
      {:ok, parse_event(response)}
    else
      error -> error
    end
  end

  def update_event(user_id, event_id, event_data) do
    with {:ok, integration} <- get_google_integration(user_id),
         {:ok, response} <-
           make_calendar_request(
             integration,
             "/calendars/primary/events/#{event_id}",
             event_data,
             :put
           ) do
      {:ok, parse_event(response)}
    else
      error -> error
    end
  end

  def delete_event(user_id, event_id) do
    with {:ok, integration} <- get_google_integration(user_id),
         {:ok, _response} <-
           make_calendar_request(
             integration,
             "/calendars/primary/events/#{event_id}",
             %{},
             :delete
           ) do
      {:ok, :deleted}
    else
      error -> error
    end
  end

  @doc """
  Finds free time slots for the given user, considering their timezone.
  Returns a list of available time slots in the user's timezone.
  """
  def find_free_time(user_id, duration_minutes, preferred_times \\ []) do
    # Get user to access their timezone
    user = FinancialAdvisorAi.Accounts.get_user!(user_id)
    user_timezone = user.timezone || "UTC"

    # Get events for the next 7 days (in UTC)
    start_time = DateTime.utc_now() |> DateTime.to_iso8601()

    end_time =
      DateTime.utc_now() |> DateTime.add(7 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()

    list_events(user_id, %{
      timeMin: start_time,
      timeMax: end_time,
      singleEvents: true,
      orderBy: "startTime"
    })
    |> case do
      {:ok, events} ->
        IO.puts("Found #{length(events)} events from API")

        free_slots =
          calculate_free_slots(events, duration_minutes, preferred_times, user_timezone)

        IO.puts("Generated #{length(free_slots)} free slots")

        {:ok, free_slots}

      {:error, _} ->
        {:error, :no_events}
    end
  end

  def schedule_meeting_with_client(
        user_id,
        client_email,
        subject,
        duration_minutes \\ 60,
        preferred_times \\ []
      ) do
    # Find available time slots
    case find_free_time(user_id, duration_minutes, preferred_times) do
      {:ok, []} ->
        {:error, :no_available_slots}

      {:ok, [best_slot | _other_slots]} ->
        # Create the meeting event - times are already in UTC from find_free_time
        event_data = %{
          summary: subject,
          description: "Meeting scheduled via AI Financial Advisor",
          start: %{
            dateTime: best_slot.start_time_utc,
            timeZone: "UTC"
          },
          end: %{
            dateTime: best_slot.end_time_utc,
            timeZone: "UTC"
          },
          attendees: [
            %{email: client_email}
          ],
          reminders: %{
            useDefault: false,
            overrides: [
              # 24 hours
              %{method: "email", minutes: 1440},
              %{method: "popup", minutes: 15}
            ]
          }
        }

        create_event(user_id, event_data)

      error ->
        error
    end
  end

  @doc """
  Polls for new Google Calendar events for the given user_id.
  Returns a list of new event objects (raw data).
  """
  def poll_new_events(_user_id) do
    # TODO: Track last seen event, fetch new ones, return as events
    {:ok, []}
  end

  defp get_google_integration(user_id) do
    case AI.get_integration(user_id, "google") do
      nil -> {:error, :not_connected}
      integration -> {:ok, integration}
    end
  end

  defp make_calendar_request(integration, path, params \\ %{}, method \\ :get) do
    url = @calendar_base_url <> path

    headers = [
      {"Authorization", "Bearer #{integration.access_token}"},
      {"Content-Type", "application/json"}
    ]

    case method do
      :get ->
        query_string = URI.encode_query(params)
        full_url = if query_string != "", do: "#{url}?#{query_string}", else: url

        Req.get(full_url, headers: headers)

      :post ->
        Req.post(url, headers: headers, json: params)

      :put ->
        Req.put(url, headers: headers, json: params)

      :delete ->
        Req.delete(url, headers: headers)
    end
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, {status, body}}
  end

  defp handle_response({:error, error}) do
    {:error, error}
  end

  defp parse_event(response) do
    %{
      id: response["id"],
      summary: response["summary"],
      description: response["description"],
      start_time: get_in(response, ["start", "dateTime"]) || get_in(response, ["start", "date"]),
      end_time: get_in(response, ["end", "dateTime"]) || get_in(response, ["end", "date"]),
      attendees: response["attendees"] || [],
      location: response["location"],
      status: response["status"],
      html_link: response["htmlLink"]
    }
  end

  defp calculate_free_slots(events, duration_minutes, preferred_times, user_timezone) do
    # Get the current time range for filtering
    now_utc = DateTime.utc_now()
    end_time_utc = DateTime.add(now_utc, 7 * 24 * 60 * 60, :second)

    # Convert events to busy periods - only include events within the next 7 days
    busy_periods =
      events
      |> Enum.filter(fn event ->
        event["status"] != "cancelled" and Map.has_key?(event, "start") and
          Map.has_key?(event, "end")
      end)
      |> Enum.map(fn event ->
        start_time_str = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
        end_time_str = get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"])

        with {:ok, start_dt, _} <- DateTime.from_iso8601(start_time_str),
             {:ok, end_dt, _} <- DateTime.from_iso8601(end_time_str) do
          {convert_to_utc(start_dt), convert_to_utc(end_dt)}
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {start_utc, _end_utc} ->
        DateTime.compare(start_utc, now_utc) != :lt and
          DateTime.compare(start_utc, end_time_utc) != :gt
      end)
      |> Enum.sort_by(fn {start_utc, _} -> start_utc end)

    # Generate potential time slots based on preferred_times if provided, otherwise use business hours
    # Ensure preferred_times is a list (require nil case)
    preferred_times = preferred_times || []

    potential_slots =
      if not Enum.empty?(preferred_times) do
        generate_slots_from_preferred_times(preferred_times, duration_minutes, user_timezone)
      else
        generate_business_hour_slots(duration_minutes, user_timezone)
      end

    IO.puts("Generated #{length(potential_slots)} potential slots")

    # Filter out busy periods and past time slots
    free_slots =
      potential_slots
      |> Enum.reject(fn slot ->
        overlaps_with_busy =
          Enum.any?(busy_periods, fn {busy_start, busy_end} ->
            result = slots_overlap?(slot, {busy_start, busy_end})
            result
          end)

        overlaps_with_busy
      end)
      |> Enum.filter(fn {start_time_utc, _end_time_utc, _start_time_user, _end_time_user} ->
        # Only include slots that are in the future (using UTC for consistent comparison)
        case DateTime.from_iso8601(start_time_utc) do
          {:ok, slot_start_time, _} ->
            DateTime.compare(slot_start_time, now_utc) == :gt

          _ ->
            false
        end
      end)
      |> Enum.map(fn {start_time_utc, end_time_utc, start_time_user, end_time_user} ->
        %{
          # Display time in user's timezone
          start_time: start_time_user,
          # Display time in user's timezone
          end_time: end_time_user,
          # UTC time for API calls
          start_time_utc: start_time_utc,
          # UTC time for API calls
          end_time_utc: end_time_utc,
          duration_minutes: duration_minutes,
          timezone: user_timezone
        }
      end)
      # Return top 5 available slots
      |> Enum.take(5)

    free_slots
  end

  defp generate_business_hour_slots(duration_minutes, user_timezone) do
    # Generate slots for the next 7 days during business hours (9 AM - 5 PM in user's timezone)
    now = DateTime.utc_now()

    0..6
    |> Enum.flat_map(fn day_offset ->
      day = DateTime.add(now, day_offset * 24 * 60 * 60, :second)

      generate_day_slots(day, duration_minutes, user_timezone)
    end)
  end

  defp generate_slots_from_preferred_times(preferred_times, duration_minutes, user_timezone) do
    now_utc = DateTime.utc_now()

    # Parse preferred times and generate slots for each time range
    preferred_times
    |> Enum.flat_map(fn time_range ->
      case parse_time_range(time_range) do
        {:ok, {start_time, end_time}} ->
          # Skip preferred times that are in the past
          if DateTime.compare(start_time, now_utc) == :gt do
            generate_slots_in_range(start_time, end_time, duration_minutes, user_timezone)
          else
            # Skip past preferred times
            []
          end

        {:error, _} ->
          # If parsing fails, skip this time range
          []
      end
    end)
  end

  defp parse_time_range(time_range) do
    # Parse time ranges in format "YYYY-MM-DDTHH:MM:SSZ/YYYY-MM-DDTHH:MM:SSZ"
    case String.split(time_range, "/") do
      [start_str, end_str] ->
        with {:ok, start_dt, _} <- DateTime.from_iso8601(start_str),
             {:ok, end_dt, _} <- DateTime.from_iso8601(end_str) do
          {:ok, {start_dt, end_dt}}
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp generate_slots_in_range(start_time, end_time, duration_minutes, user_timezone) do
    # Generate slots within the specified time range
    duration_seconds = duration_minutes * 60

    # Convert times to user timezone for processing
    case {DateTime.shift_zone(start_time, user_timezone),
          DateTime.shift_zone(end_time, user_timezone)} do
      {{:ok, user_start}, {:ok, user_end}} ->
        # Generate slots at the requested time
        if DateTime.diff(user_end, user_start, :second) >= duration_seconds do
          # Create a single slot for the exact time range requested
          [
            {
              # UTC for API
              DateTime.to_iso8601(start_time),
              # UTC for API
              DateTime.to_iso8601(DateTime.add(start_time, duration_seconds, :second)),
              # User timezone for display
              DateTime.to_iso8601(user_start),
              # User timezone for display
              DateTime.to_iso8601(DateTime.add(user_start, duration_seconds, :second))
            }
          ]
        else
          []
        end

      _ ->
        # Fallback to UTC if timezone conversion fails
        if DateTime.diff(end_time, start_time, :second) >= duration_seconds do
          [
            {
              DateTime.to_iso8601(start_time),
              DateTime.to_iso8601(DateTime.add(start_time, duration_seconds, :second)),
              DateTime.to_iso8601(start_time),
              DateTime.to_iso8601(DateTime.add(start_time, duration_seconds, :second))
            }
          ]
        else
          []
        end
    end
  end

  defp generate_day_slots(day, duration_minutes, user_timezone) do
    # Convert UTC day to user's timezone to check day of week
    user_day = convert_utc_to_timezone(day, user_timezone)

    # Skip weekends (in user's timezone)
    if Date.day_of_week(DateTime.to_date(user_day)) in [6, 7] do
      []
    else
      # Get current time in user's timezone for comparison
      now_in_user_tz = convert_utc_to_timezone(DateTime.utc_now(), user_timezone)

      # Generate hourly slots from 9 AM to 5 PM in user's timezone
      9..16
      |> Enum.map(fn hour ->
        calculate_start_end_times(user_day, hour, duration_minutes, user_timezone)
      end)
      |> Enum.filter(fn {_utc_start, _utc_end, user_start, _user_end} ->
        # Only include slots that are in the future
        case DateTime.from_iso8601(user_start) do
          {:ok, slot_start_time, _} ->
            DateTime.compare(slot_start_time, now_in_user_tz) == :gt

          _ ->
            false
        end
      end)
    end
  end

  defp calculate_start_end_times(user_day, hour, duration_minutes, user_timezone) do
    # Create date from user_day
    date = DateTime.to_date(user_day)
    time = Time.new!(hour, 0, 0)

    # Create naive datetime first
    naive_start_time = NaiveDateTime.new!(date, time)

    # Convert to user's timezone with DST support
    case DateTime.from_naive(naive_start_time, user_timezone) do
      {:ok, user_start_time} ->
        # Convert to UTC for storage and API calls
        case DateTime.shift_zone(user_start_time, "UTC") do
          {:ok, utc_start_time} ->
            # Calculate end times
            user_end_time = DateTime.add(user_start_time, duration_minutes * 60, :second)
            utc_end_time = DateTime.add(utc_start_time, duration_minutes * 60, :second)

            {
              # UTC for API
              DateTime.to_iso8601(utc_start_time),
              # UTC for API
              DateTime.to_iso8601(utc_end_time),
              # User timezone for display
              DateTime.to_iso8601(user_start_time),
              # User timezone for display
              DateTime.to_iso8601(user_end_time)
            }

          {:error, _} ->
            # Fallback to simpler calculation if timezone shift fails
            fallback_calculate_times(naive_start_time, duration_minutes, user_timezone)
        end

      {:error, _} ->
        # Fallback to simpler calculation if timezone creation fails
        fallback_calculate_times(naive_start_time, duration_minutes, user_timezone)
    end
  end

  # Fallback calculation method
  defp fallback_calculate_times(naive_start_time, duration_minutes, _user_timezone) do
    # Use UTC as fallback
    utc_start_time = DateTime.from_naive!(naive_start_time, "Etc/UTC")
    utc_end_time = DateTime.add(utc_start_time, duration_minutes * 60, :second)

    {
      DateTime.to_iso8601(utc_start_time),
      DateTime.to_iso8601(utc_end_time),
      DateTime.to_iso8601(utc_start_time),
      DateTime.to_iso8601(utc_end_time)
    }
  end

  defp slots_overlap?({slot_start_utc, slot_end_utc, _, _}, {busy_start, busy_end}) do
    # Parse slot times (which are ISO8601 strings) and normalize busy times (which are already DateTime objects)
    case {DateTime.from_iso8601(slot_start_utc), DateTime.from_iso8601(slot_end_utc)} do
      {{:ok, slot_start_dt, _}, {:ok, slot_end_dt, _}} ->
        # Convert all times to UTC for consistent comparison
        slot_start_utc_dt = convert_to_utc(slot_start_dt)
        slot_end_utc_dt = convert_to_utc(slot_end_dt)

        # busy_start and busy_end are already DateTime objects, just convert to UTC
        busy_start_utc_dt = convert_to_utc(busy_start)
        busy_end_utc_dt = convert_to_utc(busy_end)

        # Check for overlap using UTC times
        overlap_result =
          DateTime.compare(slot_start_utc_dt, busy_end_utc_dt) == :lt and
            DateTime.compare(slot_end_utc_dt, busy_start_utc_dt) == :gt

        overlap_result

      _ ->
        # If we can't parse dates, assume no overlap
        false
    end
  end

  # Helper function to safely convert DateTime to UTC
  defp convert_to_utc(datetime) do
    case DateTime.shift_zone(datetime, "UTC") do
      {:ok, utc_datetime} -> utc_datetime
      # Return original if conversion fails
      {:error, _} -> datetime
    end
  end

  # Timezone conversion helper functions with DST support
  defp convert_utc_to_timezone(utc_datetime, timezone) when timezone == "UTC" do
    utc_datetime
  end

  defp convert_utc_to_timezone(utc_datetime, timezone) do
    # Use proper timezone conversion with DST support
    case DateTime.shift_zone(utc_datetime, timezone) do
      {:ok, shifted_datetime} -> shifted_datetime
      # Fallback to UTC if timezone is invalid
      {:error, _} -> utc_datetime
    end
  end
end
