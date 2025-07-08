defmodule FinancialAdvisorAi.Integrations.HubspotService do
  @moduledoc """
  HubSpot CRM integration service for managing contacts, companies, deals, and notes.
  """

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.Integrations.TokenRefreshService

  require Logger

  @hubspot_base_url "https://api.hubapi.com"

  def list_contacts(user_id, opts \\ []) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <- make_hubspot_request(integration, "/crm/v3/objects/contacts", opts) do
      {:ok, response["results"] || []}
    else
      error -> error
    end
  end

  def get_contact(user_id, contact_id) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(integration, "/crm/v3/objects/contacts/#{contact_id}") do
      {:ok, parse_contact(response)}
    else
      error -> error
    end
  end

  def create_contact(user_id, contact_data) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(
             integration,
             "/crm/v3/objects/contacts",
             %{properties: contact_data},
             :post
           ) do
      {:ok, parse_contact(response)}
    else
      error -> error
    end
  end

  def update_contact(user_id, contact_id, contact_data) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(
             integration,
             "/crm/v3/objects/contacts/#{contact_id}",
             %{properties: contact_data},
             :patch
           ) do
      {:ok, parse_contact(response)}
    else
      error -> error
    end
  end

  def search_contacts(user_id, query) do
    email_filter = %{
      filters: [
        %{
          propertyName: "email",
          operator: "EQ",
          value: query
        }
      ]
    }

    name_filters =
      for field <- ["firstname", "lastname"] do
        %{
          filters: [
            %{
              propertyName: field,
              operator: "CONTAINS_TOKEN",
              value: query
            }
          ]
        }
      end

    filter_groups = [email_filter | name_filters]

    search_request = %{
      filterGroups: filter_groups,
      properties: ["email", "firstname", "lastname"],
      limit: 10
    }

    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(
             integration,
             "/crm/v3/objects/contacts/search",
             search_request,
             :post
           ) do
      contacts = response["results"] || []
      parsed_contacts = Enum.map(contacts, &parse_contact/1)
      {:ok, parsed_contacts}
    else
      error -> error
    end
  end

  def create_note(user_id, contact_id, note_content) do
    note_data = %{
      properties: %{
        hs_note_body: note_content,
        hs_timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      },
      associations: [
        %{
          to: %{id: contact_id},
          types: [%{associationCategory: "HUBSPOT_DEFINED", associationTypeId: 202}]
        }
      ]
    }

    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(integration, "/crm/v3/objects/notes", note_data, :post) do
      {:ok, response}
    else
      error -> error
    end
  end

  def get_contact_activities(user_id, contact_id) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(
             integration,
             "/crm/v3/objects/contacts/#{contact_id}/associations/notes"
           ) do
      {:ok, response["results"] || []}
    else
      error -> error
    end
  end

  @doc """
  Polls for new Hubspot contact or note events for the given user_id.
  Returns a list of new event objects (raw data).
  """
  def poll_new_events(user_id) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         last_seen_timestamp <-
           Map.get(integration.metadata || %{}, "last_seen_hubspot_timestamp"),
         {:ok, contacts} <- fetch_contacts_since(integration, last_seen_timestamp) do
      # Return raw contact data as events
      {:ok, contacts}
    else
      error -> error
    end
  end

  @doc """
  Polls for new or updated HubSpot contacts and notes for the given user_id,
  imports them into the contact_embeddings table, and updates the last seen
  timestamp in the integration metadata.
  """
  def poll_and_import_contacts_and_notes(user_id) do
    IO.inspect(user_id, label: "polling hubspot for user_id #{user_id}")

    with {:ok, integration} <- get_hubspot_integration(user_id),
         last_seen_timestamp <-
           Map.get(integration.metadata || %{}, "last_seen_hubspot_timestamp"),
         {:ok, contacts} <- fetch_contacts_since(integration, last_seen_timestamp) do
      # Process contacts and their notes
      # |> IO.inspect(label: "processed_contacts")
      processed_contacts =
        process_contacts_for_import(contacts, user_id)

      # Import contacts to embeddings
      import_contacts_to_embeddings(processed_contacts, user_id)

      # Update last seen timestamp if we processed any contacts
      if length(processed_contacts) > 0 do
        new_metadata =
          Map.put(
            integration.metadata || %{},
            "last_seen_hubspot_timestamp",
            DateTime.utc_now() |> DateTime.to_unix(:millisecond)
          )

        integration
        |> Ecto.Changeset.change(metadata: new_metadata)
        |> FinancialAdvisorAi.Repo.update()
      else
        :ok
      end
    else
      error -> error
    end
  end

  defp get_hubspot_integration(user_id) do
    case AI.get_integration(user_id, "hubspot") do
      nil ->
        {:error, :not_connected}

      integration ->
        # Check if token needs refreshing and refresh if necessary
        case TokenRefreshService.refresh_if_needed(integration) do
          {:ok, updated_integration} ->
            {:ok, updated_integration}

          {:error, reason} ->
            Logger.warning(
              "Token refresh failed for HubSpot integration user #{user_id}: #{inspect(reason)}"
            )

            # Still try to use the existing token in case it works
            {:ok, integration}
        end
    end
  end

  defp make_hubspot_request(integration, path, params \\ %{}, method \\ :get) do
    url = @hubspot_base_url <> path

    headers = [
      {"Authorization", "Bearer #{integration.access_token}"},
      {"Content-Type", "application/json"}
    ]

    # IO.inspect(path, label: "path")
    # IO.inspect(params, label: "params")
    # IO.inspect(method, label: "method")

    case method do
      :get ->
        query_string = URI.encode_query(params)
        full_url = if query_string != "", do: "#{url}?#{query_string}", else: url
        Req.get(full_url, headers: headers)

      :post ->
        Req.post(url, headers: headers, json: params)

      :patch ->
        Req.patch(url, headers: headers, json: params)
    end
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.error("Hubspot request failed with status #{status} and body #{inspect(body)}")
    {:error, {status, body}}
  end

  defp handle_response({:error, error}) do
    {:error, error}
  end

  defp parse_contact(response) do
    properties = response["properties"] || %{}

    %{
      id: response["id"],
      email: properties["email"],
      first_name: properties["firstname"],
      last_name: properties["lastname"],
      company: properties["company"],
      phone: properties["phone"],
      lifecycle_stage: properties["lifecyclestage"],
      lead_status: properties["hs_lead_status"],
      created_at: properties["createdate"],
      updated_at: properties["lastmodifieddate"]
    }
  end

  defp fetch_contacts_since(integration, last_seen_timestamp) do
    # Build query parameters for fetching contacts
    # HubSpot API expects properties as comma-separated string
    properties_string =
      [
        "email",
        "firstname",
        "lastname",
        "company",
        "phone",
        "lifecyclestage",
        "hs_lead_status",
        "createdate",
        "lastmodifieddate",
        "notes"
      ]
      |> Enum.join(",")

    params = %{
      limit: 100,
      properties: properties_string
    }

    # If we have a last seen timestamp, add it to the query
    params =
      if last_seen_timestamp do
        Map.put(params, :after, last_seen_timestamp)
      else
        params
      end

    make_hubspot_request(integration, "/crm/v3/objects/contacts", params)
    |> IO.inspect(label: "fetch_contacts_since")
    |> case do
      {:ok, response} -> {:ok, response["results"] || []}
      error -> error
    end
  end

  defp process_contacts_for_import(contacts, _user_id) do
    Enum.map(contacts, fn contact ->
      # Parse the contact data
      parsed_contact = parse_contact(contact)

      # Create contact content for embedding (without notes)
      content = build_contact_content(parsed_contact)

      Map.put(parsed_contact, :content, content)
    end)
  end

  defp get_contact_notes(user_id, contact_id) do
    case get_hubspot_integration(user_id) do
      {:ok, integration} ->
        make_hubspot_request(
          integration,
          "/crm/v3/objects/contacts/#{contact_id}/associations/notes"
        )
        |> case do
          {:ok, response} -> {:ok, response["results"] || []}
          error -> error
        end

      error ->
        error
    end
  end

  defp build_contact_content(contact) do
    [
      "Name: #{contact.first_name} #{contact.last_name}",
      "Email: #{contact.email}",
      "Company: #{contact.company}",
      "Phone: #{contact.phone}",
      "Lifecycle Stage: #{contact.lifecycle_stage}",
      "Lead Status: #{contact.lead_status}"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(". ")
  end

  defp import_contacts_to_embeddings(contacts, user_id) do
    alias FinancialAdvisorAi.AI.LlmService

    Enum.each(contacts, fn contact ->
      # Generate embedding for the contact content
      embedding =
        case LlmService.create_embedding(contact.content) do
          {:ok, response} ->
            get_in(response, ["data", Access.at(0), "embedding"])

          {:error, _} ->
            nil
        end

      # Create contact embedding record (without notes)
      contact_embedding_attrs = %{
        user_id: user_id,
        contact_id: contact.id,
        firstname: contact.first_name,
        lastname: contact.last_name,
        email: contact.email,
        company: contact.company,
        phone: contact.phone,
        lifecycle_stage: contact.lifecycle_stage,
        lead_status: contact.lead_status,
        content: contact.content,
        embedding: embedding,
        notes_processed: false,
        metadata: %{
          created_at: contact.created_at,
          updated_at: contact.updated_at,
          processed_at: DateTime.utc_now()
        }
      }

      # Create or update the contact embedding
      contact_embedding =
        case FinancialAdvisorAi.AI.get_contact_embedding_by_contact_id(user_id, contact.id) do
          nil ->
            case FinancialAdvisorAi.AI.create_contact_embedding(contact_embedding_attrs) do
              {:ok, contact_embedding} -> contact_embedding
              _ -> nil
            end

          existing ->
            case FinancialAdvisorAi.AI.update_contact_embedding(existing, contact_embedding_attrs) do
              {:ok, contact_embedding} -> contact_embedding
              _ -> existing
            end
        end

      # Now process notes separately if contact embedding was created/updated successfully
      if contact_embedding do
        process_contact_notes(user_id, contact.id, contact_embedding.id)
      end
    end)
  end

  defp process_contact_notes(user_id, contact_id, contact_embedding_id) do
    alias FinancialAdvisorAi.AI.LlmService

    # Fetch notes for this contact
    case get_contact_notes(user_id, contact_id) |> IO.inspect(label: "get_contact_notes") do
      {:ok, notes_data} ->
        # Process each note separately
        Enum.each(notes_data, fn note_data ->
          # Extract note content
          note_content =
            case note_data["properties"] do
              %{"hs_note_body" => body} -> body
              _ -> ""
            end

          # Only process if note has content
          if note_content != "" do
            # Check if note already exists to avoid duplicates
            hubspot_note_id = note_data["id"]

            existing_note =
              FinancialAdvisorAi.AI.get_contact_note_by_hubspot_id(user_id, hubspot_note_id)

            if is_nil(existing_note) do
              # Generate embedding for the note content
              embedding =
                case LlmService.create_embedding(note_content) do
                  {:ok, response} ->
                    get_in(response, ["data", Access.at(0), "embedding"])

                  {:error, _} ->
                    nil
                end

              # Create contact note record
              note_attrs = %{
                user_id: user_id,
                contact_embedding_id: contact_embedding_id,
                hubspot_note_id: hubspot_note_id,
                content: note_content,
                embedding: embedding,
                metadata: %{
                  created_at: note_data["createdAt"],
                  updated_at: note_data["updatedAt"],
                  processed_at: DateTime.utc_now()
                }
              }

              FinancialAdvisorAi.AI.create_contact_note(note_attrs)
            end
          end
        end)

        # Mark contact as having notes processed
        contact_embedding =
          FinancialAdvisorAi.AI.get_contact_embedding_by_contact_id(user_id, contact_id)

        if contact_embedding do
          FinancialAdvisorAi.AI.update_contact_embedding(contact_embedding, %{
            notes_processed: true
          })
        end

      {:error, _} ->
        # If we can't fetch notes, still mark as processed to avoid retrying
        contact_embedding =
          FinancialAdvisorAi.AI.get_contact_embedding_by_contact_id(user_id, contact_id)

        if contact_embedding do
          FinancialAdvisorAi.AI.update_contact_embedding(contact_embedding, %{
            notes_processed: true
          })
        end
    end
  end
end
