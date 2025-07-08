#!/usr/bin/env elixir

# HubSpot Contact Notes Processing Script
# This script demonstrates how to process notes for contacts using the new timestamp-based approach

# Run this script with: elixir process_hubspot_notes.exs

# Add the project to the load path
Mix.install([])

# Start the application
Application.put_env(:financial_advisor_ai, FinancialAdvisorAi.Repo,
  database: "financial_advisor_ai_dev",
  hostname: "localhost",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true
)

# You'll need to replace this with an actual user ID from your database
user_id = "your_user_id_here"

IO.puts("🔍 Processing HubSpot Contact Notes (Timestamp-based)")
IO.puts("=" <> String.duplicate("=", 60))

# Check which contacts need notes processing
IO.puts("\n📋 Checking for contacts that need notes processing...")
contacts_needing_processing = FinancialAdvisorAi.AI.list_contacts_needing_notes_processing(user_id)
all_contacts = FinancialAdvisorAi.AI.list_all_contacts_for_notes_processing(user_id)

IO.puts("Found #{length(contacts_needing_processing)} contacts that have never had notes processed")
IO.puts("Found #{length(all_contacts)} total contacts")

Enum.each(contacts_needing_processing, fn contact ->
  full_name = [contact.firstname, contact.lastname]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || "Unknown"
      name -> name
    end

  last_processed = if contact.notes_last_processed_at do
    "Last processed: #{contact.notes_last_processed_at}"
  else
    "Never processed"
  end

  IO.puts("  • #{full_name} (#{contact.contact_id}) - #{last_processed}")
end)

IO.puts("\n🔄 Processing notes for all contacts...")
case FinancialAdvisorAi.AI.process_contact_notes(user_id) do
  {:ok, %{processed_count: count, results: results}} ->
    IO.puts("✅ Successfully processed notes for #{count} contacts")

    # Show detailed results
    IO.puts("\n📊 Processing results:")
    Enum.each(results, fn {contact_id, result} ->
      case result do
        {:processed, note_count} ->
          IO.puts("  • Contact #{contact_id}: processed #{note_count} notes")
        {:error, reason} ->
          IO.puts("  • Contact #{contact_id}: error - #{inspect(reason)}")
      end
    end)

  {:error, reason} ->
    IO.puts("❌ Error processing notes: #{inspect(reason)}")
end

IO.puts("\n🎉 Processing complete!")
IO.puts("Notes will now be processed automatically based on timestamps.")
IO.puts("New notes added to contacts will be imported in future runs.")
