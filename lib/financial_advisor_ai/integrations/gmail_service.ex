defmodule FinancialAdvisorAi.Integrations.GmailService do
  @moduledoc """
  Gmail integration service for reading and sending emails.
  """

  alias FinancialAdvisorAi.AI

  @gmail_base_url "https://gmail.googleapis.com/gmail/v1"

  def list_messages(user_id, opts \\ []) do
    with {:ok, integration} <- get_gmail_integration(user_id),
         {:ok, response} <- make_gmail_request(integration, "/users/me/messages", opts) do
      {:ok, response["messages"] || []}
    else
      error -> error
    end
  end

  def get_message(user_id, message_id) do
    with {:ok, integration} <- get_gmail_integration(user_id),
         {:ok, response} <- make_gmail_request(integration, "/users/me/messages/#{message_id}") do
      {:ok, parse_message(response)}
    else
      error -> error
    end
  end

  def send_email(user_id, to, subject, body) do
    with {:ok, integration} <- get_gmail_integration(user_id),
         {:ok, raw_email} <- create_raw_email(to, subject, body),
         {:ok, response} <-
           make_gmail_request(integration, "/users/me/messages/send", %{raw: raw_email}, :post) do
      {:ok, response}
    else
      error -> error
    end
  end

  def create_contact_from_email(user_id, email_data) do
    # Extract sender information and create embeddings for RAG
    sender = extract_sender(email_data)
    content = extract_content(email_data)

    # Store email embedding for RAG
    AI.create_email_embedding(%{
      user_id: user_id,
      email_id: email_data[:id],
      subject: email_data[:subject],
      content: content,
      sender: sender,
      recipient: extract_recipient(email_data),
      metadata: %{
        thread_id: email_data[:thread_id],
        labels: email_data[:labels] || []
      }
    })
  end

  def search_emails(user_id, query) do
    with {:ok, integration} <- get_gmail_integration(user_id),
         {:ok, response} <- make_gmail_request(integration, "/users/me/messages", %{q: query}) do
      messages = response["messages"] || []

      detailed_messages =
        Enum.map(messages, fn msg ->
          case get_message(user_id, msg["id"]) do
            {:ok, detailed} -> detailed
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, detailed_messages}
    else
      error -> error
    end
  end

  @doc """
  Polls for new Gmail messages for the given user_id, imports them into the email_embeddings table, and updates the last seen message ID in the integration metadata.
  """
  def poll_and_import_new_messages(user_id) do
    with {:ok, integration} <- get_gmail_integration(user_id),
         last_seen_id <- Map.get(integration.metadata || %{}, "last_seen_gmail_id"),
         {:ok, messages} <- list_messages(user_id, %{maxResults: 50}) do
      new_messages =
        case last_seen_id do
          # First import: treat all as new (could limit to N)
          nil ->
            messages

          _ ->
            # Only messages more recent than last_seen_id
            Enum.take_while(messages, fn msg -> msg["id"] != last_seen_id end)
        end

      # Process in reverse order (oldest first)
      new_messages = Enum.reverse(new_messages)

      Enum.each(new_messages, fn msg ->
        case get_message(user_id, msg["id"]) do
          {:ok, email_data} ->
            # Store embedding for RAG
            create_contact_from_email(user_id, email_data)

          _ ->
            :noop
        end
      end)

      # Update last_seen_gmail_id in integration metadata if we processed any new messages
      if new_messages != [] do
        new_metadata =
          Map.put(
            integration.metadata || %{},
            "last_seen_gmail_id",
            List.last(new_messages)["id"]
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

  defp get_gmail_integration(user_id) do
    case AI.get_integration(user_id, "google") do
      nil -> {:error, :not_connected}
      integration -> {:ok, integration}
    end
  end

  defp make_gmail_request(integration, path, params \\ %{}, method \\ :get) do
    url = @gmail_base_url <> path

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

  defp parse_message(response) do
    payload = response["payload"] || %{}
    headers = payload["headers"] || []

    %{
      id: response["id"],
      thread_id: response["threadId"],
      subject: get_header(headers, "Subject"),
      from: get_header(headers, "From"),
      to: get_header(headers, "To"),
      date: get_header(headers, "Date"),
      body: extract_body(payload),
      labels: response["labelIds"] || []
    }
  end

  defp get_header(headers, name) do
    case Enum.find(headers, fn h -> h["name"] == name end) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_body(payload) do
    cond do
      payload["body"]["data"] -> Base.url_decode64!(payload["body"]["data"])
      payload["parts"] -> extract_body_from_parts(payload["parts"])
      true -> ""
    end
  end

  defp extract_body_from_parts(parts) do
    Enum.find_value(parts, "", fn part ->
      if part["mimeType"] == "text/plain" and part["body"]["data"] do
        Base.url_decode64!(part["body"]["data"])
      end
    end)
  end

  defp create_raw_email(to, subject, body) do
    email = """
    To: #{to}
    Subject: #{subject}
    Content-Type: text/plain; charset=UTF-8

    #{body}
    """

    {:ok, Base.encode64(email)}
  end

  defp extract_sender(email_data) do
    email_data[:from]
    |> extract_email_address()
    |> case do
      nil -> "unknown"
      email -> email
    end
  end

  defp extract_content(email_data) do
    email_data[:body]
  end

  defp extract_recipient(email_data) do
    email_data[:to]
    |> extract_email_address()
    |> case do
      nil -> "unknown"
      email -> email
    end
  end

  defp extract_email_address(nil), do: nil

  defp extract_email_address(str) when is_binary(str) do
    # Regex to match email inside angle brackets, or just the email if no brackets
    case Regex.run(~r/<([^>]+)>/, str) do
      [_, email] ->
        email

      _ ->
        # Try to match a plain email
        case Regex.run(~r/([\w._%+-]+@[\w.-]+\.[A-Za-z]{2,})/, str) do
          [email | _] -> email
          _ -> nil
        end
    end
  end
end
