defmodule MetricsExTest do
  use ExUnit.Case, async: false
  alias MetricsEx.Storage.ETS

  setup do
    ETS.clear()
    :ok
  end

  describe "MetricsEx main API" do
    test "record/2 stores metrics" do
      MetricsEx.record(:test_metric, %{value: 42})
      Process.sleep(50)

      results = ETS.query(name: :test_metric)
      refute Enum.empty?(results)
    end

    test "increment/1 increments counters" do
      MetricsEx.increment(:test_counter)
      Process.sleep(50)

      results = ETS.query(name: :test_counter)
      refute Enum.empty?(results)
    end

    test "gauge/2 records gauge values" do
      MetricsEx.gauge(:test_gauge, 100)
      Process.sleep(50)

      results = ETS.query(name: :test_gauge)
      assert hd(results).value == 100
    end

    test "histogram/2 records histogram values" do
      MetricsEx.histogram(:test_histogram, 123.45)
      Process.sleep(50)

      results = ETS.query(name: :test_histogram)
      assert hd(results).value == 123.45
    end

    test "query/2 aggregates metrics" do
      MetricsEx.increment(:test_query, 10)
      MetricsEx.increment(:test_query, 20)
      Process.sleep(50)

      result = MetricsEx.query(:test_query, aggregation: :sum)
      assert result == 30
    end
  end
end
