defmodule Sak.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SakWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:sak, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Sak.PubSub}
      ] ++ gateway_children() ++ [SakWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Sak.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SakWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp gateway_children do
    case Application.get_env(:sak, :gateway) do
      nil -> []
      opts -> [{Sak.Gateway, opts}]
    end
  end
end
