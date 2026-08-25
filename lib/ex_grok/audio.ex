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

  ## What `/v1/stt` does with options

  It ignores the ones it does not recognise and answers `200`. An invented
  parameter returns the same transcript, byte for byte, as sending nothing - so
  a request succeeding tells you nothing about whether the option took effect.
  That is why option names are checked here, by `ExGrok.Options`, rather than
  left to the server: an unrecognised key would otherwise vanish twice over.

  Measured 2026-08-25, and worth knowing before reaching for it:

    * `vad_threshold` appears **inert** on `grok-stt`. `0.05` and `0.95` produce
      identical output on the same audio, as does an invented parameter. It is
      documented by xAI and accepted by the endpoint; it just does not seem to
      do anything yet. `test/ex_grok/live_smoke_test.exs` pins this so we hear
      about it if that changes.
    * Long audio is transcribed in full but *written up* only in part - the
      model emits roughly sixty to ninety words and stops, however many minutes
      it was handed. The lever is input length, not any request parameter.
  """

  alias ExGrok.Client
  alias ExGrok.Options

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @tts_allowed_opts ~w(voice_id language output_format speed text_normalization with_timestamps optimize_streaming_latency extra_params)a

  # `format`, `filler_words`, `diarize` and `multichannel` are booleans; xAI
  # spells the inverse-text-normalization switch `format`, not `response_format`
  # - there is no response-shape option on this endpoint.
  @stt_allowed_opts ~w(language format keyterm vad_threshold filler_words diarize multichannel channels audio_format sample_rate extra_params)a
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
    Options.validate!(opts, @tts_allowed_opts, %{}, "the Text to Speech API (/v1/tts)")
    {extra, opts} = Options.pop_extra(opts)

    params =
      opts
      |> Keyword.take(@tts_allowed_opts)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.reduce(%{"text" => text}, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
      # Merged last so an escape-hatch value wins over a built one.
      |> Map.merge(extra)

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
    - `:format` — inverse text normalization (boolean, default `false`)
    - `:keyterm` — bias term, or a list of them (max 100, 50 chars each)
    - `:vad_threshold` — speech-detection threshold, `0.0`–`1.0` (default `0.5`).
      Lower it when quiet speech shares the audio with something louder — music
      under a radio host, say — and whole passages come back missing.
    - `:filler_words` — keep "uh", "um", "er" (boolean, default `false`)
    - `:diarize` — label speakers (boolean, default `false`)
    - `:multichannel` — transcribe each channel independently (boolean)
    - `:channels` — channel count, 2–8, for raw multichannel audio
    - `:audio_format` — `"pcm"`, `"mulaw"` or `"alaw"`, for raw audio
    - `:sample_rate` — Hz, for raw audio
    - `:extra_params` — map of parameters this client does not know about,
      merged last so it can also override one it does

  Every field is sent as multipart, so values are stringified: `0.2` goes up as
  `"0.2"` and `true` as `"true"`. A list value becomes a repeated field, which
  is how `:keyterm` carries more than one term.
  """
  @spec transcribe(client(), tuple(), keyword()) :: response()
  def transcribe(client, source, opts \\ []) do
    {model, opts} = Keyword.pop(opts, :model, @default_stt_model)

    Options.validate!(opts, @stt_allowed_opts, %{}, "the Speech to Text API (/v1/stt)")
    {extra, opts} = Options.pop_extra(opts)

    extra_fields = encode_fields(extra)
    overridden = MapSet.new(extra_fields, &elem(&1, 0))

    fields =
      [{"model", to_string(model)}]
      |> Enum.concat(encode_fields(Keyword.take(opts, @stt_allowed_opts)))
      |> Enum.reject(&MapSet.member?(overridden, elem(&1, 0)))
      |> Enum.concat(extra_fields)

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

  # Multipart carries strings, so every value is stringified here rather than at
  # each call site. A list becomes repeated fields under one name - `keyterm`
  # takes up to 100 terms, and there is no other way to spell that in multipart.
  defp encode_fields(opts) do
    Enum.flat_map(opts, fn
      {_key, nil} -> []
      {key, values} when is_list(values) -> Enum.map(values, &{to_string(key), to_string(&1)})
      {key, value} -> [{to_string(key), to_string(value)}]
    end)
  end

  # For a remote URL we send a plain field; otherwise a multipart file part.
  defp file_field({:url, url}), do: {"url", url}

  defp file_field({:content, bytes, filename}) when is_binary(bytes),
    do: {"file", {bytes, filename: filename}}

  defp file_field({:file, path}),
    do: {"file", {File.read!(path), filename: Path.basename(path)}}
end
