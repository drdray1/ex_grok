defmodule ExGrok.StreamingTest do
  use ExUnit.Case, async: true

  alias ExGrok.Streaming

  describe "parse_sse/1" do
    test "parses single SSE event" do
      data = "data: {\"id\":\"123\",\"content\":\"hello\"}\n\n"
      assert [%{"id" => "123", "content" => "hello"}] = Streaming.parse_sse(data)
    end

    test "parses multiple SSE events" do
      data = """
      data: {"id":"1"}

      data: {"id":"2"}

      data: {"id":"3"}

      """

      chunks = Streaming.parse_sse(data)
      assert length(chunks) == 3
      assert Enum.map(chunks, & &1["id"]) == ["1", "2", "3"]
    end

    test "filters out [DONE] sentinel" do
      data = "data: {\"id\":\"123\"}\n\ndata: [DONE]\n\n"
      assert [%{"id" => "123"}] = Streaming.parse_sse(data)
    end

    test "skips non-data lines" do
      data = "event: message\ndata: {\"id\":\"123\"}\nid: 456\n\n"
      assert [%{"id" => "123"}] = Streaming.parse_sse(data)
    end

    test "skips invalid JSON" do
      data = "data: {invalid json}\n\ndata: {\"id\":\"123\"}\n\n"
      assert [%{"id" => "123"}] = Streaming.parse_sse(data)
    end

    test "returns empty list for empty data" do
      assert [] = Streaming.parse_sse("")
    end

    test "returns empty list for only [DONE]" do
      assert [] = Streaming.parse_sse("data: [DONE]\n\n")
    end

    test "parses realistic streaming chunks" do
      data = ExGrok.Fixtures.sample_sse_data()
      chunks = Streaming.parse_sse(data)

      assert length(chunks) == 4

      # First chunk has role
      assert get_in(chunks, [Access.at(0), "choices", Access.at(0), "delta", "role"]) ==
               "assistant"

      # Middle chunks have content
      assert get_in(chunks, [Access.at(1), "choices", Access.at(0), "delta", "content"]) ==
               "Hello"

      assert get_in(chunks, [Access.at(2), "choices", Access.at(0), "delta", "content"]) ==
               " world"

      # Last chunk has finish_reason
      assert get_in(chunks, [Access.at(3), "choices", Access.at(0), "finish_reason"]) == "stop"
    end
  end

  describe "done?/1" do
    test "returns true for [DONE] data" do
      assert Streaming.done?("data: [DONE]\n\n")
    end

    test "returns true when [DONE] is mixed with other data" do
      data = "data: {\"id\":\"123\"}\n\ndata: [DONE]\n\n"
      assert Streaming.done?(data)
    end

    test "returns false for normal data" do
      refute Streaming.done?("data: {\"id\":\"123\"}\n\n")
    end

    test "returns false for empty data" do
      refute Streaming.done?("")
    end
  end

  describe "extract_delta_content/1" do
    test "extracts content from delta" do
      chunk = %{"choices" => [%{"delta" => %{"content" => "Hello"}, "index" => 0}]}
      assert Streaming.extract_delta_content(chunk) == "Hello"
    end

    test "returns nil for empty delta" do
      chunk = %{"choices" => [%{"delta" => %{}, "index" => 0}]}
      assert Streaming.extract_delta_content(chunk) == nil
    end

    test "returns nil for role-only delta" do
      chunk = %{"choices" => [%{"delta" => %{"role" => "assistant"}, "index" => 0}]}
      assert Streaming.extract_delta_content(chunk) == nil
    end

    test "returns nil for invalid structure" do
      assert Streaming.extract_delta_content(%{}) == nil
    end
  end

  describe "extract_finish_reason/1" do
    test "extracts finish reason" do
      chunk = %{"choices" => [%{"finish_reason" => "stop", "index" => 0}]}
      assert Streaming.extract_finish_reason(chunk) == "stop"
    end

    test "returns nil when no finish reason" do
      chunk = %{"choices" => [%{"finish_reason" => nil, "index" => 0}]}
      assert Streaming.extract_finish_reason(chunk) == nil
    end

    test "returns nil for invalid structure" do
      assert Streaming.extract_finish_reason(%{}) == nil
    end
  end
end
