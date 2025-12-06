defmodule MetricsEx.Exporters.InfluxDB do
  @moduledoc """
  Exports metrics in InfluxDB line protocol format.

  Provides compatibility with InfluxDB time-series database for
  long-term storage and analysis.

  See: https://docs.influxdata.com/influxdb/latest/reference/syntax/line-protocol/
  """

  alias MetricsEx.Metric
  alias MetricsEx.Storage.ETS

  @doc """
  Exports all metrics in InfluxDB line protocol format.

  ## Examples

      iex> MetricsEx.Exporters.InfluxDB.export()
      \"\"\"
      jobs_completed,tenant=cns value=1234i 1638835200000000000
      jobs_completed,tenant=crucible value=567i 1638835200000000000
      queue_depth,queue=sno_validation value=42i 1638835200000000000
      \"\"\"

  ## Options

    * `:measurement` - Override the measurement name (default: metric name)
    * `:precision` - Timestamp precision (:nanosecond, :microsecond, :millisecond, :second). Default: :nanosecond
  """
  @spec export() :: String.t()
  def export do
    export_with_opts([])
  end

  @doc """
  Exports all metrics in InfluxDB line protocol format with options.
  """
  @spec export_with_opts(keyword()) :: String.t()
  def export_with_opts(opts) do
    precision = Keyword.get(opts, :precision, :nanosecond)

    ETS.all()
    |> Enum.map(fn {_key, metric} -> metric end)
    |> Enum.map_join("\n", &format_line(&1, precision))
  end

  @doc """
  Exports metrics for a specific metric name in InfluxDB line protocol format.
  """
  @spec export_metric(atom(), keyword()) :: String.t()
  def export_metric(metric_name, opts \\ []) do
    precision = Keyword.get(opts, :precision, :nanosecond)

    ETS.query(name: metric_name)
    |> Enum.map_join("\n", &format_line(&1, precision))
  end

  @doc """
  Converts a metric to InfluxDB line protocol format.

  Format: <measurement>[,<tag_key>=<tag_value>...] <field_key>=<field_value>[,<field_key>=<field_value>...] [<timestamp>]
  """
  @spec format_line(Metric.t(), atom()) :: String.t()
  def format_line(%Metric{} = metric, precision \\ :nanosecond) do
    measurement = escape_measurement(metric.name)
    tags = format_tags(metric.tags)
    fields = format_fields(metric)
    timestamp = format_timestamp(metric.timestamp, precision)

    if tags == "" do
      "#{measurement} #{fields} #{timestamp}"
    else
      "#{measurement},#{tags} #{fields} #{timestamp}"
    end
  end

  # Private functions

  defp format_tags(tags) when map_size(tags) == 0, do: ""

  defp format_tags(tags) do
    tags
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(",", fn {key, value} ->
      "#{escape_tag_key(key)}=#{escape_tag_value(value)}"
    end)
  end

  defp format_fields(%Metric{type: type, value: value}) do
    # For counters and gauges, use integer values if they are integers
    formatted_value =
      cond do
        is_integer(value) and type in [:counter, :gauge] ->
          "#{value}i"

        is_float(value) ->
          Float.to_string(value)

        is_integer(value) ->
          Integer.to_string(value)

        true ->
          to_string(value)
      end

    "value=#{formatted_value}"
  end

  defp format_timestamp(datetime, :nanosecond) do
    DateTime.to_unix(datetime, :nanosecond)
  end

  defp format_timestamp(datetime, :microsecond) do
    DateTime.to_unix(datetime, :microsecond)
  end

  defp format_timestamp(datetime, :millisecond) do
    DateTime.to_unix(datetime, :millisecond)
  end

  defp format_timestamp(datetime, :second) do
    DateTime.to_unix(datetime, :second)
  end

  defp escape_measurement(name) when is_atom(name) do
    name |> Atom.to_string() |> escape_measurement()
  end

  defp escape_measurement(name) when is_binary(name) do
    name
    |> String.replace(",", "\\,")
    |> String.replace(" ", "\\ ")
  end

  defp escape_tag_key(key) when is_atom(key) do
    key |> Atom.to_string() |> escape_tag_key()
  end

  defp escape_tag_key(key) when is_binary(key) do
    key
    |> String.replace(",", "\\,")
    |> String.replace("=", "\\=")
    |> String.replace(" ", "\\ ")
  end

  defp escape_tag_value(value) when is_atom(value) do
    value |> Atom.to_string() |> escape_tag_value()
  end

  defp escape_tag_value(value) when is_binary(value) do
    value
    |> String.replace(",", "\\,")
    |> String.replace("=", "\\=")
    |> String.replace(" ", "\\ ")
  end

  defp escape_tag_value(value), do: to_string(value)
end
