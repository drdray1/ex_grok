defmodule ExGrok.ChatTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Chat, Fixtures}

  @stub_name :chat_test_stub

  describe "create_completion/2 with params map" do
    test "sends POST to /chat/completions" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/chat/completions"
        assert conn.method == "POST"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-3-mini"
        assert length(params["messages"]) == 1

        Req.Test.json(conn, Fixtures.sample_chat_completion_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, response} =
               Chat.create_completion(client, %{
                 "model" => "grok-3-mini",
                 "messages" => [%{"role" => "user", "content" => "Hello"}]
               })

      assert response["id"] == "chatcmpl-test-123"
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, :unauthorized} =
               Chat.create_completion(client, %{
                 "model" => "grok-3-mini",
                 "messages" => [%{"role" => "user", "content" => "Hello"}]
               })
    end

    test "returns error on rate limit" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(Fixtures.sample_rate_limit_error())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, :rate_limited} =
               Chat.create_completion(client, %{
                 "model" => "grok-3-mini",
                 "messages" => [%{"role" => "user", "content" => "Hello"}]
               })
    end
  end

  describe "create_completion/4 convenience form" do
    test "builds params from model, messages, and opts" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-3-mini"
        assert params["temperature"] == 0.7
        assert params["max_tokens"] == 100
        assert length(params["messages"]) == 2

        Req.Test.json(conn, Fixtures.sample_chat_completion_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _response} =
               Chat.create_completion(
                 client,
                 "grok-3-mini",
                 [
                   Chat.system_message("You are helpful."),
                   Chat.user_message("Hello")
                 ],
                 temperature: 0.7,
                 max_tokens: 100
               )
    end

    test "works with default opts" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-3-mini"
        refute Map.has_key?(params, "temperature")

        Req.Test.json(conn, Fixtures.sample_chat_completion_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _response} =
               Chat.create_completion(client, "grok-3-mini", [Chat.user_message("Hi")])
    end

    test "includes reasoning_effort when specified" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["reasoning_effort"] == "high"

        Req.Test.json(conn, Fixtures.sample_chat_completion_with_reasoning())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _response} =
               Chat.create_completion(
                 client,
                 "grok-3-mini",
                 [Chat.user_message("Think hard about this")],
                 reasoning_effort: "high"
               )
    end
  end

  describe "extract_content/1" do
    test "extracts content from response" do
      response = Fixtures.sample_chat_completion_response()

      assert Chat.extract_content(response) ==
               "The meaning of life is a complex philosophical question."
    end

    test "returns nil for nil content (tool calls)" do
      response = Fixtures.sample_chat_completion_with_tool_calls()
      assert Chat.extract_content(response) == nil
    end

    test "returns nil for invalid response" do
      assert Chat.extract_content(%{}) == nil
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from response" do
      response = Fixtures.sample_chat_completion_with_tool_calls()
      calls = Chat.extract_tool_calls(response)
      assert length(calls) == 1
      assert hd(calls)["id"] == "call_abc123"
      assert hd(calls)["function"]["name"] == "get_weather"
    end

    test "returns empty list when no tool calls" do
      response = Fixtures.sample_chat_completion_response()
      assert Chat.extract_tool_calls(response) == []
    end

    test "returns empty list for invalid response" do
      assert Chat.extract_tool_calls(%{}) == []
    end
  end

  describe "extract_usage/1" do
    test "extracts usage from response" do
      response = Fixtures.sample_chat_completion_response()
      usage = Chat.extract_usage(response)
      assert usage["prompt_tokens"] == 10
      assert usage["completion_tokens"] == 20
      assert usage["total_tokens"] == 30
    end

    test "returns nil for invalid response" do
      assert Chat.extract_usage(%{}) == nil
    end
  end

  describe "extract_reasoning_content/1" do
    test "extracts reasoning content from response" do
      response = Fixtures.sample_chat_completion_with_reasoning()
      assert Chat.extract_reasoning_content(response) == "Let me think about this step by step..."
    end

    test "returns nil when no reasoning content" do
      response = Fixtures.sample_chat_completion_response()
      assert Chat.extract_reasoning_content(response) == nil
    end
  end

  describe "extract_finish_reason/1" do
    test "extracts finish reason" do
      response = Fixtures.sample_chat_completion_response()
      assert Chat.extract_finish_reason(response) == "stop"
    end

    test "extracts tool_calls finish reason" do
      response = Fixtures.sample_chat_completion_with_tool_calls()
      assert Chat.extract_finish_reason(response) == "tool_calls"
    end
  end

  describe "message builders" do
    test "user_message/1" do
      assert Chat.user_message("Hello") == %{"role" => "user", "content" => "Hello"}
    end

    test "system_message/1" do
      assert Chat.system_message("Be helpful") == %{"role" => "system", "content" => "Be helpful"}
    end

    test "assistant_message/1" do
      assert Chat.assistant_message("Sure!") == %{"role" => "assistant", "content" => "Sure!"}
    end

    test "tool_result_message/2" do
      assert Chat.tool_result_message("call_123", "72°F") == %{
               "role" => "tool",
               "tool_call_id" => "call_123",
               "content" => "72°F"
             }
    end
  end

  describe "structured output and tool builders" do
    @schema %{"type" => "object", "properties" => %{"n" => %{"type" => "number"}}}

    test "json_schema_format builds the NESTED chat-completions shape" do
      fmt = ExGrok.Chat.json_schema_format("invoice", @schema, description: "An invoice")

      assert fmt["type"] == "json_schema"
      assert fmt["json_schema"]["name"] == "invoice"
      assert fmt["json_schema"]["schema"] == @schema
      assert fmt["json_schema"]["strict"] == true
      assert fmt["json_schema"]["description"] == "An invoice"

      # Flat is the Responses shape and a 400 here. Asserting its absence is
      # what a presence-only test misses.
      refute Map.has_key?(fmt, "name")
      refute Map.has_key?(fmt, "schema")
    end

    test "strict can be disabled and description omitted" do
      fmt = ExGrok.Chat.json_schema_format("n", %{}, strict: false)
      assert fmt["json_schema"]["strict"] == false
      refute Map.has_key?(fmt["json_schema"], "description")
    end

    test "function_tool nests under a function key, unlike the Responses one" do
      chat = ExGrok.Chat.function_tool("get_weather", "Get weather", @schema)
      responses = ExGrok.Responses.function_tool("get_weather", "Get weather", @schema)

      assert chat["function"]["name"] == "get_weather"
      assert responses["name"] == "get_weather"
      refute chat == responses
      refute Map.has_key?(responses, "function")
    end

    test "response_format reaches the request body nested" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        assert params["response_format"]["json_schema"]["name"] == "invoice"
        # `text` is the Responses spelling and must not appear here.
        refute Map.has_key?(params, "text")

        Req.Test.json(conn, Fixtures.sample_chat_completion_response())
      end)

      assert {:ok, _} =
               Chat.create_completion(
                 Fixtures.test_client(@stub_name),
                 "grok-3-mini",
                 [Chat.user_message("hi")],
                 response_format: ExGrok.Chat.json_schema_format("invoice", @schema)
               )
    end
  end

  describe "stream_completion/5" do
    test "forwards options into the streamed body" do
      # Before this arity existed, the convenience streaming path hard-coded an
      # empty opts list, so temperature/tools/response_format could not be sent
      # at all without dropping to a raw params map.
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        assert params["stream"] == true
        assert params["temperature"] == 0.7
        assert params["response_format"]["json_schema"]["name"] == "invoice"

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, Fixtures.sample_sse_data())
      end)

      assert :ok =
               Chat.stream_completion(
                 Fixtures.test_client(@stub_name),
                 "grok-3-mini",
                 [Chat.user_message("hi")],
                 fn _chunk -> :ok end,
                 temperature: 0.7,
                 response_format: ExGrok.Chat.json_schema_format("invoice", %{})
               )
    end
  end

  describe "stream_completion/4" do
    test "invokes the callback per SSE chunk and returns :ok" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["stream"] == true

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, Fixtures.sample_sse_data())
      end)

      client = Fixtures.test_client(@stub_name)
      parent = self()

      assert :ok =
               Chat.stream_completion(
                 client,
                 "grok-3-mini",
                 [Chat.user_message("hi")],
                 fn chunk ->
                   send(parent, {:chunk, chunk})
                 end
               )

      assert_receive {:chunk, %{"choices" => _}}
    end

    test "maps error statuses from the stream" do
      for {status, expected} <- [{401, :unauthorized}, {429, :rate_limited}] do
        Req.Test.expect(@stub_name, fn conn ->
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
        end)

        client = Fixtures.test_client(@stub_name)

        assert {:error, ^expected} =
                 Chat.stream_completion(
                   client,
                   %{"model" => "grok-3-mini", "messages" => []},
                   fn _ -> :ok end
                 )
      end
    end

    test "maps a 400 to an api_error with the message" do
      Req.Test.expect(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:error, {:api_error, 400, _msg}} =
               Chat.stream_completion(
                 client,
                 %{"model" => "grok-3-mini", "messages" => []},
                 fn _ -> :ok end
               )
    end
  end

  describe "get_deferred/2" do
    test "returns {:ok, completion} when ready (200)" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/chat/deferred-completion/req-1"
        Req.Test.json(conn, Fixtures.sample_chat_completion_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, completion} = Chat.get_deferred(client, "req-1")
      assert Chat.extract_content(completion) =~ "meaning of life"
    end

    test "returns {:pending} while still processing (202)" do
      Req.Test.expect(@stub_name, fn conn ->
        Plug.Conn.send_resp(conn, 202, "")
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:pending} = Chat.get_deferred(client, "req-1")
    end
  end

  describe "deferred option" do
    test "create_completion/4 forwards deferred: true" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["deferred"] == true
        Req.Test.json(conn, %{"request_id" => "req-1"})
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, %{"request_id" => "req-1"}} =
               Chat.create_completion(client, "grok-4", [Chat.user_message("hi")], deferred: true)
    end
  end
end
