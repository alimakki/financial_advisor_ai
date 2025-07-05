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

  def find_free_time(user_id, duration_minutes, preferred_times \\ []) do
    # Get events for the next 7 days
    start_time = DateTime.utc_now() |> DateTime.to_iso8601()

    end_time =
      DateTime.utc_now() |> DateTime.add(7 * 24 * 60 * 60, :second) |> DateTime.to_iso8601()

    with {:ok, events} <-
           list_events(user_id, %{
             timeMin: start_time,
             timeMax: end_time,
             singleEvents: true,
             orderBy: "startTime"
           }) do
      free_slots = calculate_free_slots(events, duration_minutes, preferred_times)
      {:ok, free_slots}
    else
      error -> error
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
        # Create the meeting event
        event_data = %{
          summary: subject,
          description: "Meeting scheduled via AI Financial Advisor",
          start: %{
            dateTime: best_slot.start_time,
            timeZone: "UTC"
          },
          end: %{
            dateTime: best_slot.end_time,
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
  def poll_new_events(user_id) do
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

  defp calculate_free_slots(events, duration_minutes, preferred_times) do
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

    # Generate potential time slots (business hours: 9 AM - 5 PM)
    potential_slots = generate_business_hour_slots(duration_minutes)

    # Filter out busy periods
    free_slots =
      potential_slots
      |> Enum.reject(fn slot ->
        Enum.any?(busy_periods, fn {busy_start, busy_end} ->
          slots_overlap?(slot, {busy_start, busy_end})
        end)
      end)
      |> Enum.map(fn {start_time, end_time} ->
        %{
          start_time: start_time,
          end_time: end_time,
          duration_minutes: duration_minutes
        }
      end)
      # Return top 5 available slots
      |> Enum.take(5)

    free_slots
  end

  defp generate_business_hour_slots(duration_minutes) do
    # Generate slots for the next 7 days during business hours (9 AM - 5 PM)
    now = DateTime.utc_now()

    0..6
    |> Enum.flat_map(fn day_offset ->
      day = DateTime.add(now, day_offset * 24 * 60 * 60, :second)

      # Skip weekends
      if Date.day_of_week(DateTime.to_date(day)) in [6, 7] do
        []
      else
        # Generate hourly slots from 9 AM to 5 PM
        9..16
        |> Enum.map(fn hour ->
          start_time =
            day
            |> DateTime.to_date()
            |> DateTime.new!(Time.new!(hour, 0, 0), "UTC")
            |> DateTime.to_iso8601()

          end_time =
            day
            |> DateTime.to_date()
            |> DateTime.new!(Time.new!(hour, 0, 0), "UTC")
            |> DateTime.add(duration_minutes * 60, :second)
            |> DateTime.to_iso8601()

          {start_time, end_time}
        end)
      end
    end)
  end

  defp slots_overlap?({slot_start, slot_end}, {busy_start, busy_end}) do
    case {DateTime.from_iso8601(slot_start), DateTime.from_iso8601(slot_end),
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
end
