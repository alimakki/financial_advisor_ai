# FinancialAdvisorAi

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

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
