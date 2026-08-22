defmodule ExGrok.Options do
  @moduledoc """
  Keyword-option validation shared by `ExGrok.Chat` and `ExGrok.Responses`.

  Both modules filter options through an allowlist. On its own that filter is
  silent: an unrecognised option vanishes inside `Keyword.take/2` and the request
  succeeds having ignored what the caller asked for — quieter, and so worse, than
  the 400 you would get for sending it.

  The two endpoints also spell overlapping concepts differently
  (`max_tokens`/`max_output_tokens`, `response_format`/`text`,
  `messages`/`input`), so the commonest mistake is reaching for the *other*
  endpoint's name. Each module passes its own cross-endpoint map here, and the
  error names the local equivalent.

  Lives in one module so the two sides cannot drift — which they did: 0.6.0
  documented this validation for both and shipped it only on `Responses`.
  """

  @doc """
  Raises `ArgumentError` on any option outside `allowed`.

  `cross` maps an option belonging to the *other* endpoint to its local
  equivalent, or to `nil` when there is none. `hints` maps an option to extra
  guidance appended to the message.
  """
  @spec validate!(keyword(), [atom()], map(), String.t(), map()) :: :ok
  def validate!(opts, allowed, cross, endpoint, hints \\ %{}) do
    Enum.each(opts, fn {key, _value} ->
      unless key in allowed do
        raise ArgumentError, message(key, allowed, cross, endpoint, hints)
      end
    end)

    :ok
  end

  @doc """
  Raises for options the API advertises but refuses, with per-option guidance.

  Separate from `validate!/5` because "this option is dead" needs a different
  answer than "this option belongs to the other endpoint" — the generic message
  would imply a different spelling exists.
  """
  @spec reject!(keyword(), map()) :: :ok
  def reject!(opts, rejected) do
    Enum.each(opts, fn {key, _value} ->
      case Map.fetch(rejected, key) do
        {:ok, reason} -> raise ArgumentError, "#{inspect(key)} is not usable: " <> reason
        :error -> :ok
      end
    end)

    :ok
  end

  @doc """
  Splits `:extra_params` off the option list.

  The escape hatch that keeps a strict allowlist from becoming a dead end the
  day xAI ships a parameter this client does not know about.
  """
  @spec pop_extra(keyword()) :: {map(), keyword()}
  def pop_extra(opts) do
    {extra, rest} = Keyword.pop(opts, :extra_params, %{})
    {extra, rest}
  end

  defp message(key, allowed, cross, endpoint, hints) do
    base = "unknown option #{inspect(key)} for #{endpoint}"

    case Map.fetch(cross, key) do
      {:ok, nil} ->
        base <> ". It belongs to the other endpoint and has no equivalent here."

      {:ok, replacement} ->
        base <>
          ". It belongs to the other endpoint; here use #{inspect(replacement)}." <>
          Map.get(hints, key, "")

      :error ->
        base <>
          ". Allowed: #{Enum.map_join(Enum.sort(allowed), ", ", &inspect/1)}. " <>
          "Pass unrecognised API parameters through :extra_params."
    end
  end

  @doc """
  The guidance shown when structured output is requested with the wrong key.

  Shared so both modules describe the difference identically.
  """
  @spec structured_output_hint() :: String.t()
  def structured_output_hint do
    "\n\nStructured output differs between the two endpoints:\n" <>
      "    text: ExGrok.Responses.json_schema_text(\"name\", schema)" <>
      "          # flat, under text.format\n" <>
      "    response_format: ExGrok.Chat.json_schema_format(\"name\", schema)" <>
      "  # nested, chat only"
  end
end
