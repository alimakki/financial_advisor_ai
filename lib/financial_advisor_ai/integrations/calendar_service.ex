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
        free_slots = calculate_free_slots(events, duration_minutes, preferred_times, user_timezone)
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

  defp calculate_free_slots(events, duration_minutes, _preferred_times, user_timezone) do
    # Convert events to busy periods
    busy_periods =
      events
      |> Enum.filter(fn event -> event["status"] != "cancelled" end)
      |> Enum.map(fn event ->
        start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
        end_time = get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"])

        {start_time, end_time}
      end)
      |> Enum.sort()

    # Generate potential time slots (business hours: 9 AM - 5 PM in user's timezone)
    potential_slots = generate_business_hour_slots(duration_minutes, user_timezone)

    # Filter out busy periods
    free_slots =
      potential_slots
      |> Enum.reject(fn slot ->
        Enum.any?(busy_periods, fn {busy_start, busy_end} ->
          slots_overlap?(slot, {busy_start, busy_end})
        end)
      end)
      |> Enum.map(fn {start_time_utc, end_time_utc, start_time_user, end_time_user} ->
        %{
          start_time: start_time_user,           # Display time in user's timezone
          end_time: end_time_user,               # Display time in user's timezone
          start_time_utc: start_time_utc,        # UTC time for API calls
          end_time_utc: end_time_utc,            # UTC time for API calls
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

  defp generate_day_slots(day, duration_minutes, user_timezone) do
    # Convert UTC day to user's timezone to check day of week
    user_day = convert_utc_to_timezone(day, user_timezone)

    # Skip weekends (in user's timezone)
    if Date.day_of_week(DateTime.to_date(user_day)) in [6, 7] do
      []
    else
      # Generate hourly slots from 9 AM to 5 PM in user's timezone
      9..16
      |> Enum.map(fn hour ->
        calculate_start_end_times(user_day, hour, duration_minutes, user_timezone)
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
              DateTime.to_iso8601(utc_start_time),     # UTC for API
              DateTime.to_iso8601(utc_end_time),       # UTC for API
              DateTime.to_iso8601(user_start_time),    # User timezone for display
              DateTime.to_iso8601(user_end_time)       # User timezone for display
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
    case {DateTime.from_iso8601(slot_start_utc), DateTime.from_iso8601(slot_end_utc),
          DateTime.from_iso8601(busy_start), DateTime.from_iso8601(busy_end)} do
      {{:ok, slot_start_dt, _}, {:ok, slot_end_dt, _}, {:ok, busy_start_dt, _},
       {:ok, busy_end_dt, _}} ->
        DateTime.compare(slot_start_dt, busy_end_dt) == :lt and
          DateTime.compare(slot_end_dt, busy_start_dt) == :gt

      _ ->
        # If we can't parse dates, assume no overlap
        false
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
      {:error, _} -> utc_datetime  # Fallback to UTC if timezone is invalid
    end
  end
end
