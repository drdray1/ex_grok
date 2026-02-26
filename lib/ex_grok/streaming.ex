defmodule ExGrok.Streaming do
  @moduledoc """
  SSE (Server-Sent Events) parsing utilities for streaming chat completions.

  Parses the raw SSE text format used by the Grok API into decoded JSON maps.

  ## SSE Format

  The Grok API streams responses as SSE events:

      data: {"id":"chatcmpl-...","choices":[{"delta":{"content":"Hello"}}]}

      data: {"id":"chatcmpl-...","choices":[{"delta":{"content":" world"}}]}

      data: [DONE]

  Each event is separated by a blank line (`\\n\\n`).
  """

  @doc """
  Parses SSE text data into a list of decoded JSON maps.

  Handles multiple events in a single chunk, skips non-data lines,
  and filters out the `[DONE]` sentinel.

  ## Examples

      iex> parse_sse("data: {\\"id\\":\\"123\\"}\\n\\ndata: [DONE]\\n\\n")
      [%{"id" => "123"}]
  """
  @spec parse_sse(binary()) :: list(map())
  def parse_sse(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.replace_prefix(&1, "data: ", ""))
    |> Enum.reject(&(&1 == "[DONE]"))
    |> Enum.flat_map(fn json_str ->
      case Jason.decode(json_str) do
        {:ok, decoded} -> [decoded]
        {:error, _} -> []
      end
    end)
  end

  @doc """
  Returns true if the SSE data contains the `[DONE]` sentinel.

  ## Examples

      iex> done?("data: [DONE]\\n\\n")
      true

      iex> done?("data: {\\"id\\":\\"123\\"}\\n\\n")
      false
  """
  @spec done?(binary()) :: boolean()
  def done?(data) when is_binary(data) do
    String.contains?(data, "data: [DONE]")
  end

  @doc """
  Extracts delta content from a streaming chunk.

  ## Examples

      iex> extract_delta_content(%{"choices" => [%{"delta" => %{"content" => "Hi"}}]})
      "Hi"

      iex> extract_delta_content(%{"choices" => [%{"delta" => %{}}]})
      nil
  """
  @spec extract_delta_content(map()) :: String.t() | nil
  def extract_delta_content(%{"choices" => [%{"delta" => %{"content" => content}} | _]}),
    do: content

  def extract_delta_content(_), do: nil

  @doc """
  Extracts the finish reason from a streaming chunk.

  ## Examples

      iex> extract_finish_reason(%{"choices" => [%{"finish_reason" => "stop"}]})
      "stop"
  """
  @spec extract_finish_reason(map()) :: String.t() | nil
  def extract_finish_reason(%{"choices" => [%{"finish_reason" => reason} | _]}), do: reason
  def extract_finish_reason(_), do: nil
end
