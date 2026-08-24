defmodule ExGrok.Usage do
  @moduledoc """
  Typed accessors for the `usage` map returned by both API surfaces.

  Normalizes naming differences between `/v1/chat/completions`
  (`prompt_tokens`/`completion_tokens`) and `/v1/responses`
  (`input_tokens`/`output_tokens`), and digs into the nested detail maps for
  reasoning/cached tokens and xAI billing fields.

  Every function accepts either the full response body **or** the inner `usage`
  map, so you can call it directly on `{:ok, body}` payloads:

      {:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", input)
      ExGrok.Usage.reasoning_tokens(resp)   # => 594
      ExGrok.Usage.cost_usd(resp)           # => 0.0059864
  """

  @tick_per_usd 10_000_000_000

  @doc "Prompt/input token count, or nil."
  @spec input_tokens(map()) :: non_neg_integer() | nil
  def input_tokens(source), do: usage(source) |> first_int(["input_tokens", "prompt_tokens"])

  @doc "Completion/output token count, or nil."
  @spec output_tokens(map()) :: non_neg_integer() | nil
  def output_tokens(source),
    do: usage(source) |> first_int(["output_tokens", "completion_tokens"])

  @doc "Total token count, or nil."
  @spec total_tokens(map()) :: non_neg_integer() | nil
  def total_tokens(source), do: usage(source) |> first_int(["total_tokens"])

  @doc "Reasoning token count (from `output_tokens_details`), or nil."
  @spec reasoning_tokens(map()) :: non_neg_integer() | nil
  def reasoning_tokens(source) do
    u = usage(source)

    nested_int(u, "output_tokens_details", "reasoning_tokens") ||
      first_int(u, ["reasoning_tokens"])
  end

  @doc "Cached input token count (from `input_tokens_details`), or nil."
  @spec cached_tokens(map()) :: non_neg_integer() | nil
  def cached_tokens(source) do
    u = usage(source)

    nested_int(u, "input_tokens_details", "cached_tokens") ||
      nested_int(u, "prompt_tokens_details", "cached_tokens") || first_int(u, ["cached_tokens"])
  end

  @doc """
  Response cost in US dollars, derived from `cost_in_usd_ticks`
  (1 USD = 10,000,000,000 ticks, per the xAI cost-tracking docs), or nil
  when the field is absent.
  """
  @spec cost_usd(map()) :: float() | nil
  def cost_usd(source) do
    case first_int(usage(source), ["cost_in_usd_ticks"]) do
      nil -> nil
      ticks -> ticks / @tick_per_usd
    end
  end

  @doc "Number of sources used by server-side search tools, or nil."
  @spec sources_used(map()) :: non_neg_integer() | nil
  def sources_used(source), do: usage(source) |> first_int(["num_sources_used"])

  @doc "Number of server-side tool invocations billed, or nil."
  @spec server_tools_used(map()) :: non_neg_integer() | nil
  def server_tools_used(source), do: usage(source) |> first_int(["num_server_side_tools_used"])

  # ---------------------------------------------------------------------------

  # Accept a full response body (with a "usage" key) or the usage map itself.
  defp usage(%{"usage" => usage}) when is_map(usage), do: usage
  defp usage(map) when is_map(map), do: map
  defp usage(_), do: %{}

  defp first_int(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        n when is_integer(n) -> n
        _ -> nil
      end
    end)
  end

  defp nested_int(map, outer, inner) do
    case Map.get(map, outer) do
      %{} = details -> first_int(details, [inner])
      _ -> nil
    end
  end
end
