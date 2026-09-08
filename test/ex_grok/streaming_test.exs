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
  describe "parse_sse/2 (chunked streams)" do
    test "an event split across two chunks survives" do
      {events, rest} = Streaming.parse_sse(~s(data: {"type":"a"}\n\ndata: {"ty), "")
      assert events == [%{"type" => "a"}]
      assert rest == ~s(data: {"ty)

      assert {[%{"type" => "b"}], ""} = Streaming.parse_sse(~s(pe":"b"}\n\n), rest)
    end

    test "an event split across many chunks survives" do
      json = ~s(data: {"type":"response.completed","response":{"output":[1,2,3]}}\n\n)

      {events, rest} =
        json
        |> String.graphemes()
        |> Enum.reduce({[], ""}, fn ch, {acc, buf} ->
          {events, rest} = Streaming.parse_sse(ch, buf)
          {acc ++ events, rest}
        end)

      assert rest == ""
      assert [%{"type" => "response.completed", "response" => %{"output" => [1, 2, 3]}}] = events
    end

    # The prod failure this arity exists for: small deltas arrive fine, then the
    # big terminal event straddles a chunk boundary and used to vanish, leaving
    # the caller with a stream that never completed.
    test "the terminal event is not lost when it straddles a boundary" do
      big = %{"type" => "response.completed", "response" => %{"pad" => String.duplicate("x", 5_000)}}
      wire = ~s(data: {"type":"response.output_text.delta","delta":"hi"}\n\n) <>
               "data: " <> Jason.encode!(big) <> "\n\n"

      {chunk1, chunk2} = String.split_at(wire, 100)

      {first, buf} = Streaming.parse_sse(chunk1, "")
      {second, rest} = Streaming.parse_sse(chunk2, buf)

      assert [%{"type" => "response.output_text.delta"}] = first
      assert [%{"type" => "response.completed"}] = second
      assert rest == ""
    end

    test "a chunk ending exactly on an event boundary leaves nothing buffered" do
      assert {[%{"a" => 1}], ""} = Streaming.parse_sse(~s(data: {"a": 1}\n\n), "")
    end

    test "the [DONE] sentinel is still filtered" do
      assert {[], ""} = Streaming.parse_sse("data: [DONE]\n\n", "")
    end

    test "parse_sse/1 still reads whole events, ignoring any partial tail" do
      assert [%{"a" => 1}] = Streaming.parse_sse(~s(data: {"a": 1}\n\ndata: {"b))
    end
  end
end
