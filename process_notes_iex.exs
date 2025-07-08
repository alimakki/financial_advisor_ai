# Interactive HubSpot Contact Notes Processing Script
# Run this in IEx with: iex -S mix
# Then run: import_file("process_notes_iex.exs")

defmodule HubspotNotesProcessor do
  @moduledoc """
  Interactive utility for processing HubSpot contact notes using timestamp-based approach.
  """

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.Integrations.HubspotService

  @doc """
  Lists contacts that need their notes processed.
  """
  def list_contacts_needing_processing(user_id) do
    contacts_never_processed = AI.list_contacts_needing_notes_processing(user_id)
    all_contacts = AI.list_all_contacts_for_notes_processing(user_id)

    IO.puts("📋 Contacts needing notes processing:")
    IO.puts("Never processed: #{length(contacts_never_processed)} contacts")
    IO.puts("Total contacts: #{length(all_contacts)} contacts\n")

    Enum.each(contacts_never_processed, fn contact ->
      full_name = build_contact_name(contact)

      last_processed =
        if contact.notes_last_processed_at do
          "Last processed: #{contact.notes_last_processed_at}"
        else
          "Never processed"
        end

      IO.puts("  • #{full_name}")
      IO.puts("    HubSpot ID: #{contact.contact_id}")
      IO.puts("    Email: #{contact.email || "N/A"}")
      IO.puts("    Company: #{contact.company || "N/A"}")
      IO.puts("    #{last_processed}")
      IO.puts("    Created: #{contact.inserted_at}")
      IO.puts("")
    end)

    contacts_never_processed
  end

  @doc """
  Process notes for all contacts.
  """
  def process_all_notes(user_id) do
    IO.puts("🔄 Processing notes for all contacts...")

    case AI.process_contact_notes(user_id) do
      {:ok, %{processed_count: count, results: results}} ->
        IO.puts("✅ Successfully processed notes for #{count} contacts")

        # Show processing results
        IO.puts("\n📊 Processing results:")

        Enum.each(results, fn {contact_id, result} ->
          case result do
            {:processed, note_count} ->
              IO.puts("  • Contact #{contact_id}: processed #{note_count} notes")

            {:error, reason} ->
              IO.puts("  • Contact #{contact_id}: error - #{inspect(reason)}")
          end
        end)

        verify_processing(user_id)

      {:error, reason} ->
        IO.puts("❌ Error processing notes: #{inspect(reason)}")
    end
  end

  @doc """
  Process notes for a specific contact.
  """
  def process_contact_notes(user_id, contact_id) do
    IO.puts("🔄 Processing notes for contact #{contact_id}...")

    case HubspotService.process_contact_notes(user_id) do
      {:ok, result} ->
        IO.puts("✅ Notes processed successfully")
        IO.inspect(result)

      {:error, reason} ->
        IO.puts("❌ Error processing notes: #{inspect(reason)}")
    end
  end

  @doc """
  Check the status of note processing.
  """
  def check_status(user_id) do
    all_contacts = AI.list_all_contacts_for_notes_processing(user_id)
    never_processed = AI.list_contacts_needing_notes_processing(user_id)
    processed_at_least_once = length(all_contacts) - length(never_processed)

    IO.puts("📊 HubSpot Contact Notes Status:")
    IO.puts("Total contacts: #{length(all_contacts)}")
    IO.puts("Processed at least once: #{processed_at_least_once}")
    IO.puts("Never processed: #{length(never_processed)}")

    if length(all_contacts) > 0 do
      completion_percentage = Float.round(processed_at_least_once / length(all_contacts) * 100, 1)
      IO.puts("Initial processing completion: #{completion_percentage}%")
    end

    IO.puts("\nNote: With timestamp-based processing, contacts are regularly")
    IO.puts("checked for new notes, so this status shows initial processing only.")
  end

  @doc """
  Interactive workflow for processing notes.
  """
  def run_interactive(user_id) do
    IO.puts("🎯 HubSpot Contact Notes Processing (Timestamp-based)")
    IO.puts("=" <> String.duplicate("=", 55))

    check_status(user_id)

    never_processed = list_contacts_needing_processing(user_id)

    if length(never_processed) > 0 do
      IO.puts("\nWould you like to process all contact notes? (y/n)")

      case IO.gets("") |> String.trim() |> String.downcase() do
        "y" -> process_all_notes(user_id)
        "yes" -> process_all_notes(user_id)
        _ -> IO.puts("Skipping note processing.")
      end
    else
      IO.puts("✅ All contacts have been processed at least once!")
      IO.puts("The system will continue to check for new notes automatically.")
    end
  end

  # Private helper functions

  defp build_contact_name(contact) do
    [contact.firstname, contact.lastname]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || "Unknown Contact"
      name -> name
    end
  end

  defp verify_processing(user_id) do
    IO.puts("\n🔍 Verifying processing results...")

    # Show updated stats
    check_status(user_id)

    # Show some example processed notes
    all_contacts = AI.list_all_contacts_for_notes_processing(user_id)

    if length(all_contacts) > 0 do
      sample_contact = Enum.at(all_contacts, 0)
      notes = AI.get_contact_notes_by_contact_id(user_id, sample_contact.contact_id)

      IO.puts("\n📝 Sample notes for #{build_contact_name(sample_contact)}:")
      IO.puts("Found #{length(notes)} notes")

      if length(notes) > 0 do
        sample_note = Enum.at(notes, 0)
        content_preview = String.slice(sample_note.content, 0, 100)
        IO.puts("Sample note: #{content_preview}...")
      end
    end
  end
end

# Instructions for use
IO.puts("🎯 HubSpot Notes Processor loaded!")
IO.puts("Usage:")
IO.puts("  HubspotNotesProcessor.run_interactive(\"your_user_id_here\")")
IO.puts("  HubspotNotesProcessor.check_status(\"your_user_id_here\")")
IO.puts("  HubspotNotesProcessor.process_all_notes(\"your_user_id_here\")")
IO.puts("\nReplace 'your_user_id_here' with an actual user ID from your database.")
