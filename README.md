# FinancialAdvisorAi

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

## Starting the Postgres Database with Docker Compose

This project includes a Docker Compose file to run a local Postgres database for development.

1. Make sure you have [Docker](https://docs.docker.com/get-docker/) installed and running.
2. Start the Postgres service by running the following command from the project root:

   ```bash
   docker compose -f docker/docker-compse-dev.yml up -d
   ```

   This will start a Postgres 17.5 instance with the database `financial_advisor_ai`.

3. To stop the database, run:

   ```bash
   docker compose -f docker/docker-compse-dev.yml down
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Generate self signed certifiacates for localhost https

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout priv/cert/selfsigned_key.pem \
  -out priv/cert/selfsigned.pem \
  -days 365 \
  -subj "/CN=localhost" \
  -extensions san \
  -config <(cat /etc/ssl/openssl.cnf <(printf "\n[san]\nsubjectAltName=DNS:localhost,IP:127.0.0.1"))


```
