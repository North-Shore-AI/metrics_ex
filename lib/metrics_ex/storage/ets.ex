defmodule MetricsEx.Storage.ETS do
  @moduledoc """
  ETS-based storage backend for metrics.

  Provides fast in-memory storage with configurable retention.
  Stores metrics in duplicate_bag to allow multiple values per metric name/tag combination.
  """

  use GenServer
  require Logger

  alias MetricsEx.Metric

  @table_name :metrics_ex_storage
  @retention_check_interval :timer.minutes(5)
  @default_retention_hours 24

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a metric in ETS.
  """
  def store(%Metric{} = metric) do
    GenServer.call(__MODULE__, {:store, metric})
  end

  @doc """
  Retrieves metrics matching the given criteria.

  ## Options
    - `:name` - Filter by metric name (atom)
    - `:type` - Filter by metric type (:counter, :gauge, :histogram)
    - `:tags` - Filter by tags (exact match on provided tags)
    - `:since` - Only return metrics after this DateTime
    - `:until` - Only return metrics before this DateTime
    - `:limit` - Maximum number of results to return
  """
  def query(opts \\ []) do
    GenServer.call(__MODULE__, {:query, opts})
  end

  @doc """
  Returns all metrics in the table (useful for debugging).
  """
  def all do
    :ets.tab2list(@table_name)
  end

  @doc """
  Clears all metrics from storage.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Returns statistics about the storage.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    retention_hours = Keyword.get(opts, :retention_hours, @default_retention_hours)

    table =
      :ets.new(@table_name, [
        :duplicate_bag,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Schedule retention cleanup
    schedule_retention_check()

    state = %{
      table: table,
      retention_hours: retention_hours,
      metrics_stored: 0,
      metrics_pruned: 0
    }

    Logger.info("MetricsEx.Storage.ETS started with #{retention_hours}h retention")
    {:ok, state}
  end

  @impl true
  def handle_call({:store, metric}, _from, state) do
    key = metric_key(metric)
    :ets.insert(@table_name, {key, metric})

    new_state = %{state | metrics_stored: state.metrics_stored + 1}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:query, opts}, _from, state) do
    results = do_query(opts)
    {:reply, results, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    new_state = %{state | metrics_stored: 0, metrics_pruned: 0}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      total_metrics: :ets.info(@table_name, :size),
      metrics_stored: state.metrics_stored,
      metrics_pruned: state.metrics_pruned,
      retention_hours: state.retention_hours,
      memory_bytes: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:retention_check, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.retention_hours * 3600, :second)
    pruned = prune_old_metrics(cutoff)

    schedule_retention_check()

    new_state = %{state | metrics_pruned: state.metrics_pruned + pruned}
    {:noreply, new_state}
  end

  # Private functions

  defp metric_key(%Metric{name: name, tags: tags}) do
    # Create a composite key from name and sorted tags
    tag_key = tags |> Enum.sort() |> :erlang.phash2()
    {name, tag_key}
  end

  defp do_query(opts) do
    name_filter = Keyword.get(opts, :name)
    type_filter = Keyword.get(opts, :type)
    tags_filter = Keyword.get(opts, :tags, %{})
    since = Keyword.get(opts, :since)
    until_time = Keyword.get(opts, :until)
    limit = Keyword.get(opts, :limit)

    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_key, metric} -> metric end)
    |> filter_by_name(name_filter)
    |> filter_by_type(type_filter)
    |> filter_by_tags(tags_filter)
    |> filter_by_time_range(since, until_time)
    |> maybe_limit(limit)
  end

  defp filter_by_name(metrics, nil), do: metrics

  defp filter_by_name(metrics, name) do
    Enum.filter(metrics, fn metric -> metric.name == name end)
  end

  defp filter_by_type(metrics, nil), do: metrics

  defp filter_by_type(metrics, type) do
    Enum.filter(metrics, fn metric -> metric.type == type end)
  end

  defp filter_by_tags(metrics, tags) when map_size(tags) == 0, do: metrics

  defp filter_by_tags(metrics, tags) do
    Enum.filter(metrics, fn metric ->
      Enum.all?(tags, fn {key, value} ->
        Map.get(metric.tags, key) == value
      end)
    end)
  end

  defp filter_by_time_range(metrics, nil, nil), do: metrics

  defp filter_by_time_range(metrics, since, until_time) do
    Enum.filter(metrics, fn metric ->
      after_since = is_nil(since) or DateTime.compare(metric.timestamp, since) != :lt
      before_until = is_nil(until_time) or DateTime.compare(metric.timestamp, until_time) != :gt
      after_since and before_until
    end)
  end

  defp maybe_limit(metrics, nil), do: metrics
  defp maybe_limit(metrics, limit), do: Enum.take(metrics, limit)

  defp prune_old_metrics(cutoff) do
    before_count = :ets.info(@table_name, :size)

    @table_name
    |> :ets.tab2list()
    |> Enum.each(fn {key, metric} ->
      if DateTime.compare(metric.timestamp, cutoff) == :lt do
        :ets.delete_object(@table_name, {key, metric})
      end
    end)

    after_count = :ets.info(@table_name, :size)
    pruned = before_count - after_count

    if pruned > 0 do
      Logger.info("Pruned #{pruned} old metrics (cutoff: #{DateTime.to_iso8601(cutoff)})")
    end

    pruned
  end

  defp schedule_retention_check do
    Process.send_after(self(), :retention_check, @retention_check_interval)
  end
end
