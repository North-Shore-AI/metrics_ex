defmodule MetricsEx.MetricTest do
  use ExUnit.Case, async: true
  alias MetricsEx.Metric

  describe "counter/4" do
    test "creates a counter metric with default value" do
      metric = Metric.counter(:test_counter)

      assert metric.name == :test_counter
      assert metric.type == :counter
      assert metric.value == 1
      assert metric.tags == %{}
    end

    test "creates a counter metric with custom value and tags" do
      metric = Metric.counter(:test_counter, 5, %{tenant: "cns"})

      assert metric.value == 5
      assert metric.tags == %{tenant: "cns"}
    end
  end

  describe "gauge/4" do
    test "creates a gauge metric" do
      metric = Metric.gauge(:queue_depth, 42, %{queue: "default"})

      assert metric.name == :queue_depth
      assert metric.type == :gauge
      assert metric.value == 42
      assert metric.tags == %{queue: "default"}
    end
  end

  describe "histogram/4" do
    test "creates a histogram metric" do
      metric = Metric.histogram(:response_time, 123.45, %{endpoint: "/api"})

      assert metric.name == :response_time
      assert metric.type == :histogram
      assert metric.value == 123.45
      assert metric.tags == %{endpoint: "/api"}
    end
  end

  describe "to_map/1" do
    test "converts metric to map format" do
      metric = Metric.counter(:test, 1, %{tag: "value"})
      map = Metric.to_map(metric)

      assert map.name == :test
      assert map.type == :counter
      assert map.value == 1
      assert map.tags == %{tag: "value"}
      assert is_binary(map.timestamp)
    end
  end

  describe "from_telemetry/3" do
    test "propagates standard dimensions into tags" do
      metric =
        Metric.from_telemetry(
          [:work, :job, :completed],
          %{count: 1},
          %{
            work_id: "work-123",
            trace_id: "trace-456",
            plan_id: "plan-789",
            step_id: "step-abc",
            tenant: "cns"
          }
        )

      assert metric.tags.work_id == "work-123"
      assert metric.tags.trace_id == "trace-456"
      assert metric.tags.plan_id == "plan-789"
      assert metric.tags.step_id == "step-abc"
      assert metric.tags.tenant == "cns"
    end
  end
end
