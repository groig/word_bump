defmodule WordBump.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WordBumpWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:word_bump, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WordBump.PubSub},
      WordBumpWeb.Presence,
      # Start a worker by calling: WordBump.Worker.start_link(arg)
      # {WordBump.Worker, arg},
      # Start to serve requests, typically the last entry
      WordBumpWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WordBump.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WordBumpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
