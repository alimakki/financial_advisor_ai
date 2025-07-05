# Sample email data for testing RAG functionality

import Ecto.Query
alias FinancialAdvisorAi.{Repo, AI, Accounts}

# Get our test user
user = Repo.one(from u in Accounts.User, where: u.email == "webshookeng@gmail.com")

if user do
  # Create sample email embeddings for testing RAG
  {:ok, _} = AI.create_email_embedding(%{
    user_id: user.id,
    email_id: "email_1",
    subject: "Baseball season starting soon",
    content: "Hi John, my son's baseball season is starting next month. We'll need to adjust our meeting schedule around his games. Let me know what works for you.",
    sender: "sarah.johnson@email.com",
    recipient: "webshookeng@gmail.com",
    metadata: %{keywords: ["baseball", "son", "meeting", "schedule"]}
  })

  {:ok, _} = AI.create_email_embedding(%{
    user_id: user.id,
    email_id: "email_2",
    subject: "AAPL Stock Discussion",
    content: "Greg here. I've been thinking about selling my AAPL stock position. The market seems volatile and I want to take some profits. What are your thoughts?",
    sender: "greg.miller@email.com",
    recipient: "webshookeng@gmail.com",keywords: ["AAPL", "stock", "sell", "profits"]}
  })

  {:ok, _} = AI.create_email_embedding(%{
    user_id: user.id,
    email_id: "email_3",
    subject: "Daughter's soccer tournament",
    content: "My daughter has a soccer tournament this weekend. Could we reschedule our investment review meeting to next week?",
    sender: "mike.chen@email.com",
    recipient: "webshookeng@gmail.com",keywords: ["daughter", "soccer", "tournament", "meeting"]}
  })

  IO.puts("Sample email data created for RAG testing!")
  IO.puts("- Baseball email from Sarah Johnson")
  IO.puts("- AAPL stock email from Greg Miller")
  IO.puts("- Soccer tournament email from Mike Chen")
else
  IO.puts("Test user not found. Please run mix run priv/repo/seeds.exs first.")
end
