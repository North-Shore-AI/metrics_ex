defmodule MetricsEx.Recorder do
  @moduledoc """
  GenServer responsible for recording metrics.

  Provides high-level API for recording different metric types and
  coordinates with storage backend.
  """

  use GenServer
  require Logger

  alias MetricsEx.{Metric, Storage.ETS}

  @pubsub_topic "metrics:recorded"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a generic metric.

  ## Examples

      iex> MetricsEx.Recorder.record(:experiment_result, %{
      ...>   experiment_id: "exp_123",
      ...>   metric: :entailment_score,
      ...>   value: 0.75,
      ...>   tags: %{model: "llama-3.1", dataset: "scifact"}
      ...> })
      :ok
  """
  def record(name, data) when is_map(data) do
    value = Map.get(data, :value, 1)
    tags = Map.get(data, :tags, %{})
    metadata = Map.drop(data, [:value, :tags])
    type = infer_type(name, value)

    metric = create_metric(type, name, value, tags, metadata)
    GenServer.cast(__MODULE__, {:record, metric})
  end

  @doc """
  Increments a counter metric.

  ## Examples

      iex> MetricsEx.Recorder.increment(:jobs_completed, tags: %{tenant: "cns"})
      :ok

      iex> MetricsEx.Recorder.increment(:requests_total, 5)
      :ok
  """
  def increment(name, amount \\ 1, opts \\ [])

  def increment(name, amount, opts) when is_number(amount) do
    tags = Keyword.get(opts, :tags, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    metric = Metric.counter(name, amount, tags, metadata)
    GenServer.cast(__MODULE__, {:record, metric})
  end

  def increment(name, opts, _) when is_list(opts) do
    increment(name, 1, opts)
  end

  @doc """
  Records a gauge metric.

  ## Examples

      iex> MetricsEx.Recorder.gauge(:queue_depth, 42, tags: %{queue: "sno_validation"})
      :ok
  """
  def gauge(name, value, opts \\ []) do
    tags = Keyword.get(opts, :tags, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    metric = Metric.gauge(name, value, tags, metadata)
    GenServer.cast(__MODULE__, {:record, metric})
  end

  @doc """
  Records a histogram metric (typically for distributions like latencies).

  ## Examples

      iex> MetricsEx.Recorder.histogram(:response_time, 123.45, tags: %{endpoint: "/api"})
      :ok
  """
  def histogram(name, value, opts \\ []) do
    tags = Keyword.get(opts, :tags, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    metric = Metric.histogram(name, value, tags, metadata)
    GenServer.cast(__MODULE__, {:record, metric})
  end

  @doc """
  Measures the execution time of a function and records it as a histogram.

  ## Examples

      iex> MetricsEx.Recorder.measure(:database_query, fn ->
      ...>   # expensive operation
      ...>   :timer.sleep(100)
      ...> end, tags: %{query: "SELECT * FROM users"})
      # Returns the function result and records the duration
  """
  def measure(name, fun, opts \\ []) when is_function(fun, 0) do
    {duration, result} = :timer.tc(fun, :microsecond)
    # Convert to milliseconds
    histogram(name, duration / 1000, opts)
    result
  end

  # Server callbacks

  @impl true
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub)

    state = %{
      pubsub: pubsub,
      metrics_recorded: 0
    }

    Logger.info("MetricsEx.Recorder started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record, metric}, state) do
    # Store metric
    ETS.store(metric)

    # Broadcast to pubsub if configured
    if state.pubsub do
      Phoenix.PubSub.broadcast(
        state.pubsub,
        @pubsub_topic,
        {:metric_recorded, Metric.to_map(metric)}
      )
    end

    new_state = %{state | metrics_recorded: state.metrics_recorded + 1}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      metrics_recorded: state.metrics_recorded
    }

    {:reply, stats, state}
  end

  # Private functions

  defp infer_type(_name, value) when is_float(value), do: :histogram

  defp infer_type(name, value) when is_integer(value) do
    # If name suggests it's a gauge (contains "depth", "size", "count"), use gauge
    name_str = Atom.to_string(name)

    if String.contains?(name_str, ["depth", "size", "active", "current"]) do
      :gauge
    else
      :counter
    end
  end

  defp infer_type(_name, _value), do: :counter

  defp create_metric(:counter, name, value, tags, metadata) do
    Metric.counter(name, value, tags, metadata)
  end

  defp create_metric(:gauge, name, value, tags, metadata) do
    Metric.gauge(name, value, tags, metadata)
  end

  defp create_metric(:histogram, name, value, tags, metadata) do
    Metric.histogram(name, value, tags, metadata)
  end
end
