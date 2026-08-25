defmodule ExGrok.AudioTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Audio, Fixtures}

  @stub_name :audio_test_stub

  describe "speech/3 (TTS)" do
    test "POSTs text to /tts and returns raw audio bytes" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/tts"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["text"] == "Hello"
        assert params["voice_id"] == "eve"

        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, "RAWBYTES")
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, "RAWBYTES"} = Audio.speech(client, "Hello", voice_id: "eve")
    end

    test "with_timestamps returns the JSON envelope" do
      Req.Test.expect(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_tts_timestamps())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"audio_timestamps" => _}} = Audio.speech(client, "Hi", with_timestamps: true)
    end
  end

  describe "voices/1" do
    test "GETs /tts/voices" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/tts/voices"
        Req.Test.json(conn, Fixtures.sample_voices())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"voices" => [%{"voice_id" => "eve"}]}} = Audio.voices(client)
    end
  end

  describe "speech/3 option validation" do
    test "an unknown option raises" do
      client = Fixtures.test_client(@stub_name)

      assert_raise ArgumentError, ~r/unknown option :voice/, fn ->
        Audio.speech(client, "Hello", voice: "eve")
      end
    end
  end

  describe "transcribe/3 (STT)" do
    test "POSTs multipart to /stt with model + file and returns transcript" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/stt"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "grok-stt"
        assert body =~ "clip.wav"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, resp} =
               Audio.transcribe(client, {:content, "audiobytes", "clip.wav"}, language: "en")

      assert Audio.extract_transcript(resp) == "hello world"
    end

    test "tuning options reach the request body, stringified" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "vad_threshold"
        assert body =~ "0.2"
        assert body =~ "filler_words"
        assert body =~ "true"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Audio.transcribe(client, {:content, "bytes", "a.wav"},
                 vad_threshold: 0.2,
                 filler_words: true
               )
    end

    test "a list of keyterms becomes repeated fields" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "the Bull"
        assert body =~ "KUBL"
        # One name, two values - the only way multipart carries a list.
        assert length(Regex.scan(~r/name="keyterm"/, body)) == 2
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Audio.transcribe(client, {:content, "bytes", "a.wav"},
                 keyterm: ["the Bull", "KUBL"]
               )
    end

    test "an unknown option raises instead of vanishing" do
      client = Fixtures.test_client(@stub_name)

      assert_raise ArgumentError, ~r/unknown option :vadthreshold/, fn ->
        Audio.transcribe(client, {:content, "bytes", "a.wav"}, vadthreshold: 0.2)
      end
    end

    test "extra_params carries a parameter this client does not know" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "smart_turn"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Audio.transcribe(client, {:content, "bytes", "a.wav"},
                 extra_params: %{"smart_turn" => true}
               )
    end

    test "extra_params overrides a field this client built" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "grok-stt-next"
        refute body =~ "grok-stt\r"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Audio.transcribe(client, {:content, "bytes", "a.wav"},
                 extra_params: %{"model" => "grok-stt-next"}
               )
    end

    test "url source sends a url field" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "https://ex/a.wav"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Audio.transcribe(client, {:url, "https://ex/a.wav"})
    end
  end

  describe "save/2" do
    test "writes bytes to disk" do
      path = Path.join(System.tmp_dir!(), "ex_grok_audio_test.bin")
      on_exit(fn -> File.rm(path) end)
      assert :ok = Audio.save("abc", path)
      assert File.read!(path) == "abc"
    end
  end

  describe "transcribe from a local file" do
    test "reads the file and uploads it by basename" do
      path = Path.join(System.tmp_dir!(), "ex_grok_stt_input.wav")
      File.write!(path, "WAVDATA")
      on_exit(fn -> File.rm(path) end)

      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "ex_grok_stt_input.wav"
        assert body =~ "WAVDATA"
        Req.Test.json(conn, Fixtures.sample_transcript())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Audio.transcribe(client, {:file, path})
    end
  end

  describe "extract_transcript/1" do
    test "handles transcript key and nil" do
      assert Audio.extract_transcript(%{"transcript" => "hey"}) == "hey"
      assert Audio.extract_transcript(%{}) == nil
    end
  end
end
