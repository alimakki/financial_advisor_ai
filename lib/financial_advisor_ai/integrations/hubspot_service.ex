defmodule FinancialAdvisorAi.Integrations.HubspotService do
  @moduledoc """
  HubSpot CRM integration service for managing contacts, companies, deals, and notes.
  """

  alias FinancialAdvisorAi.AI

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
           make_hubspot_request(integration, "/crm/v3/objects/contacts", contact_data, :post) do
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
             contact_data,
             :patch
           ) do
      {:ok, parse_contact(response)}
    else
      error -> error
    end
  end

  def search_contacts(user_id, query) do
    search_request = %{
      filterGroups: [
        %{
          filters: [
            %{
              propertyName: "email",
              operator: "CONTAINS_TOKEN",
              value: query
            },
            %{
              propertyName: "firstname",
              operator: "CONTAINS_TOKEN",
              value: query
            },
            %{
              propertyName: "lastname",
              operator: "CONTAINS_TOKEN",
              value: query
            }
          ]
        }
      ]
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

  def list_companies(user_id, opts \\ []) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <- make_hubspot_request(integration, "/crm/v3/objects/companies", opts) do
      {:ok, response["results"] || []}
    else
      error -> error
    end
  end

  def create_company(user_id, company_data) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(integration, "/crm/v3/objects/companies", company_data, :post) do
      {:ok, response}
    else
      error -> error
    end
  end

  def list_deals(user_id, opts \\ []) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <- make_hubspot_request(integration, "/crm/v3/objects/deals", opts) do
      {:ok, response["results"] || []}
    else
      error -> error
    end
  end

  def create_deal(user_id, deal_data) do
    with {:ok, integration} <- get_hubspot_integration(user_id),
         {:ok, response} <-
           make_hubspot_request(integration, "/crm/v3/objects/deals", deal_data, :post) do
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
  def poll_new_events(_user_id) do
    # TODO: Track last seen event, fetch new ones, return as events
    {:ok, []}
  end

  defp get_hubspot_integration(user_id) do
    case AI.get_integration(user_id, "hubspot") do
      nil -> {:error, :not_connected}
      integration -> {:ok, integration}
    end
  end

  defp make_hubspot_request(integration, path, params \\ %{}, method \\ :get) do
    url = @hubspot_base_url <> path

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

      :patch ->
        Req.patch(url, headers: headers, json: params)

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
      updated_at: properties["lastmodifieddate"],
      notes: properties["notes"]
    }
  end
end
