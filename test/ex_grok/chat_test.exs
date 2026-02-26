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
end
