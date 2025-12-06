defmodule MetricsEx.Storage.Prometheus do
  @moduledoc """
  Exports metrics in Prometheus text format.

  Provides compatibility with Prometheus scraping and monitoring tools.

  See: https://prometheus.io/docs/instrumenting/exposition_formats/
  """

  alias MetricsEx.Storage.ETS

  @doc """
  Exports all metrics in Prometheus text format.

  ## Examples

      iex> MetricsEx.Storage.Prometheus.export()
      \"\"\"
      # HELP jobs_completed Total number of completed jobs
      # TYPE jobs_completed counter
      jobs_completed{tenant="cns"} 1234 1638835200000
      jobs_completed{tenant="crucible"} 567 1638835200000

      # HELP queue_depth Current depth of processing queue
      # TYPE queue_depth gauge
      queue_depth{queue="sno_validation"} 42 1638835200000
      \"\"\"
  """
  @spec export() :: String.t()
  def export do
    metrics = ETS.all()

    metrics
    |> group_by_name()
    |> Enum.map_join("\n\n", &format_metric_family/1)
  end

  @doc """
  Exports metrics for a specific metric name.
  """
  @spec export(atom()) :: String.t()
  def export(metric_name) do
    metrics = ETS.query(name: metric_name)

    case metrics do
      [] ->
        ""

      _ ->
        group_by_name([{nil, hd(metrics)} | Enum.map(tl(metrics), &{nil, &1})])
        |> Enum.map_join("\n\n", &format_metric_family/1)
    end
  end

  @doc """
  Returns Prometheus-compatible content type.
  """
  @spec content_type() :: String.t()
  def content_type do
    "text/plain; version=0.0.4; charset=utf-8"
  end

  # Private functions

  defp group_by_name(metrics) do
    metrics
    |> Enum.map(fn {_key, metric} -> metric end)
    |> Enum.group_by(& &1.name)
  end

  defp format_metric_family({name, metrics}) do
    # Get metric type from first metric
    metric_type = get_prometheus_type(hd(metrics).type)

    help = generate_help(name)
    type_line = "# TYPE #{name} #{metric_type}"
    metric_lines = Enum.map(metrics, &format_metric_line/1)

    [help, type_line | metric_lines]
    |> Enum.join("\n")
  end

  defp format_metric_line(metric) do
    name = metric.name
    labels = format_labels(metric.tags)
    value = format_value(metric.value, metric.type)
    timestamp = DateTime.to_unix(metric.timestamp, :millisecond)

    if labels == "" do
      "#{name} #{value} #{timestamp}"
    else
      "#{name}{#{labels}} #{value} #{timestamp}"
    end
  end

  defp format_labels(tags) when map_size(tags) == 0, do: ""

  defp format_labels(tags) do
    Enum.map_join(tags, ",", fn {key, value} ->
      ~s(#{key}="#{escape_label_value(value)}")
    end)
  end

  defp format_value(value, _type) when is_number(value) do
    # Prometheus expects floating point for all numeric values
    if is_float(value) do
      Float.to_string(value)
    else
      Integer.to_string(value)
    end
  end

  defp get_prometheus_type(:counter), do: "counter"
  defp get_prometheus_type(:gauge), do: "gauge"
  defp get_prometheus_type(:histogram), do: "histogram"

  defp generate_help(name) do
    # Generate a basic help text from the metric name
    help_text =
      name
      |> Atom.to_string()
      |> String.replace("_", " ")
      |> String.capitalize()

    "# HELP #{name} #{help_text}"
  end

  defp escape_label_value(value) when is_atom(value) do
    value |> Atom.to_string() |> escape_label_value()
  end

  defp escape_label_value(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_label_value(value), do: to_string(value)
end
