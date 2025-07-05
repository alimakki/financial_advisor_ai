# Create sample email data for testing RAG functionality

import Ecto.Query
alias FinancialAdvisorAi.{Repo, AI, Accounts}

# Get our test user
user = Repo.get_by!(Accounts.User, email: "webshookeng@gmail.com")

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

IO.puts("✅ Created sample email data for RAG testing!")
