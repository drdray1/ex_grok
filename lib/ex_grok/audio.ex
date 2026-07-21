defmodule ExGrok.Audio do
  @moduledoc """
  xAI Grok **audio** — text-to-speech (`/v1/tts`) and speech-to-text (`/v1/stt`).

  ## Text to speech

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, mp3} = ExGrok.Audio.speech(client, "Hello from Grok", voice_id: "eve")
      ExGrok.Audio.save(mp3, "hello.mp3")

  `speech/2` returns raw audio bytes by default. Pass `with_timestamps: true`
  for a JSON envelope (`%{"audio" => base64, "audio_timestamps" => ...}`).

  ## Speech to text

      {:ok, resp} = ExGrok.Audio.transcribe(client, {:file, "meeting.wav"}, language: "en")
      ExGrok.Audio.extract_transcript(resp)
      # => "..."

  Only batch (HTTP) TTS/STT are covered here; realtime streaming over
  WebSocket is a separate concern.
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @tts_allowed_opts ~w(voice_id language output_format speed text_normalization with_timestamps optimize_streaming_latency)a
  @stt_allowed_opts ~w(language format keyterm)a
  @default_stt_model "grok-stt"

  @doc """
  Synthesizes speech from `text` (`POST /tts`).

  Returns `{:ok, binary}` (raw audio bytes) by default, or `{:ok, map}` when
  `with_timestamps: true`.

  ## Options
    - `:voice_id` — voice (default server-side, e.g. `"eve"`)
    - `:language` — BCP-47 code or `"auto"`
    - `:output_format` — codec/sample-rate map
    - `:speed` — `0.7`–`1.5`
    - `:with_timestamps` — return a JSON envelope with char timings
  """
  @spec speech(client(), String.t(), keyword()) :: {:ok, binary() | map()} | {:error, term()}
  def speech(client, text, opts \\ []) do
    params =
      opts
      |> Keyword.take(@tts_allowed_opts)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.reduce(%{"text" => text}, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)

    client
    |> Req.post(url: "/tts", json: params)
    |> Client.handle_response()
  end

  @doc "Lists available TTS voices (`GET /tts/voices`)."
  @spec voices(client()) :: response()
  def voices(client) do
    client
    |> Req.get(url: "/tts/voices")
    |> Client.handle_response()
  end

  @doc """
  Transcribes audio to text (`POST /stt`, multipart).

  `source` is one of:
    - `{:file, path}` — read and upload a local file
    - `{:content, bytes, filename}` — upload in-memory bytes
    - `{:url, url}` — transcribe a remote audio URL

  ## Options
    - `:model` — STT model (default `"grok-stt"`)
    - `:language` — BCP-47 code
    - `:format` — response format (e.g. `"json"`)
    - `:keyterm` — bias term(s) for recognition
  """
  @spec transcribe(client(), tuple(), keyword()) :: response()
  def transcribe(client, source, opts \\ []) do
    fields =
      opts
      |> Keyword.take(@stt_allowed_opts)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), to_string(v)} end)

    fields = [{"model", Keyword.get(opts, :model, @default_stt_model)} | fields]

    client
    |> Req.post(url: "/stt", form_multipart: fields ++ [file_field(source)])
    |> Client.handle_response()
  end

  @doc "Writes audio bytes (from `speech/2`) to `path`. Returns `:ok` or `{:error, reason}`."
  @spec save(binary(), Path.t()) :: :ok | {:error, term()}
  def save(audio, path) when is_binary(audio), do: File.write(path, audio)

  @doc "The transcript text from an STT response, or nil."
  @spec extract_transcript(map()) :: String.t() | nil
  def extract_transcript(%{"text" => text}) when is_binary(text), do: text
  def extract_transcript(%{"transcript" => text}) when is_binary(text), do: text
  def extract_transcript(_), do: nil

  # ---------------------------------------------------------------------------

  # For a remote URL we send a plain field; otherwise a multipart file part.
  defp file_field({:url, url}), do: {"url", url}

  defp file_field({:content, bytes, filename}) when is_binary(bytes),
    do: {"file", {bytes, filename: filename}}

  defp file_field({:file, path}),
    do: {"file", {File.read!(path), filename: Path.basename(path)}}
end
