defmodule ExGrok.VideoTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Fixtures, Video}

  @stub_name :video_test_stub

  describe "generate/3" do
    test "POSTs prompt + options to /videos/generations and returns request_id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/videos/generations"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["prompt"] == "a neon city"
        assert params["model"] == "grok-imagine-video"
        assert params["duration"] == 8
        assert params["image"] == %{"url" => "https://ex/f.jpg"}

        Req.Test.json(conn, Fixtures.sample_video_accepted())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"request_id" => "vid-req-1"}} =
               Video.generate(client, "a neon city", duration: 8, image: "https://ex/f.jpg")
    end
  end

  describe "get/2 and extractors" do
    test "GETs /videos/:id and extracts url + status" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/videos/vid-req-1"
        Req.Test.json(conn, Fixtures.sample_video_done())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, job} = Video.get(client, "vid-req-1")
      assert Video.extract_status(job) == "done"
      assert Video.extract_video_url(job) == "https://vidgen.x.ai/abc/video.mp4"
    end
  end

  describe "poll/3" do
    test "polls until status is done" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        n = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
        body = if n == 0, do: Fixtures.sample_video_pending(), else: Fixtures.sample_video_done()
        Req.Test.json(conn, body)
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"status" => "done"}} =
               Video.poll(client, "vid-req-1", interval_ms: 1, max_attempts: 5)
    end

    test "times out when never terminal" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_video_pending())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :timeout} = Video.poll(client, "vid-req-1", interval_ms: 1, max_attempts: 3)
    end

    test "propagates an error from get/2" do
      Req.Test.stub(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, {:not_found, _}} = Video.poll(client, "vid-req-1", interval_ms: 1)
    end
  end

  describe "generate/3 with all options + extractor fallbacks" do
    test "builds every optional param, wrapping media refs as url objects" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-imagine-video-1.5"
        assert params["aspect_ratio"] == "9:16"
        assert params["resolution"] == "1080p"
        assert params["generate_audio"] == true
        assert params["reference_images"] == [%{"url" => "https://r/1.jpg"}, %{"file_id" => "f"}]
        assert params["reference_audios"] == [%{"voice_id" => "v1"}]
        assert params["last_frame"] == %{"url" => "https://r/last.jpg"}

        assert params["keyframes"] == [
                 %{"image" => %{"url" => "https://r/k.jpg"}, "timestamp_s" => 2.5}
               ]

        assert params["storage_options"] == %{"filename" => "out.mp4"}
        Req.Test.json(conn, Fixtures.sample_video_accepted())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Video.generate(client, "a scene",
                 model: "grok-imagine-video-1.5",
                 aspect_ratio: "9:16",
                 resolution: "1080p",
                 generate_audio: true,
                 reference_images: ["https://r/1.jpg", %{"file_id" => "f"}],
                 reference_audios: [%{"voice_id" => "v1"}],
                 last_frame: "https://r/last.jpg",
                 keyframes: [{"https://r/k.jpg", 2.5}],
                 storage_options: %{"filename" => "out.mp4"}
               )
    end

    test "rejects :video, which belongs to edit/3 and extend/3" do
      client = Fixtures.test_client(@stub_name)

      assert_raise ArgumentError, ~r/edit\/3 or extend\/3/, fn ->
        Video.generate(client, "x", video: "https://v/base.mp4")
      end
    end

    test "extractors return nil when absent" do
      assert Video.extract_video_url(%{}) == nil
      assert Video.extract_status(%{}) == nil
    end
  end

  describe "edit/3" do
    test "POSTs to /videos/edits with the source video as a url object" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/videos/edits"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["prompt"] == "make it snow"
        assert params["model"] == "grok-imagine-video"
        assert params["video"] == %{"url" => "https://v/in.mp4"}
        refute Map.has_key?(params, "duration")

        Req.Test.json(conn, Fixtures.sample_video_accepted())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"request_id" => "vid-req-1"}} =
               Video.edit(client, "make it snow", video: "https://v/in.mp4", duration: 5)
    end

    test "requires :video" do
      client = Fixtures.test_client(@stub_name)
      assert_raise KeyError, fn -> Video.edit(client, "x", []) end
    end
  end

  describe "extend/3" do
    test "POSTs to /videos/extensions with video and duration" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/videos/extensions"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["video"] == %{"url" => "https://v/in.mp4"}
        assert params["duration"] == 4
        refute Map.has_key?(params, "aspect_ratio")

        Req.Test.json(conn, Fixtures.sample_video_accepted())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Video.extend(client, "keep going",
                 video: "https://v/in.mp4",
                 duration: 4,
                 aspect_ratio: "1:1"
               )
    end
  end
end
