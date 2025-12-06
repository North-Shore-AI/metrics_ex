defmodule MetricsEx.Exporters.Datadog do
  @moduledoc """
  Exports metrics to Datadog format (DogStatsD protocol).

  Provides compatibility with Datadog monitoring and observability platform.

  See: https://docs.datadoghq.com/developers/dogstatsd/datagram_shell/
  """

  alias MetricsEx.Metric
  alias MetricsEx.Storage.ETS

  @doc """
  Exports all metrics in DogStatsD datagram format.

  ## Examples

      iex> MetricsEx.Exporters.Datadog.export()
      [
        "jobs_completed:1234|c|#tenant:cns",
        "jobs_completed:567|c|#tenant:crucible",
        "queue_depth:42|g|#queue:sno_validation",
        "response_time:123.45|h|#endpoint:/api"
      ]

  Returns a list of datagram strings suitable for sending to DogStatsD agent.
  """
  @spec export() :: list(String.t())
  def export do
    ETS.all()
    |> Enum.map(fn {_key, metric} -> metric end)
    |> Enum.map(&format_datagram/1)
  end

  @doc """
  Exports metrics for a specific metric name in DogStatsD datagram format.
  """
  @spec export(atom()) :: list(String.t())
  def export(metric_name) do
    ETS.query(name: metric_name)
    |> Enum.map(&format_datagram/1)
  end

  @doc """
  Converts a metric to DogStatsD datagram format.

  Format: <metric_name>:<value>|<type>|@<sample_rate>|#<tag_list>

  ## Metric Types

  - `c` - Counter
  - `g` - Gauge
  - `h` - Histogram
  - `ms` - Timing (milliseconds)
  - `s` - Set
  - `d` - Distribution
  """
  @spec format_datagram(Metric.t()) :: String.t()
  def format_datagram(%Metric{} = metric) do
    name = metric_name_to_datadog(metric.name)
    value = format_value(metric.value)
    type = metric_type_to_datadog(metric.type)
    tags = format_tags(metric.tags)

    if tags == "" do
      "#{name}:#{value}|#{type}"
    else
      "#{name}:#{value}|#{type}|##{tags}"
    end
  end

  @doc """
  Sends metrics to DogStatsD agent via UDP.

  ## Options

    * `:host` - DogStatsD agent hostname (default: "localhost")
    * `:port` - DogStatsD agent port (default: 8125)
    * `:namespace` - Metric namespace prefix (default: "")

  ## Examples

      iex> MetricsEx.Exporters.Datadog.send_to_agent(host: "localhost", port: 8125)
      {:ok, 42}  # 42 metrics sent

  Note: This requires the `:gen_udp` Erlang module (built-in).
  """
  @spec send_to_agent(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def send_to_agent(opts \\ []) do
    host = Keyword.get(opts, :host, ~c"localhost")
    port = Keyword.get(opts, :port, 8125)
    namespace = Keyword.get(opts, :namespace, "")

    datagrams = export()

    case :gen_udp.open(0) do
      {:ok, socket} ->
        results =
          Enum.map(datagrams, fn datagram ->
            payload = add_namespace(datagram, namespace)
            :gen_udp.send(socket, host, port, payload)
          end)

        :gen_udp.close(socket)

        success_count = Enum.count(results, &(&1 == :ok))
        {:ok, success_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp metric_name_to_datadog(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", ".")
  end

  defp metric_type_to_datadog(:counter), do: "c"
  defp metric_type_to_datadog(:gauge), do: "g"
  defp metric_type_to_datadog(:histogram), do: "h"

  defp format_value(value) when is_float(value), do: Float.to_string(value)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value), do: to_string(value)

  defp format_tags(tags) when map_size(tags) == 0, do: ""

  defp format_tags(tags) do
    tags
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(",", fn {key, value} ->
      "#{sanitize_tag_key(key)}:#{sanitize_tag_value(value)}"
    end)
  end

  defp sanitize_tag_key(key) when is_atom(key) do
    key |> Atom.to_string() |> sanitize_tag_key()
  end

  defp sanitize_tag_key(key) when is_binary(key) do
    key
    |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_")
    |> String.downcase()
  end

  defp sanitize_tag_value(value) when is_atom(value) do
    value |> Atom.to_string() |> sanitize_tag_value()
  end

  defp sanitize_tag_value(value) when is_binary(value) do
    String.replace(value, ~r/[^a-zA-Z0-9_\-\.\:]/, "_")
  end

  defp sanitize_tag_value(value), do: to_string(value)

  defp add_namespace("", _namespace), do: ""

  defp add_namespace(datagram, "") do
    datagram
  end

  defp add_namespace(datagram, namespace) do
    String.replace(datagram, ~r/^([^:]+):/, "#{namespace}.\\1:")
  end
end
