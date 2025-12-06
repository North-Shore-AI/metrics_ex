defmodule MetricsEx.TelemetryHandler do
  @moduledoc """
  Handles telemetry events and converts them to MetricsEx metrics.

  Automatically attaches to configured telemetry events and records them
  as appropriate metric types.
  """

  require Logger

  alias MetricsEx.{Metric, Recorder}

  @doc """
  Attaches MetricsEx to a list of telemetry events.

  ## Examples

      # Attach to work job events
      iex> MetricsEx.TelemetryHandler.attach_telemetry([
      ...>   {[:work, :job, :completed], :counter},
      ...>   {[:work, :job, :duration], :histogram},
      ...>   {[:crucible, :experiment, :completed], :histogram}
      ...> ])
      :ok

      # Attach with custom handler ID
      iex> MetricsEx.TelemetryHandler.attach_telemetry(
      ...>   [{[:my_app, :request], :counter}],
      ...>   handler_id: :my_app_metrics
      ...> )
      :ok
  """
  def attach_telemetry(event_configs, opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, :metrics_ex_telemetry_handler)

    events = Enum.map(event_configs, fn {event_name, _type} -> event_name end)

    # Store event type mapping in process dictionary for the handler
    type_mapping = Enum.into(event_configs, %{})

    :telemetry.attach_many(
      handler_id,
      events,
      &handle_telemetry_event/4,
      %{type_mapping: type_mapping}
    )

    Logger.info("Attached MetricsEx to #{length(events)} telemetry events")
    :ok
  end

  @doc """
  Detaches MetricsEx from telemetry events.
  """
  def detach_telemetry(handler_id \\ :metrics_ex_telemetry_handler) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Lists all attached telemetry handlers.
  """
  def list_handlers do
    :telemetry.list_handlers([])
    |> Enum.filter(fn handler ->
      handler.id == :metrics_ex_telemetry_handler or
        String.starts_with?(to_string(handler.id), "metrics_ex_")
    end)
  end

  # Telemetry event handler callback
  def handle_telemetry_event(event_name, measurements, metadata, config) do
    type_mapping = Map.get(config, :type_mapping, %{})
    metric_type = Map.get(type_mapping, event_name, :counter)

    metric = build_metric(event_name, measurements, metadata, metric_type)

    if metric do
      case Recorder.record(metric.name, %{
             value: metric.value,
             tags: metric.tags,
             metadata: metric.metadata
           }) do
        :ok ->
          :ok

        error ->
          Logger.warning("Failed to record telemetry metric: #{inspect(error)}")
      end
    end
  rescue
    error ->
      Logger.error("Error handling telemetry event #{inspect(event_name)}: #{inspect(error)}")
  end

  # Private functions

  defp build_metric(event_name, measurements, metadata, metric_type) do
    name = event_name_to_atom(event_name)
    value = extract_value(measurements, metric_type)
    tags = extract_tags(metadata)

    case value do
      nil ->
        nil

      _ ->
        %Metric{
          name: name,
          type: metric_type,
          value: value,
          tags: tags,
          timestamp: DateTime.utc_now(),
          metadata: metadata
        }
    end
  end

  defp event_name_to_atom(event_name) do
    event_name
    |> Enum.join("_")
    |> String.to_atom()
  end

  defp extract_value(measurements, :counter) do
    # For counters, default to 1 if no count measurement
    measurements[:count] || measurements[:total] || 1
  end

  defp extract_value(measurements, :gauge) do
    # For gauges, look for common gauge measurement names
    measurements[:value] ||
      measurements[:size] ||
      measurements[:depth] ||
      measurements[:active]
  end

  defp extract_value(measurements, :histogram) do
    # For histograms, prioritize duration and latency measurements
    measurements[:duration] ||
      measurements[:latency] ||
      measurements[:time] ||
      measurements[:value]
  end

  defp extract_tags(metadata) when is_map(metadata) do
    # Extract commonly used tag fields
    metadata
    |> Map.take([
      :tenant,
      :model,
      :dataset,
      :experiment_id,
      :queue,
      :endpoint,
      :method,
      :status,
      :job_id,
      :worker_id,
      :stage
    ])
    |> Enum.into(%{})
  end

  defp extract_tags(_), do: %{}
end
