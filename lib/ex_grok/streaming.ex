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

  > #### Only safe for whole events {: .warning}
  >
  > This arity assumes `data` contains only complete events. An HTTP chunk is
  > not an event boundary, so a streaming caller must use `parse_sse/2`, which
  > carries the partial trailing event over to the next chunk. See its docs.

  ## Examples

      iex> parse_sse("data: {\\"id\\":\\"123\\"}\\n\\ndata: [DONE]\\n\\n")
      [%{"id" => "123"}]
  """
  @spec parse_sse(binary()) :: list(map())
  def parse_sse(data) when is_binary(data) do
    {events, _rest} = parse_sse(data, "")
    events
  end

  @doc """
  Parses one chunk of an SSE stream, given the leftover from the previous chunk.

  Returns `{events, rest}` — decoded events, and the trailing bytes that do not
  yet form a complete event. Feed `rest` back in as `buffer` on the next chunk.

  ## Why this exists

  Transport chunks and SSE events are unrelated boundaries: an event can be
  split across two chunks, and often is. Parsing each chunk on its own means
  such an event decodes as invalid JSON and is dropped, silently — the stream
  simply appears to be missing one event.

  Which event gets lost is not random. Large events are the ones most likely to
  span a chunk boundary, and on the Responses API the largest event by far is
  the terminal `response.completed`, which carries the entire final response
  object. So the failure lands precisely on the event a caller most needs:
  small text deltas stream in fine, and then the result never arrives.

  ## Examples

      iex> {events, rest} = parse_sse(~s(data: {"a": 1}\\n\\ndata: {"b":), "")
      iex> events
      [%{"a" => 1}]
      iex> parse_sse(~s( 2}\\n\\n), rest)
      {[%{"b" => 2}], ""}
  """
  @spec parse_sse(binary(), binary()) :: {list(map()), binary()}
  def parse_sse(data, buffer) when is_binary(data) and is_binary(buffer) do
    # Events are separated by a blank line. Anything after the last separator is
    # incomplete by definition — it is either a partial event or empty — so it
    # goes back into the buffer rather than being parsed and thrown away.
    {frames, [rest]} =
      (buffer <> data)
      |> String.split("\n\n")
      |> Enum.split(-1)

    {Enum.flat_map(frames, &decode_frame/1), rest}
  end

  defp decode_frame(frame) do
    frame
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
