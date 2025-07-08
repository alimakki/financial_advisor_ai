#!/usr/bin/env elixir

# Simple test script to debug calendar availability
alias FinancialAdvisorAi.Integrations.CalendarService

# Replace with a real user ID from your database
user_id = 1

# Test the find_free_time function
duration_minutes = 60
preferred_times = []

case CalendarService.find_free_time(user_id, duration_minutes, preferred_times) do
  {:ok, slots} ->
    IO.puts("Found #{length(slots)} available slots")

    Enum.each(slots, fn slot ->
      IO.puts("Slot: #{slot.start_time} - #{slot.end_time} (#{slot.timezone})")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end
