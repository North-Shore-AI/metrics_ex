defmodule MetricsEx.Tagging do
  @moduledoc """
  Tag extraction helpers, including standard lineage dimensions.
  """

  @dimension_keys [:work_id, :trace_id, :plan_id, :step_id]
  @tag_keys [
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
  ]

  @standard_keys @dimension_keys ++ @tag_keys

  @spec extract(map() | keyword()) :: map()
  def extract(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@standard_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  def extract(metadata) when is_list(metadata) do
    metadata
    |> Enum.into(%{})
    |> extract()
  end

  def extract(_), do: %{}

  @spec merge_tags(map(), map() | keyword()) :: map()
  def merge_tags(tags, metadata) when is_map(tags) do
    Map.merge(extract(metadata), tags)
  end

  def merge_tags(nil, metadata), do: merge_tags(%{}, metadata)
end
