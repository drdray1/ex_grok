defmodule ExGrok.LiveSmokeTest do
  @moduledoc """
  Real requests against the xAI API. Excluded by default (see `test_helper.exs`);
  run with `mix test --only live` and `XAI_API_KEY` set.

  These exist because every other test in this suite stubs the transport, so all
  of them stayed green while the Responses API rejected our structured-output
  request with a 400 on every call. Run them before tagging a release.
  """

  use ExUnit.Case, async: false

  @moduletag :live

  alias ExGrok.{Audio, Chat, Responses}

  @schema %{
    "type" => "object",
    "properties" => %{"city" => %{"type" => "string"}},
    "required" => ["city"],
    "additionalProperties" => false
  }

  setup do
    case System.get_env("XAI_API_KEY") do
      nil -> flunk("XAI_API_KEY is not set; live tests cannot run")
      key -> %{client: ExGrok.new(key), model: System.get_env("XAI_MODEL", "grok-4.5")}
    end
  end

  test "Responses API accepts text.format structured output", ctx do
    assert {:ok, resp} =
             Responses.create(ctx.client, ctx.model, "Name any city as JSON.",
               text: Responses.json_schema_text("city", @schema)
             )

    assert {:ok, %{"city" => city}} = Responses.extract_parsed(resp)
    assert is_binary(city)
  end

  test "Chat Completions accepts response_format structured output", ctx do
    assert {:ok, resp} =
             Chat.create_completion(
               ctx.client,
               ctx.model,
               [Chat.user_message("Name any city as JSON.")],
               response_format: Chat.json_schema_format("city", @schema)
             )

    assert {:ok, %{"city" => city}} = Jason.decode(ExGrok.extract_content(resp))
    assert is_binary(city)
  end

  @tag :background
  test "background: true is actually honoured", ctx do
    # xAI's API reference marks `background` as "(Unsupported)". If that is
    # accurate, this library documents a feature the API ignores — `poll/3`,
    # `get/2`, the facade's `poll_response/3` and the README's "Stateful &
    # background responses" section all rest on it.
    #
    # A wire-shape test cannot settle this: asserting the flag reaches the body
    # says nothing about whether the server acted on it. Only a real call can,
    # which is the whole reason this file exists.
    #
    # An immediate "queued"/"in_progress" means the docs are stale and the
    # feature works. An instant "completed" means the flag is inert, and the
    # claims should come out of the docs while `background` stays in the
    # allowlist (the API does accept the key). Responses users needing async
    # would then be pointed at Chat's `deferred: true` + `get_deferred/2`.
    # `background` is rejected by build_params now, so this goes through the raw
    # map to ask the API directly. If xAI ever starts honouring it, this fails
    # and tells us the local guard has become too strict.
    result =
      Responses.create(ctx.client, %{
        "model" => ctx.model,
        "input" => "Count to three.",
        "background" => true
      })

    assert {:error, {:api_error, 400, _}} = result,
           "xAI now accepts background: true (got #{inspect(result)}). The guard in " <>
             "@rejected_opts is too strict — restore the parameter and the docs."
  end

  test "a malformed text.format is reported as a deserialization error", ctx do
    # 422 rather than 400: xAI deserializes the body before validating
    # arguments. A sanity check on the shape, nothing more — the comment here
    # used to claim this was the response_format tripwire, which it never was.
    assert {:error, {:api_error, 422, message}} =
             Responses.create(ctx.client, %{
               "model" => ctx.model,
               "input" => "hi",
               "text" => %{"format" => %{"type" => "json_schema"}}
             })

    assert is_binary(message)
  end

  test "the API still rejects response_format on /v1/responses", ctx do
    # The actual tripwire. It has to bypass `create/2` entirely: `validate_params/1`
    # intercepts a top-level "response_format" and returns before any HTTP, so
    # asking through the public API would only ever test our own guard against
    # itself — the same tautology that let the original bug ship.
    #
    # If this ever stops being a 4xx, xAI has relaxed and our guard is now the
    # thing that is wrong.
    {:ok, response} =
      Req.post(ctx.client,
        url: "/responses",
        json: %{
          "model" => ctx.model,
          "input" => "hi",
          "response_format" => %{
            "type" => "json_schema",
            "json_schema" => %{"name" => "city", "schema" => @schema, "strict" => true}
          }
        }
      )

    assert response.status >= 400,
           "xAI now accepts response_format on /v1/responses (got #{response.status}). " <>
             "The guard in Responses.validate_params/1 has become too strict."
  end

  # ---------------------------------------------------------------------------
  # Speech to Text
  #
  # `Audio` shipped in one commit and was never checked against the API, unlike
  # Chat and Responses. Its STT allowlist was three options wide, so a caller
  # asking for `vad_threshold` had it dropped by `Keyword.take/2` and got a 200
  # back describing a request it never made.
  #
  # Note what these assert, and what they cannot. `/v1/stt` answers **200 to
  # parameters that do not exist** - an invented `bogus_param` returns the same
  # transcript, byte for byte, as sending nothing. So on this endpoint a
  # successful request proves nothing at all, and a test asserting `{:ok, _}`
  # after sending an option would pass whether or not the option is real. That
  # is the same worthless shape as the old `background` test.
  #
  # The only honest check is differential: send the option, send it again
  # without, and compare. That is what these do.

  setup ctx do
    path = Path.join(System.tmp_dir!(), "ex_grok_live_stt.wav")
    File.write!(path, tone_wav())
    on_exit(fn -> File.rm(path) end)
    Map.put(ctx, :audio, {:file, path})
  end

  test "STT ignores parameters it does not know, so acceptance proves nothing", ctx do
    # The control for every test below. If this ever starts failing, xAI has
    # begun validating STT parameters and the differential tests can relax.
    assert {:ok, baseline} = Audio.transcribe(ctx.client, ctx.audio, language: "en")

    assert {:ok, invented} =
             Audio.transcribe(ctx.client, ctx.audio,
               language: "en",
               extra_params: %{"bogus_param" => "1"}
             )

    assert invented["text"] == baseline["text"],
           "/stt now reacts to unknown parameters; the notes above are stale"
  end

  @tag :vad
  test "vad_threshold is inert on grok-stt", ctx do
    # Measured 2026-08-25 on a 499 s radio capture: 0.2 against the default 0.5
    # produced byte-identical output, indistinguishable from `bogus_param`. The
    # reference documents the option; the model does not appear to read it.
    #
    # This is pinned as a *failing-when-fixed* test on purpose. If xAI wires it
    # up, this breaks and tells us a real knob just appeared - which matters,
    # because Scribe worked around its absence by chunking audio instead.
    assert {:ok, loose} =
             Audio.transcribe(ctx.client, ctx.audio, language: "en", vad_threshold: 0.05)

    assert {:ok, tight} =
             Audio.transcribe(ctx.client, ctx.audio, language: "en", vad_threshold: 0.95)

    assert loose["text"] == tight["text"],
           "vad_threshold now changes the transcript - it is no longer inert"
  end

  test "STT accepts the documented options without erroring", ctx do
    # Weak by necessity (see above), but it still catches the one thing that
    # would break callers: a parameter starting to return 4xx.
    assert {:ok, _} =
             Audio.transcribe(ctx.client, ctx.audio,
               language: "en",
               filler_words: true,
               format: true,
               diarize: true,
               keyterm: ["the Bull", "KUBL"]
             )
  end

  test "STT response carries duration and word timings", ctx do
    # Scribe reads `duration` to tell "heard it all, stopped writing" apart from
    # "never got the audio", and shifts `words` by each chunk's offset. If xAI
    # drops either field, chunked transcription loses its timeline.
    assert {:ok, resp} = Audio.transcribe(ctx.client, ctx.audio, language: "en")
    assert Map.has_key?(resp, "duration"), "no duration in #{inspect(Map.keys(resp))}"
    assert is_number(resp["duration"])
  end

  test "a byte slice of a CBR MP3 is transcribable on its own", ctx do
    # Scribe chunks audio by `binary_part/3` alone - no sox, no ffmpeg - which
    # only works because the decoder resyncs after a mid-frame cut. If xAI ever
    # starts rejecting headerless slices, that whole approach fails and this is
    # where it shows up.
    %{client: client} = ctx
    {:ok, mp3} = Audio.speech(client, "One two three four five six seven eight nine ten.")

    half = binary_part(mp3, div(byte_size(mp3), 2), div(byte_size(mp3), 2))

    assert {:ok, resp} = Audio.transcribe(client, {:content, half, "slice.mp3"}, language: "en")
    assert is_number(resp["duration"])
  end

  # 16 kHz mono 16-bit PCM, one second of a 440 Hz tone. Built here rather than
  # committed so the suite carries no binary fixture.
  defp tone_wav do
    rate = 16_000
    samples = for n <- 0..(rate - 1), do: round(8000 * :math.sin(2 * :math.pi() * 440 * n / rate))
    data = for s <- samples, into: <<>>, do: <<s::little-signed-16>>

    <<"RIFF", byte_size(data) + 36::little-32, "WAVEfmt ", 16::little-32, 1::little-16,
      1::little-16, rate::little-32, rate * 2::little-32, 2::little-16, 16::little-16, "data",
      byte_size(data)::little-32, data::binary>>
  end
end
