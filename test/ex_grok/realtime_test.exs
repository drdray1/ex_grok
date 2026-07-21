defmodule ExGrok.RealtimeTest do
  use ExUnit.Case, async: true

  alias ExGrok.Realtime

  describe "client event builders" do
    test "session_update wraps the config" do
      cfg = %{"voice" => "eve", "turn_detection" => %{"type" => "server_vad"}}
      assert Realtime.session_update(cfg) == %{"type" => "session.update", "session" => cfg}
    end

    test "append_audio_event base64-encodes the PCM bytes" do
      event = Realtime.append_audio_event("rawpcm")
      assert event["type"] == "input_audio_buffer.append"
      assert Base.decode64!(event["audio"]) == "rawpcm"
    end

    test "commit_event" do
      assert Realtime.commit_event() == %{"type" => "input_audio_buffer.commit"}
    end

    test "create_response_event with and without config" do
      assert Realtime.create_response_event() == %{"type" => "response.create"}

      assert Realtime.create_response_event(%{"modalities" => ["audio"]}) == %{
               "type" => "response.create",
               "response" => %{"modalities" => ["audio"]}
             }
    end

    test "text_item builds a user message item" do
      event = Realtime.text_item("hello")
      assert event["type"] == "conversation.item.create"
      assert event["item"]["role"] == "user"
      assert event["item"]["content"] == [%{"type" => "input_text", "text" => "hello"}]
    end

    test "function_call_output builds a tool-result item" do
      event = Realtime.function_call_output("call_1", "72F")
      assert event["item"]["type"] == "function_call_output"
      assert event["item"]["call_id"] == "call_1"
      assert event["item"]["output"] == "72F"
    end
  end

  describe "encode/parse round-trip" do
    test "encode produces JSON that parse_event decodes back" do
      event = Realtime.session_update(%{"voice" => "eve"})
      json = Realtime.encode(event)
      assert is_binary(json)
      assert {:ok, ^event} = Realtime.parse_event(json)
    end

    test "parse_event passes a map through unchanged" do
      assert {:ok, %{"type" => "x"}} = Realtime.parse_event(%{"type" => "x"})
    end

    test "parse_event returns an error for invalid JSON" do
      assert {:error, _} = Realtime.parse_event("{not json")
    end
  end

  describe "server event helpers" do
    test "audio_delta extracts base64 audio only from the audio delta event" do
      assert Realtime.audio_delta(%{
               "type" => "response.output_audio.delta",
               "delta" => "QUJD"
             }) == "QUJD"

      assert Realtime.audio_delta(%{"type" => "response.done"}) == nil
      assert Realtime.audio_delta(%{}) == nil
    end

    test "event_type reads the type or nil" do
      assert Realtime.event_type(%{"type" => "response.done"}) == "response.done"
      assert Realtime.event_type(%{}) == nil
    end
  end
end
