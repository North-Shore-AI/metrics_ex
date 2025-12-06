defmodule MetricsEx.Alerting do
  @moduledoc """
  Threshold-based alerting and anomaly detection for metrics.

  Provides:
  - Threshold-based alerts (>, <, ==, >=, <=)
  - Statistical anomaly detection (Z-score, IQR)
  - Alert routing (webhook, email stub)
  - Alert silencing and acknowledgment
  """

  use GenServer
  require Logger

  alias MetricsEx.Storage.ETS

  @type alert_id :: String.t()
  @type alert_status :: :active | :acknowledged | :resolved | :silenced

  @type alert :: %{
          id: alert_id(),
          rule_name: String.t(),
          metric_name: atom(),
          message: String.t(),
          severity: :critical | :warning | :info,
          status: alert_status(),
          triggered_at: DateTime.t(),
          value: number(),
          threshold: number() | nil,
          tags: map()
        }

  # Client API

  @doc """
  Starts the alerting GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Defines a threshold-based alert rule.

  ## Examples

      iex> MetricsEx.Alerting.define_rule(:high_queue_depth, %{
      ...>   metric: :queue_depth,
      ...>   condition: :greater_than,
      ...>   threshold: 100,
      ...>   severity: :warning,
      ...>   message: "Queue depth exceeded 100"
      ...> })
      :ok
  """
  @spec define_rule(atom(), map()) :: :ok
  def define_rule(rule_name, rule_config) do
    GenServer.call(__MODULE__, {:define_rule, rule_name, rule_config})
  end

  @doc """
  Removes an alert rule.
  """
  @spec remove_rule(atom()) :: :ok
  def remove_rule(rule_name) do
    GenServer.call(__MODULE__, {:remove_rule, rule_name})
  end

  @doc """
  Checks all rules against current metrics and triggers alerts.

  This should be called periodically (e.g., every minute).
  """
  @spec check_rules() :: list(alert())
  def check_rules do
    GenServer.call(__MODULE__, :check_rules)
  end

  @doc """
  Gets all active alerts.
  """
  @spec get_alerts(keyword()) :: list(alert())
  def get_alerts(opts \\ []) do
    GenServer.call(__MODULE__, {:get_alerts, opts})
  end

  @doc """
  Acknowledges an alert.
  """
  @spec acknowledge(alert_id()) :: :ok | {:error, :not_found}
  def acknowledge(alert_id) do
    GenServer.call(__MODULE__, {:acknowledge, alert_id})
  end

  @doc """
  Silences an alert for a specified duration.

  ## Examples

      iex> MetricsEx.Alerting.silence("alert_123", duration_minutes: 60)
      :ok
  """
  @spec silence(alert_id(), keyword()) :: :ok | {:error, :not_found}
  def silence(alert_id, opts \\ []) do
    duration_minutes = Keyword.get(opts, :duration_minutes, 60)
    GenServer.call(__MODULE__, {:silence, alert_id, duration_minutes})
  end

  @doc """
  Detects anomalies using Z-score method.

  Values beyond `threshold` standard deviations from mean are flagged.

  ## Examples

      iex> MetricsEx.Alerting.detect_anomalies(:response_time,
      ...>   method: :zscore,
      ...>   threshold: 3.0,
      ...>   window: :last_hour
      ...> )
      [%{...}, ...]
  """
  @spec detect_anomalies(atom(), keyword()) :: list(map())
  def detect_anomalies(metric_name, opts \\ []) do
    method = Keyword.get(opts, :method, :zscore)
    threshold = Keyword.get(opts, :threshold, 3.0)

    metrics = ETS.query(name: metric_name)

    case method do
      :zscore -> detect_zscore_anomalies(metrics, threshold)
      :iqr -> detect_iqr_anomalies(metrics)
      _ -> []
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      rules: %{},
      alerts: %{},
      alert_history: []
    }

    # Schedule periodic rule checking
    schedule_check()

    Logger.info("MetricsEx.Alerting started")
    {:ok, state}
  end

  @impl true
  def handle_call({:define_rule, rule_name, rule_config}, _from, state) do
    new_state = put_in(state.rules[rule_name], rule_config)
    Logger.info("Alert rule defined: #{rule_name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:remove_rule, rule_name}, _from, state) do
    new_state = update_in(state.rules, &Map.delete(&1, rule_name))
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:check_rules, _from, state) do
    {new_alerts, new_state} = check_all_rules(state)
    {:reply, new_alerts, new_state}
  end

  @impl true
  def handle_call({:get_alerts, opts}, _from, state) do
    status_filter = Keyword.get(opts, :status)

    filtered_alerts =
      state.alerts
      |> Map.values()
      |> filter_by_status(status_filter)

    {:reply, filtered_alerts, state}
  end

  @impl true
  def handle_call({:acknowledge, alert_id}, _from, state) do
    case Map.get(state.alerts, alert_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      alert ->
        updated_alert = %{alert | status: :acknowledged}
        new_state = put_in(state.alerts[alert_id], updated_alert)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:silence, alert_id, duration_minutes}, _from, state) do
    case Map.get(state.alerts, alert_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      alert ->
        silenced_until = DateTime.add(DateTime.utc_now(), duration_minutes * 60, :second)
        updated_alert = %{alert | status: :silenced, silenced_until: silenced_until}
        new_state = put_in(state.alerts[alert_id], updated_alert)
        Logger.info("Alert #{alert_id} silenced until #{DateTime.to_iso8601(silenced_until)}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info(:check_rules, state) do
    {_new_alerts, new_state} = check_all_rules(state)
    schedule_check()
    {:noreply, new_state}
  end

  # Private functions

  defp check_all_rules(state) do
    {new_alerts, updated_alerts} =
      Enum.reduce(state.rules, {[], state.alerts}, fn {rule_name, rule_config},
                                                      {alerts_acc, alerts_map} ->
        case check_rule(rule_name, rule_config) do
          {:triggered, alert} ->
            alert_id = alert.id
            alerts_map_updated = Map.put(alerts_map, alert_id, alert)
            {[alert | alerts_acc], alerts_map_updated}

          :ok ->
            {alerts_acc, alerts_map}
        end
      end)

    new_state = %{state | alerts: updated_alerts}

    # Route alerts if any were triggered
    if not Enum.empty?(new_alerts) do
      route_alerts(new_alerts)
    end

    {new_alerts, new_state}
  end

  defp check_rule(rule_name, rule_config) do
    metric_name = rule_config.metric
    condition = rule_config.condition
    threshold = rule_config.threshold
    severity = Map.get(rule_config, :severity, :warning)
    message = Map.get(rule_config, :message, "Alert: #{rule_name}")

    metrics = ETS.query(name: metric_name)

    if Enum.empty?(metrics) do
      :ok
    else
      latest_metric = Enum.max_by(metrics, & &1.timestamp, DateTime)

      if evaluate_condition(latest_metric.value, condition, threshold) do
        alert = %{
          id: generate_alert_id(rule_name),
          rule_name: to_string(rule_name),
          metric_name: metric_name,
          message: message,
          severity: severity,
          status: :active,
          triggered_at: DateTime.utc_now(),
          value: latest_metric.value,
          threshold: threshold,
          tags: latest_metric.tags
        }

        {:triggered, alert}
      else
        :ok
      end
    end
  end

  defp evaluate_condition(value, :greater_than, threshold), do: value > threshold
  defp evaluate_condition(value, :less_than, threshold), do: value < threshold
  defp evaluate_condition(value, :equal_to, threshold), do: value == threshold
  defp evaluate_condition(value, :greater_than_or_equal, threshold), do: value >= threshold
  defp evaluate_condition(value, :less_than_or_equal, threshold), do: value <= threshold
  defp evaluate_condition(_value, _condition, _threshold), do: false

  defp detect_zscore_anomalies(metrics, threshold) do
    if Enum.empty?(metrics) or length(metrics) < 3 do
      []
    else
      values = Enum.map(metrics, & &1.value)
      mean = Enum.sum(values) / length(values)

      std_dev =
        :math.sqrt(
          Enum.reduce(values, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / length(values)
        )

      detect_with_zscore(metrics, mean, std_dev, threshold)
    end
  end

  defp detect_with_zscore(metrics, mean, std_dev, threshold) do
    # Guard against division by zero
    if std_dev == 0 or std_dev == 0.0 do
      []
    else
      do_detect_zscore(metrics, mean, std_dev, threshold)
    end
  end

  defp do_detect_zscore(metrics, mean, std_dev, threshold) do
    metrics
    |> Enum.filter(fn metric ->
      z_score = abs((metric.value - mean) / std_dev)
      z_score > threshold
    end)
    |> Enum.map(fn metric ->
      %{
        metric: metric,
        z_score: abs((metric.value - mean) / std_dev),
        mean: mean,
        std_dev: std_dev
      }
    end)
  end

  defp detect_iqr_anomalies(metrics) do
    if Enum.empty?(metrics) or length(metrics) < 4 do
      []
    else
      values = metrics |> Enum.map(& &1.value) |> Enum.sort()
      n = length(values)

      q1_index = div(n, 4)
      q3_index = div(3 * n, 4)

      q1 = Enum.at(values, q1_index)
      q3 = Enum.at(values, q3_index)
      iqr = q3 - q1

      lower_bound = q1 - 1.5 * iqr
      upper_bound = q3 + 1.5 * iqr

      metrics
      |> Enum.filter(fn metric ->
        metric.value < lower_bound or metric.value > upper_bound
      end)
      |> Enum.map(fn metric ->
        %{
          metric: metric,
          q1: q1,
          q3: q3,
          iqr: iqr,
          lower_bound: lower_bound,
          upper_bound: upper_bound
        }
      end)
    end
  end

  defp generate_alert_id(rule_name) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    "alert_#{rule_name}_#{timestamp}"
  end

  defp filter_by_status(alerts, nil), do: alerts

  defp filter_by_status(alerts, status) do
    Enum.filter(alerts, fn alert -> alert.status == status end)
  end

  defp route_alerts(alerts) do
    # Log alerts
    Enum.each(alerts, fn alert ->
      Logger.warning(
        "ALERT [#{alert.severity}] #{alert.message} (value: #{alert.value}, threshold: #{alert.threshold})"
      )
    end)

    # TODO: Add webhook routing
    # TODO: Add email routing
    :ok
  end

  defp schedule_check do
    # Check rules every minute
    Process.send_after(self(), :check_rules, :timer.minutes(1))
  end
end
