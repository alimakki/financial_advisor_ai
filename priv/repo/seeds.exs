# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     FinancialAdvisorAi.Repo.insert!(%FinancialAdvisorAi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query
alias FinancialAdvisorAi.{Repo, Accounts}

# Create test user for OAuth testing
email = "webshookeng@gmail.com"
password = "password123456"

# Check if user already exists
existing_user = Repo.one(from u in Accounts.User, where: u.email == ^email)

if existing_user do
  IO.puts("Test user #{email} already exists")
else
  {:ok, user} = Accounts.register_user(%{email: email})
  {:ok, user, _expired_tokens} = Accounts.update_user_password(user, %{password: password})
  IO.puts("Created test user: #{email} with password: #{password}")
end
