# MetricsEx Alerting Guide

Comprehensive guide to threshold-based alerting and anomaly detection.

## Overview

MetricsEx provides two types of monitoring:

1. **Threshold-based alerts** - Trigger when metrics cross predefined thresholds
2. **Anomaly detection** - Automatically detect statistical outliers

## Getting Started

### Start the Alerting System

The alerting system must be started in your application supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    # ... other children
    MetricsEx.Alerting
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Threshold-Based Alerts

Define rules that trigger when metrics cross thresholds.

### Defining Alert Rules

```elixir
# Define a high queue depth alert
MetricsEx.Alerting.define_rule(:high_queue_depth, %{
  metric: :queue_depth,
  condition: :greater_than,
  threshold: 100,
  severity: :warning,
  message: "Queue depth exceeded 100 items"
})

# Define a low success rate alert
MetricsEx.Alerting.define_rule(:low_success_rate, %{
  metric: :success_rate,
  condition: :less_than,
  threshold: 0.95,
  severity: :critical,
  message: "Success rate dropped below 95%"
})

# Define an exact value alert
MetricsEx.Alerting.define_rule(:service_down, %{
  metric: :service_health,
  condition: :equal_to,
  threshold: 0,
  severity: :critical,
  message: "Service health check failed"
})
```

### Available Conditions

- `:greater_than` - Value > threshold
- `:less_than` - Value < threshold
- `:equal_to` - Value == threshold
- `:greater_than_or_equal` - Value >= threshold
- `:less_than_or_equal` - Value <= threshold

### Severity Levels

- `:critical` - Requires immediate attention
- `:warning` - Should be investigated soon
- `:info` - Informational only

### Checking Rules

Rules are automatically checked every minute, but you can trigger manual checks:

```elixir
# Manually check all rules
triggered_alerts = MetricsEx.Alerting.check_rules()

# triggered_alerts is a list of alert maps
Enum.each(triggered_alerts, fn alert ->
  IO.puts "Alert: #{alert.message}"
  IO.puts "  Value: #{alert.value}"
  IO.puts "  Threshold: #{alert.threshold}"
  IO.puts "  Severity: #{alert.severity}"
end)
```

## Managing Alerts

### Get Active Alerts

```elixir
# Get all alerts
all_alerts = MetricsEx.Alerting.get_alerts()

# Get only active alerts
active = MetricsEx.Alerting.get_alerts(status: :active)

# Get acknowledged alerts
acked = MetricsEx.Alerting.get_alerts(status: :acknowledged)

# Get silenced alerts
silenced = MetricsEx.Alerting.get_alerts(status: :silenced)
```

### Acknowledge Alerts

Mark an alert as acknowledged (someone is working on it):

```elixir
MetricsEx.Alerting.acknowledge("alert_high_queue_depth_1638835200000")
```

### Silence Alerts

Temporarily suppress an alert for a specified duration:

```elixir
# Silence for 1 hour (default: 60 minutes)
MetricsEx.Alerting.silence("alert_123", duration_minutes: 60)

# Silence for 4 hours
MetricsEx.Alerting.silence("alert_123", duration_minutes: 240)
```

### Remove Alert Rules

```elixir
MetricsEx.Alerting.remove_rule(:high_queue_depth)
```

## Anomaly Detection

Automatically detect unusual metric values using statistical methods.

### Z-Score Method

Flags values that are > N standard deviations from the mean.

```elixir
# Detect anomalies using Z-score (default threshold: 3.0)
anomalies = MetricsEx.Alerting.detect_anomalies(:response_time,
  method: :zscore,
  threshold: 3.0
)

# Results include statistical context
Enum.each(anomalies, fn anomaly ->
  metric = anomaly.metric
  IO.puts "Anomaly detected!"
  IO.puts "  Value: #{metric.value}"
  IO.puts "  Z-score: #{anomaly.z_score}"
  IO.puts "  Mean: #{anomaly.mean}"
  IO.puts "  Std Dev: #{anomaly.std_dev}"
end)
```

**When to use**: Best for normally distributed data (response times, latencies).

**Threshold guide**:
- `2.0` - Moderate (catches ~95% of normal data)
- `3.0` - Standard (catches ~99.7% of normal data)
- `4.0` - Conservative (very rare outliers only)

### IQR Method (Interquartile Range)

Flags values outside of Q1 - 1.5×IQR to Q3 + 1.5×IQR range.

```elixir
# Detect anomalies using IQR method
anomalies = MetricsEx.Alerting.detect_anomalies(:request_count,
  method: :iqr
)

# Results include quartile information
Enum.each(anomalies, fn anomaly ->
  metric = anomaly.metric
  IO.puts "Anomaly detected!"
  IO.puts "  Value: #{metric.value}"
  IO.puts "  Q1: #{anomaly.q1}"
  IO.puts "  Q3: #{anomaly.q3}"
  IO.puts "  IQR: #{anomaly.iqr}"
  IO.puts "  Bounds: #{anomaly.lower_bound} - #{anomaly.upper_bound}"
end)
```

**When to use**: Better for skewed distributions or when you have outliers on both ends.

**Advantages**:
- More robust to outliers than Z-score
- Doesn't assume normal distribution
- Follows "box plot" methodology

## Complete Example

```elixir
defmodule MyApp.AlertingSetup do
  def setup do
    # Define threshold alerts
    MetricsEx.Alerting.define_rule(:high_error_rate, %{
      metric: :error_rate,
      condition: :greater_than,
      threshold: 0.05,  # 5% errors
      severity: :critical,
      message: "Error rate exceeded 5%"
    })

    MetricsEx.Alerting.define_rule(:slow_responses, %{
      metric: :p95_response_time,
      condition: :greater_than,
      threshold: 1000,  # 1000ms
      severity: :warning,
      message: "P95 response time over 1 second"
    })

    MetricsEx.Alerting.define_rule(:low_memory, %{
      metric: :available_memory_mb,
      condition: :less_than,
      threshold: 512,
      severity: :warning,
      message: "Available memory below 512MB"
    })
  end

  def check_and_notify do
    # Check all rules
    alerts = MetricsEx.Alerting.check_rules()

    # Send notifications for critical alerts
    alerts
    |> Enum.filter(fn alert -> alert.severity == :critical end)
    |> Enum.each(&send_pagerduty_alert/1)

    # Check for anomalies in response times
    response_anomalies = MetricsEx.Alerting.detect_anomalies(
      :response_time,
      method: :zscore,
      threshold: 3.0
    )

    if length(response_anomalies) > 5 do
      send_slack_notification("Multiple response time anomalies detected")
    end
  end

  defp send_pagerduty_alert(alert) do
    # Your PagerDuty integration
    IO.puts "CRITICAL ALERT: #{alert.message}"
  end

  defp send_slack_notification(message) do
    # Your Slack integration
    IO.puts "SLACK: #{message}"
  end
end
```

## Scheduled Monitoring

Set up a GenServer to check alerts periodically:

```elixir
defmodule MyApp.AlertMonitor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Check every 5 minutes
    schedule_check()
    {:ok, %{}}
  end

  def handle_info(:check, state) do
    # Check threshold rules
    alerts = MetricsEx.Alerting.check_rules()
    handle_alerts(alerts)

    # Check for anomalies
    check_anomalies()

    schedule_check()
    {:noreply, state}
  end

  defp handle_alerts(alerts) do
    Enum.each(alerts, fn alert ->
      case alert.severity do
        :critical -> send_pagerduty(alert)
        :warning -> send_slack(alert)
        :info -> log_alert(alert)
      end
    end)
  end

  defp check_anomalies do
    [:response_time, :error_rate, :cpu_usage]
    |> Enum.each(fn metric ->
      anomalies = MetricsEx.Alerting.detect_anomalies(metric, method: :zscore)

      if length(anomalies) > 0 do
        send_slack("#{length(anomalies)} anomalies detected for #{metric}")
      end
    end)
  end

  defp schedule_check do
    Process.send_after(self(), :check, :timer.minutes(5))
  end

  defp send_pagerduty(alert), do: IO.puts("PAGERDUTY: #{alert.message}")
  defp send_slack(alert), do: IO.puts("SLACK: #{alert.message}")
  defp log_alert(alert), do: IO.puts("INFO: #{alert.message}")
end
```

## Best Practices

### Threshold Selection

1. **Start conservative**: Set initial thresholds based on historical data
2. **Iterate**: Adjust based on false positive/negative rates
3. **Use percentiles**: p95/p99 are better than max for noisy data
4. **Account for business hours**: Different thresholds for peak vs off-peak

### Alert Fatigue Prevention

1. **Silence during maintenance**: Use `silence/2` for planned work
2. **Aggregate similar alerts**: Group related metrics
3. **Escalate gradually**: Info → Warning → Critical
4. **Set meaningful thresholds**: Avoid alerts that don't require action

### Anomaly Detection Tips

1. **Require minimum data**: Don't detect on < 10 samples
2. **Combine methods**: Use both Z-score and IQR
3. **Account for seasonality**: Consider time-of-day patterns
4. **Validate alerts**: Not all anomalies are problems

### Alert Actions

```elixir
# Good: Specific, actionable alerts
"Database connection pool at 95% capacity (48/50 connections)"
"API error rate 12% (expected < 5%) - Check service X"

# Bad: Vague, non-actionable alerts
"Something is wrong"
"High load"
```

## Integration Examples

### PagerDuty

```elixir
defmodule MyApp.PagerDuty do
  def trigger_incident(alert) do
    payload = %{
      routing_key: "YOUR_ROUTING_KEY",
      event_action: "trigger",
      payload: %{
        summary: alert.message,
        severity: severity_to_pd(alert.severity),
        source: "metrics_ex",
        custom_details: %{
          value: alert.value,
          threshold: alert.threshold,
          tags: alert.tags
        }
      }
    }

    HTTPoison.post(
      "https://events.pagerduty.com/v2/enqueue",
      Jason.encode!(payload),
      [{"Content-Type", "application/json"}]
    )
  end

  defp severity_to_pd(:critical), do: "critical"
  defp severity_to_pd(:warning), do: "warning"
  defp severity_to_pd(:info), do: "info"
end
```

### Slack

```elixir
defmodule MyApp.Slack do
  def send_alert(alert) do
    webhook_url = "YOUR_SLACK_WEBHOOK_URL"

    message = %{
      text: "Alert: #{alert.message}",
      attachments: [
        %{
          color: color_for_severity(alert.severity),
          fields: [
            %{title: "Metric", value: alert.metric_name, short: true},
            %{title: "Value", value: alert.value, short: true},
            %{title: "Threshold", value: alert.threshold, short: true},
            %{title: "Severity", value: alert.severity, short: true}
          ]
        }
      ]
    }

    HTTPoison.post(webhook_url, Jason.encode!(message))
  end

  defp color_for_severity(:critical), do: "danger"
  defp color_for_severity(:warning), do: "warning"
  defp color_for_severity(:info), do: "good"
end
```

## Troubleshooting

### Alerts Not Triggering

1. Check rule is defined: `MetricsEx.Alerting.get_alerts()`
2. Verify metrics are being recorded: `MetricsEx.Storage.ETS.query(name: :your_metric)`
3. Check alert checker is running (should run every minute)
4. Verify threshold conditions are correct

### Too Many False Positives

1. Increase threshold values
2. Use higher Z-score threshold (e.g., 4.0 instead of 3.0)
3. Add filters for known noisy periods
4. Use IQR instead of Z-score for skewed data

### Anomaly Detection Not Working

1. Ensure sufficient data (minimum 3 samples for Z-score, 4 for IQR)
2. Check if data has sufficient variance (constant values won't have anomalies)
3. Verify method is appropriate for your data distribution
4. Inspect raw anomaly results to understand what's being flagged
