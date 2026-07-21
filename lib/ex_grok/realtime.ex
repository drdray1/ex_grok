defmodule ExGrok.Realtime do
  @moduledoc """
  xAI Grok **Voice Agent / realtime** event codec for the WebSocket API
  (`wss://api.x.ai/v1/realtime`).

  Unlike the HTTP modules, the realtime API is a bidirectional, event-based
  WebSocket session: you stream microphone audio up as
  `input_audio_buffer.append` events and receive `response.output_audio.delta`
  events (plus tool calls, transcripts, and lifecycle events) back.

  This module is the **pure codec** — it builds outgoing client-event maps and
  parses incoming server events, with no socket involved (so it is fully
  unit-testable). The live connection lives in `ExGrok.Realtime.Connection`,
  which drives a `Mint.WebSocket` session and uses this codec on the wire.

  ## Example

      alias ExGrok.Realtime
      alias ExGrok.Realtime.Connection

      {:ok, conn} =
        Connection.connect(
          api_key: System.fetch_env!("XAI_API_KEY"),
          on_event: fn event ->
            case Realtime.audio_delta(event) do
              nil -> :ok
              b64 -> play(Base.decode64!(b64))
            end
          end
        )

      Connection.send_event(conn, Realtime.session_update(%{
        "voice" => "eve",
        "instructions" => "You are a helpful assistant.",
        "turn_detection" => %{"type" => "server_vad"}
      }))

      Connection.append_audio(conn, mic_chunk_binary)
      Connection.commit(conn)
      Connection.create_response(conn)
  """

  @doc ~s(A `session.update` client event wrapping the given session config map.)
  @spec session_update(map()) :: map()
  def session_update(config) when is_map(config),
    do: %{"type" => "session.update", "session" => config}

  @doc ~s(An `input_audio_buffer.append` event carrying base64-encoded PCM audio.)
  @spec append_audio_event(binary()) :: map()
  def append_audio_event(pcm) when is_binary(pcm),
    do: %{"type" => "input_audio_buffer.append", "audio" => Base.encode64(pcm)}

  @doc ~s(An `input_audio_buffer.commit` event \(manual turn end\).)
  @spec commit_event() :: map()
  def commit_event, do: %{"type" => "input_audio_buffer.commit"}

  @doc ~s(A `response.create` event, optionally carrying a response config map.)
  @spec create_response_event(map()) :: map()
  def create_response_event(config \\ %{}) when is_map(config) do
    base = %{"type" => "response.create"}
    if map_size(config) == 0, do: base, else: Map.put(base, "response", config)
  end

  @doc "A `conversation.item.create` event carrying a user text message."
  @spec text_item(String.t()) :: map()
  def text_item(text) do
    %{
      "type" => "conversation.item.create",
      "item" => %{
        "type" => "message",
        "role" => "user",
        "content" => [%{"type" => "input_text", "text" => text}]
      }
    }
  end

  @doc "A `conversation.item.create` event returning a function/tool result."
  @spec function_call_output(String.t(), String.t()) :: map()
  def function_call_output(call_id, output) do
    %{
      "type" => "conversation.item.create",
      "item" => %{"type" => "function_call_output", "call_id" => call_id, "output" => output}
    }
  end

  @doc "Encodes a client event map to a JSON string for the wire."
  @spec encode(map()) :: String.t()
  def encode(event) when is_map(event), do: Jason.encode!(event)

  @doc """
  Parses a server event. Accepts a JSON string (decodes it) or an already
  decoded map; returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse_event(binary() | map()) :: {:ok, map()} | {:error, term()}
  def parse_event(event) when is_map(event), do: {:ok, event}
  def parse_event(json) when is_binary(json), do: Jason.decode(json)

  @doc "Extracts base64 audio from a `response.output_audio.delta` event, or nil."
  @spec audio_delta(map()) :: String.t() | nil
  def audio_delta(%{"type" => "response.output_audio.delta", "delta" => delta})
      when is_binary(delta),
      do: delta

  def audio_delta(_), do: nil

  @doc "The `type` of a server event (for routing), or nil."
  @spec event_type(map()) :: String.t() | nil
  def event_type(%{"type" => type}), do: type
  def event_type(_), do: nil
end
