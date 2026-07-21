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
end
