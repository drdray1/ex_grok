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
        assert params["image"] == "https://ex/f.jpg"

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
  end
end
