defmodule ExGrok.ResponsesTest do
  use ExUnit.Case, async: true

  alias ExGrok.Fixtures
  alias ExGrok.Responses

  @stub_name :responses_test_stub

  describe "create/2 with params map" do
    test "sends POST to /responses and returns the body" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/responses"
        assert conn.method == "POST"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-4.5"
        assert [%{"role" => "user"}] = params["input"]

        Req.Test.json(conn, Fixtures.sample_response_text())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, resp} =
               Responses.create(client, %{
                 "model" => "grok-4.5",
                 "input" => [%{"role" => "user", "content" => "Hi"}]
               })

      assert resp["object"] == "response"
    end

    test "maps 401 to :unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, :unauthorized} =
               Responses.create(client, %{"model" => "grok-4.5", "input" => "hi"})
    end
  end

  describe "create/4 builds params" do
    test "includes input, tools, and wraps reasoning_effort into reasoning object" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-4.5"
        assert params["input"] == [%{"role" => "user", "content" => "Hi"}]
        assert params["reasoning"] == %{"effort" => "high"}
        assert [%{"type" => "function", "name" => "get_weather"}] = params["tools"]
        assert params["tool_choice"] == "auto"
        Req.Test.json(conn, Fixtures.sample_response_text())
      end)

      client = Fixtures.test_client(@stub_name)
      tools = [Responses.function_tool("get_weather", "Get weather", %{"type" => "object"})]

      assert {:ok, _} =
               Responses.create(client, "grok-4.5", [Responses.user_input("Hi")],
                 reasoning_effort: "high",
                 tools: tools,
                 tool_choice: "auto"
               )
    end
  end

  describe "extract helpers" do
    test "extract_output_text concatenates message output_text" do
      assert Responses.extract_output_text(Fixtures.sample_response_text()) == "Hello there"
    end

    test "extract_output_text is nil when there is no message item" do
      assert Responses.extract_output_text(Fixtures.sample_response_function_call()) == nil
    end

    test "extract_function_calls returns function_call items" do
      assert [call] = Responses.extract_function_calls(Fixtures.sample_response_function_call())
      assert call["call_id"] == "call_abc123"
      assert call["name"] == "get_weather"
      assert Jason.decode!(call["arguments"]) == %{"location" => "San Francisco"}
    end

    test "extract_function_calls is empty for a text response" do
      assert Responses.extract_function_calls(Fixtures.sample_response_text()) == []
    end

    test "extract_reasoning pulls summary text" do
      assert Responses.extract_reasoning(Fixtures.sample_response_text()) =~ "Thinking it through"
    end

    test "extract_output_items returns the raw output list" do
      items = Responses.extract_output_items(Fixtures.sample_response_function_call())
      assert Enum.any?(items, &(&1["type"] == "function_call"))
    end

    test "extract_response_id / extract_usage / extract_status" do
      resp = Fixtures.sample_response_text()
      assert Responses.extract_response_id(resp) == "resp-test-123"
      assert Responses.extract_usage(resp)["total_tokens"] == 30
      assert Responses.extract_status(resp) == "completed"
    end
  end

  describe "builders" do
    test "function_call_output shape" do
      assert Responses.function_call_output("call_1", "72F") ==
               %{"type" => "function_call_output", "call_id" => "call_1", "output" => "72F"}
    end

    test "function_tool is flat" do
      tool = Responses.function_tool("f", "desc", %{"type" => "object"})
      assert tool["type"] == "function"
      assert tool["name"] == "f"
      refute Map.has_key?(tool, "function")
    end
  end

  describe "stream/3" do
    test "invokes the callback for each SSE event; delta_text pulls the text" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["stream"] == true

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, Fixtures.sample_response_sse_data())
      end)

      client = Fixtures.test_client(@stub_name)
      parent = self()

      assert :ok =
               Responses.stream(client, %{"model" => "grok-4.5", "input" => "hi"}, fn event ->
                 send(parent, {:event, event})
               end)

      assert_receive {:event, %{"type" => "response.output_text.delta", "delta" => "Hello"} = e1}
      assert Responses.delta_text(e1) == "Hello"
      assert_receive {:event, %{"delta" => " world"}}
      assert_receive {:event, %{"type" => "response.completed"}}
    end
  end

  describe "stream/3 error mapping" do
    test "maps 401 / 429 / api_error" do
      for {status, expected} <- [{401, :unauthorized}, {429, :rate_limited}] do
        Req.Test.expect(@stub_name, fn conn ->
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
        end)

        client = Fixtures.test_client(@stub_name)

        assert {:error, ^expected} =
                 Responses.stream(client, %{"model" => "grok-4.5", "input" => "hi"}, fn _ ->
                   :ok
                 end)
      end

      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, {:api_error, 500, _}} =
               Responses.stream(client, %{"model" => "grok-4.5", "input" => "hi"}, fn _ -> :ok end)
    end
  end

  describe "extractor nil/empty branches" do
    test "all extractors are total on unexpected shapes" do
      assert Responses.extract_output_text(%{}) == nil
      assert Responses.extract_reasoning(%{}) == nil
      assert Responses.extract_annotations(%{}) == []
      assert Responses.extract_server_tool_calls(%{}) == []
      assert Responses.extract_output_items(%{}) == []
      assert Responses.extract_usage(%{}) == nil
      assert Responses.extract_response_id(%{}) == nil
      assert Responses.extract_status(%{}) == nil
      assert Responses.delta_text(%{"type" => "other"}) == nil
      assert Responses.reasoning_delta(%{}) == nil
      assert Responses.function_call_arguments_delta(%{}) == nil
      assert Responses.completed_response(%{}) == nil
      assert Responses.event_type(%{}) == nil
    end
  end

  describe "server-side tool builders" do
    test "web_search_tool with and without config" do
      assert Responses.web_search_tool() == %{"type" => "web_search"}

      tool =
        Responses.web_search_tool(allowed_domains: ["x.ai"], enable_image_understanding: true)

      assert tool["type"] == "web_search"
      assert tool["allowed_domains"] == ["x.ai"]
      assert tool["enable_image_understanding"] == true
    end

    test "x_search / code_execution / collections_search default shapes" do
      assert Responses.x_search_tool() == %{"type" => "x_search"}
      assert Responses.code_execution_tool() == %{"type" => "code_execution"}
      assert Responses.collections_search_tool() == %{"type" => "collections_search"}
    end

    test "mcp_tool carries server_label + server_url and merges opts" do
      tool = Responses.mcp_tool("docs", "https://mcp.example.com/sse", allowed_tools: ["search"])
      assert tool["type"] == "mcp"
      assert tool["server_label"] == "docs"
      assert tool["server_url"] == "https://mcp.example.com/sse"
      assert tool["allowed_tools"] == ["search"]
    end

    test "server tools pass through create/4 into the tools array" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["tools"] == [%{"type" => "web_search"}]
        Req.Test.json(conn, Fixtures.sample_response_with_citations())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Responses.create(client, "grok-4.5", [Responses.user_input("news?")],
                 tools: [Responses.web_search_tool()]
               )
    end
  end

  describe "citations and server tool calls" do
    test "extract_citations de-duplicates url_citation annotations in order" do
      assert Responses.extract_citations(Fixtures.sample_response_with_citations()) ==
               ["https://x.ai", "https://docs.x.ai"]
    end

    test "extract_annotations returns all annotation maps" do
      assert length(Responses.extract_annotations(Fixtures.sample_response_with_citations())) == 3
    end

    test "extract_server_tool_calls finds the web_search_call item" do
      assert [%{"type" => "web_search_call"}] =
               Responses.extract_server_tool_calls(Fixtures.sample_response_with_citations())
    end

    test "extract_citations is empty for a plain text response" do
      assert Responses.extract_citations(Fixtures.sample_response_text()) == []
    end
  end

  describe "structured output" do
    test "json_schema_format builds a strict response_format" do
      schema = %{"type" => "object", "properties" => %{"city" => %{"type" => "string"}}}
      fmt = Responses.json_schema_format("weather", schema, description: "A city")

      assert fmt["type"] == "json_schema"
      assert fmt["json_schema"]["name"] == "weather"
      assert fmt["json_schema"]["schema"] == schema
      assert fmt["json_schema"]["strict"] == true
      assert fmt["json_schema"]["description"] == "A city"
    end

    test "strict can be disabled and description omitted" do
      fmt = Responses.json_schema_format("n", %{}, strict: false)
      assert fmt["json_schema"]["strict"] == false
      refute Map.has_key?(fmt["json_schema"], "description")
    end

    test "extract_parsed decodes output_text JSON" do
      assert {:ok, %{"city" => "Tokyo", "temp_c" => 18}} =
               Responses.extract_parsed(Fixtures.sample_response_structured())
    end

    test "extract_parsed errors when there is no output text" do
      assert {:error, :no_output_text} =
               Responses.extract_parsed(Fixtures.sample_response_function_call())
    end
  end

  describe "multimodal input builders" do
    test "input_text and input_image shapes" do
      assert Responses.input_text("hi") == %{"type" => "input_text", "text" => "hi"}

      img = Responses.input_image("https://img/x.png", detail: "high")
      assert img["type"] == "input_image"
      assert img["image_url"] == "https://img/x.png"
      assert img["detail"] == "high"
    end
  end

  describe "streaming event helpers" do
    test "each delta helper matches only its own event type" do
      r = %{"type" => "response.reasoning_summary_text.delta", "delta" => "think"}
      f = %{"type" => "response.function_call_arguments.delta", "delta" => "{}"}
      c = %{"type" => "response.completed", "response" => %{"id" => "x"}}

      assert Responses.reasoning_delta(r) == "think"
      assert Responses.reasoning_delta(f) == nil
      assert Responses.function_call_arguments_delta(f) == "{}"
      assert Responses.completed_response(c) == %{"id" => "x"}
      assert Responses.completed_response(r) == nil
      assert Responses.event_type(c) == "response.completed"
    end
  end

  describe "get/2 and delete/2" do
    test "get issues GET /responses/:id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/responses/resp-bg-1"
        Req.Test.json(conn, Fixtures.sample_response_text())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"object" => "response"}} = Responses.get(client, "resp-bg-1")
    end

    test "delete issues DELETE /responses/:id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/v1/responses/resp-1"
        Req.Test.json(conn, %{"id" => "resp-1", "deleted" => true})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"deleted" => true}} = Responses.delete(client, "resp-1")
    end
  end

  describe "poll/3" do
    test "polls until a terminal status, then returns the response" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(@stub_name, fn conn ->
        n = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        body =
          if n == 0,
            do: Fixtures.sample_response_background_queued(),
            else: Fixtures.sample_response_text()

        Req.Test.json(conn, body)
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"status" => "completed"}} =
               Responses.poll(client, "resp-bg-1", interval_ms: 1, max_attempts: 5)
    end

    test "returns :timeout when attempts are exhausted" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, Fixtures.sample_response_background_queued())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, :timeout} =
               Responses.poll(client, "resp-bg-1", interval_ms: 1, max_attempts: 3)
    end
  end

  describe "compact/2" do
    test "posts to /responses/compact" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/responses/compact"
        assert conn.method == "POST"
        Req.Test.json(conn, Fixtures.sample_response_text())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Responses.compact(client, %{"model" => "grok-4.5", "input" => []})
    end
  end

  describe "background create" do
    test "passes background: true through build_params" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["background"] == true
        Req.Test.json(conn, Fixtures.sample_response_background_queued())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"status" => "queued"}} =
               Responses.create(client, "grok-4.5", [Responses.user_input("hi")],
                 background: true
               )
    end
  end
end
