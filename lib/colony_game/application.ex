defmodule ColonyGame.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ColonyGameWeb.Telemetry,
      ColonyGame.Repo,
      {DNSCluster, query: Application.get_env(:colony_game, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ColonyGame.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ColonyGame.Finch},
      # Start a worker by calling: ColonyGame.Worker.start_link(arg)
      # {ColonyGame.Worker, arg},
      {Registry, keys: :unique, name: ColonyGame.Game.Registry},
      ColonyGame.Game.PlayerSupervisor,
      ColonyGame.Game.TickServer,
      ColonyGame.Game.ForagingServer,
      # Start to serve requests, typically the last entry
      ColonyGameWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ColonyGame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ColonyGameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
