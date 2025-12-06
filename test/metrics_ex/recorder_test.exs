defmodule MetricsEx.RecorderTest do
  use ExUnit.Case, async: false
  alias MetricsEx.{Recorder, Storage.ETS}

  setup do
    ETS.clear()
    :ok
  end

  describe "increment/3" do
    test "increments a counter by 1" do
      Recorder.increment(:test_counter)
      # Give async cast time to process
      Process.sleep(50)

      results = ETS.query(name: :test_counter)
      refute Enum.empty?(results)
      assert hd(results).value == 1
    end

    test "increments a counter by custom amount" do
      Recorder.increment(:test_counter, 5)
      Process.sleep(50)

      results = ETS.query(name: :test_counter)
      assert hd(results).value == 5
    end

    test "increments with tags" do
      Recorder.increment(:test_counter, tags: %{tenant: "cns"})
      Process.sleep(50)

      results = ETS.query(name: :test_counter, tags: %{tenant: "cns"})
      assert length(results) == 1
    end
  end

  describe "gauge/3" do
    test "records a gauge value" do
      Recorder.gauge(:queue_depth, 42)
      Process.sleep(50)

      results = ETS.query(name: :queue_depth)
      assert hd(results).value == 42
      assert hd(results).type == :gauge
    end
  end

  describe "histogram/3" do
    test "records a histogram value" do
      Recorder.histogram(:response_time, 123.45)
      Process.sleep(50)

      results = ETS.query(name: :response_time)
      assert hd(results).value == 123.45
      assert hd(results).type == :histogram
    end
  end

  describe "measure/3" do
    test "measures execution time" do
      result =
        Recorder.measure(:test_operation, fn ->
          Process.sleep(10)
          :ok
        end)

      assert result == :ok
      Process.sleep(50)

      results = ETS.query(name: :test_operation)
      refute Enum.empty?(results)
      # Duration should be at least 10ms
      assert hd(results).value >= 10
    end
  end

  describe "record/2" do
    test "records a generic metric" do
      Recorder.record(:experiment_result, %{
        value: 0.75,
        tags: %{model: "llama-3.1"},
        experiment_id: "exp_123"
      })

      Process.sleep(50)

      results = ETS.query(name: :experiment_result)
      assert hd(results).value == 0.75
      assert hd(results).tags.model == "llama-3.1"
      assert hd(results).metadata.experiment_id == "exp_123"
    end
  end
end
