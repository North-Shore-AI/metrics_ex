defmodule MetricsEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration
    retention_hours = Application.get_env(:metrics_ex, :retention_hours, 24)
    pubsub = Application.get_env(:metrics_ex, :pubsub)

    children = [
      # ETS storage backend
      {MetricsEx.Storage.ETS, retention_hours: retention_hours},

      # Metrics recorder
      {MetricsEx.Recorder, pubsub: pubsub}
    ]

    # Optional: Start Phoenix PubSub if configured
    children =
      if pubsub do
        [{Phoenix.PubSub, name: pubsub} | children]
      else
        children
      end

    opts = [strategy: :one_for_one, name: MetricsEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
