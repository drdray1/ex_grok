defmodule ExGrokTest do
  @moduledoc "Exercises the top-level ExGrok facade delegates."
  use ExUnit.Case, async: true

  alias ExGrok.Fixtures

  @stub_name :ex_grok_facade_stub

  # A routing stub that answers each delegate's HTTP call by path + method.
  defp routing_client do
    Req.Test.stub(@stub_name, fn conn ->
      route(conn.method, conn.request_path, conn)
    end)

    ExGrok.new(Fixtures.sample_api_key(), plug: {Req.Test, @stub_name})
    |> Req.Request.merge_options(retry: false)
  end

  defp route("GET", "/v1/models", conn),
    do: Req.Test.json(conn, Fixtures.sample_models_response())

  defp route("GET", "/v1/models/" <> _, conn), do: Req.Test.json(conn, %{"id" => "grok-4.5"})
  defp route("GET", "/v1/api-key", conn), do: Req.Test.json(conn, Fixtures.sample_api_key_info())
  defp route("GET", "/v1/tts/voices", conn), do: Req.Test.json(conn, Fixtures.sample_voices())
  defp route("GET", "/v1/files", conn), do: Req.Test.json(conn, Fixtures.sample_files_list())

  defp route("GET", "/v1/videos/" <> _, conn),
    do: Req.Test.json(conn, Fixtures.sample_video_done())

  defp route("GET", "/v1/responses/" <> _, conn),
    do: Req.Test.json(conn, Fixtures.sample_response_text())

  defp route("DELETE", "/v1/files/" <> _, conn), do: Req.Test.json(conn, %{"deleted" => true})

  defp route("DELETE", "/v1/responses/" <> _, conn),
    do: Req.Test.json(conn, %{"deleted" => true})

  defp route("POST", "/v1/chat/completions", conn),
    do: Req.Test.json(conn, Fixtures.sample_chat_completion_response())

  defp route("POST", "/v1/responses", conn),
    do: Req.Test.json(conn, Fixtures.sample_response_text())

  defp route("POST", "/v1/images/generations", conn),
    do: Req.Test.json(conn, %{"data" => [%{"url" => "https://img/x.png"}]})

  defp route("POST", "/v1/images/edits", conn),
    do: Req.Test.json(conn, %{"data" => [%{"url" => "https://img/y.png"}]})

  defp route("POST", "/v1/videos/generations", conn),
    do: Req.Test.json(conn, Fixtures.sample_video_accepted())

  defp route("POST", "/v1/tts", conn), do: Req.Test.json(conn, Fixtures.sample_tts_timestamps())
  defp route("POST", "/v1/stt", conn), do: Req.Test.json(conn, Fixtures.sample_transcript())

  defp route("POST", "/v1/documents/search", conn),
    do: Req.Test.json(conn, Fixtures.sample_search_results())

  defp route(_method, _path, conn), do: Req.Test.json(conn, %{"ok" => true})

  describe "client + account delegates" do
    test "new, management_client, api_key_info, healthcheck" do
      client = routing_client()
      assert %Req.Request{} = client
      assert %Req.Request{} = ExGrok.management_client("mgmt")
      assert {:ok, %{"api_key_id" => _}} = ExGrok.api_key_info(client)
      assert :ok = ExGrok.healthcheck(client)
    end
  end

  describe "chat delegates" do
    test "message builders" do
      assert ExGrok.user_message("h") == %{"role" => "user", "content" => "h"}
      assert ExGrok.system_message("s") == %{"role" => "system", "content" => "s"}
      assert ExGrok.assistant_message("a") == %{"role" => "assistant", "content" => "a"}
      assert %{"role" => "tool"} = ExGrok.tool_result_message("id", "out")
    end

    test "create_completion and extractors" do
      client = routing_client()
      assert {:ok, resp} = ExGrok.create_completion(client, "grok-4", [ExGrok.user_message("hi")])
      assert ExGrok.extract_content(resp) =~ "meaning of life"
      assert ExGrok.extract_tool_calls(resp) == []
      assert is_map(ExGrok.extract_usage(resp))
      assert ExGrok.extract_finish_reason(resp) == "stop"
      assert ExGrok.extract_reasoning_content(%{}) == nil
    end
  end

  describe "responses delegates" do
    test "create_response, get/delete/poll, and extractors" do
      client = routing_client()

      assert {:ok, resp} =
               ExGrok.create_response(client, "grok-4.5", [ExGrok.Responses.user_input("hi")])

      assert ExGrok.extract_output_text(resp) == "Hello there"
      assert ExGrok.extract_reasoning(resp) =~ "Thinking"
      assert ExGrok.extract_function_calls(resp) == []
      assert is_list(ExGrok.extract_output_items(resp))
      assert ExGrok.extract_citations(resp) == []
      assert ExGrok.extract_server_tool_calls(resp) == []
      assert {:error, _} = ExGrok.extract_parsed(resp)
      assert {:ok, _} = ExGrok.get_response(client, "resp-1")
      assert {:ok, _} = ExGrok.delete_response(client, "resp-1")
      assert %{"type" => "mcp"} = ExGrok.mcp_tool("l", "https://u")
    end
  end

  describe "models / images delegates" do
    test "models" do
      client = routing_client()
      assert {:ok, resp} = ExGrok.list_models(client)
      assert ExGrok.extract_model_ids(resp) != []
      assert [_ | _] = ExGrok.extract_models(resp)
      assert {:ok, %{"id" => "grok-4.5"}} = ExGrok.get_model(client, "grok-4.5")
    end

    test "images" do
      client = routing_client()
      assert {:ok, gen} = ExGrok.generate_image(client, "a cat")
      assert ExGrok.extract_image_urls(gen) == ["https://img/x.png"]
      assert [_] = ExGrok.extract_images(gen)
      assert {:ok, _} = ExGrok.edit_image(client, "make it blue", image_url: "https://i/x.png")
    end
  end

  describe "video / audio delegates" do
    test "video" do
      client = routing_client()
      assert {:ok, %{"request_id" => id}} = ExGrok.generate_video(client, "a city")
      assert {:ok, job} = ExGrok.get_video(client, id)
      assert ExGrok.extract_video_url(job) =~ "video.mp4"
      assert {:ok, %{"status" => "done"}} = ExGrok.poll_video(client, id, interval_ms: 1)
    end

    test "audio" do
      client = routing_client()

      assert {:ok, %{"audio_timestamps" => _}} =
               ExGrok.speech(client, "hi", with_timestamps: true)

      assert {:ok, %{"voices" => _}} = ExGrok.list_voices(client)
      assert {:ok, resp} = ExGrok.transcribe(client, {:url, "https://a/x.wav"})
      assert ExGrok.extract_transcript(resp) == "hello world"
    end
  end

  describe "files / collections delegates" do
    test "files" do
      client = routing_client()

      assert {:ok, _} =
               ExGrok.upload_file(client, {:content, "d", "f.pdf"}, purpose: "collections")

      assert {:ok, _} = ExGrok.list_files(client)
      assert {:ok, %{"deleted" => true}} = ExGrok.delete_file(client, "file-1")
      assert ExGrok.extract_file_id(Fixtures.sample_file()) == "file-abc123"
    end

    test "collections" do
      client = routing_client()
      assert {:ok, _} = ExGrok.create_collection(client, "C")
      assert {:ok, _} = ExGrok.add_document_to_collection(client, "coll", "file")
      assert {:ok, _} = ExGrok.search_collection(client, "q", collection_ids: ["coll"])
      assert ExGrok.extract_collection_id(Fixtures.sample_collection()) == "coll-xyz"
    end
  end

  describe "streaming + poll delegates" do
    test "stream_completion and stream_response forward chunks" do
      Req.Test.stub(@stub_name, fn conn ->
        payload =
          if conn.request_path == "/v1/responses",
            do: Fixtures.sample_response_sse_data(),
            else: Fixtures.sample_sse_data()

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, payload)
      end)

      client =
        ExGrok.new(Fixtures.sample_api_key(), plug: {Req.Test, @stub_name})
        |> Req.Request.merge_options(retry: false)

      parent = self()

      assert :ok =
               ExGrok.stream_completion(client, "grok-4", [ExGrok.user_message("hi")], fn c ->
                 send(parent, {:c, c})
               end)

      assert :ok =
               ExGrok.stream_response(
                 client,
                 %{"model" => "grok-4.5", "input" => "hi"},
                 fn e -> send(parent, {:e, e}) end
               )

      assert_receive {:c, _}
      assert_receive {:e, _}
    end

    test "poll_response reaches a terminal status" do
      client = routing_client()

      assert {:ok, %{"status" => "completed"}} =
               ExGrok.poll_response(client, "resp-1", interval_ms: 1)
    end

    test "verify_credentials returns an error tuple for a bad key" do
      assert {:error, _} = ExGrok.verify_credentials("xai-invalid")
    end
  end

  describe "usage delegates" do
    test "usage accessors" do
      resp = Fixtures.sample_response_text()
      assert ExGrok.usage_input_tokens(resp) == 10
      assert ExGrok.usage_output_tokens(resp) == 20
      assert ExGrok.usage_total_tokens(resp) == 30
      assert ExGrok.usage_reasoning_tokens(%{}) == nil
      assert ExGrok.usage_cached_tokens(%{}) == nil
      assert ExGrok.usage_cost_usd(%{}) == nil
    end
  end
end
