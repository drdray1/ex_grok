defmodule ExGrok.Fixtures do
  @moduledoc """
  Test fixtures for ExGrok API testing.
  """

  # ===========================================================================
  # Credentials
  # ===========================================================================

  def sample_api_key, do: "xai-test-api-key-123"

  # ===========================================================================
  # Test Client Factory
  # ===========================================================================

  def test_client(stub_name) do
    sample_api_key()
    |> ExGrok.Client.new(plug: {Req.Test, stub_name})
    |> Req.Request.merge_options(retry: false)
  end

  def test_management_client(stub_name) do
    "xai-mgmt-test-key"
    |> ExGrok.Client.management_client(plug: {Req.Test, stub_name})
    |> Req.Request.merge_options(retry: false)
  end

  # ===========================================================================
  # Chat Completion Responses
  # ===========================================================================

  def sample_chat_completion_response do
    %{
      "id" => "chatcmpl-test-123",
      "object" => "chat.completion",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => "The meaning of life is a complex philosophical question."
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 20,
        "total_tokens" => 30
      },
      "system_fingerprint" => "fp_test123"
    }
  end

  def sample_chat_completion_with_tool_calls do
    %{
      "id" => "chatcmpl-tool-123",
      "object" => "chat.completion",
      "created" => 1_234_567_890,
      "model" => "grok-3",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call_abc123",
                "type" => "function",
                "function" => %{
                  "name" => "get_weather",
                  "arguments" => Jason.encode!(%{"location" => "San Francisco"})
                }
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 15,
        "completion_tokens" => 25,
        "total_tokens" => 40
      }
    }
  end

  def sample_chat_completion_with_reasoning do
    %{
      "id" => "chatcmpl-reason-123",
      "object" => "chat.completion",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => "42",
            "reasoning_content" => "Let me think about this step by step..."
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 50,
        "total_tokens" => 60
      }
    }
  end

  def sample_chat_completion_multi_choice do
    %{
      "id" => "chatcmpl-multi-123",
      "object" => "chat.completion",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => "Response A"},
          "finish_reason" => "stop"
        },
        %{
          "index" => 1,
          "message" => %{"role" => "assistant", "content" => "Response B"},
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 10,
        "completion_tokens" => 40,
        "total_tokens" => 50
      }
    }
  end

  # ===========================================================================
  # Streaming Fixtures
  # ===========================================================================

  def sample_stream_chunk_role do
    %{
      "id" => "chatcmpl-stream",
      "object" => "chat.completion.chunk",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{"delta" => %{"role" => "assistant"}, "index" => 0, "finish_reason" => nil}
      ]
    }
  end

  def sample_stream_chunk_content(content) do
    %{
      "id" => "chatcmpl-stream",
      "object" => "chat.completion.chunk",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{"delta" => %{"content" => content}, "index" => 0, "finish_reason" => nil}
      ]
    }
  end

  def sample_stream_chunk_done do
    %{
      "id" => "chatcmpl-stream",
      "object" => "chat.completion.chunk",
      "created" => 1_234_567_890,
      "model" => "grok-3-mini",
      "choices" => [
        %{"delta" => %{}, "index" => 0, "finish_reason" => "stop"}
      ]
    }
  end

  def sample_sse_data do
    [
      "data: #{Jason.encode!(sample_stream_chunk_role())}\n\n",
      "data: #{Jason.encode!(sample_stream_chunk_content("Hello"))}\n\n",
      "data: #{Jason.encode!(sample_stream_chunk_content(" world"))}\n\n",
      "data: #{Jason.encode!(sample_stream_chunk_done())}\n\n",
      "data: [DONE]\n\n"
    ]
    |> Enum.join()
  end

  # ===========================================================================
  # Responses API (/v1/responses)
  # ===========================================================================

  def sample_response_text do
    %{
      "id" => "resp-test-123",
      "object" => "response",
      "model" => "grok-4.5",
      "status" => "completed",
      "output" => [
        %{
          "type" => "reasoning",
          "id" => "rs_1",
          "status" => "completed",
          "summary" => [%{"type" => "summary_text", "text" => "Thinking it through..."}]
        },
        %{
          "type" => "message",
          "id" => "msg_1",
          "role" => "assistant",
          "status" => "completed",
          "content" => [%{"type" => "output_text", "text" => "Hello there", "annotations" => []}]
        }
      ],
      "usage" => %{"input_tokens" => 10, "output_tokens" => 20, "total_tokens" => 30}
    }
  end

  def sample_response_function_call do
    %{
      "id" => "resp-tool-123",
      "object" => "response",
      "model" => "grok-4.5",
      "status" => "completed",
      "output" => [
        %{"type" => "reasoning", "id" => "rs_2", "status" => "completed", "summary" => []},
        %{
          "type" => "function_call",
          "id" => "fc_1",
          "call_id" => "call_abc123",
          "name" => "get_weather",
          "arguments" => Jason.encode!(%{"location" => "San Francisco"})
        }
      ],
      "usage" => %{"input_tokens" => 15, "output_tokens" => 25, "total_tokens" => 40}
    }
  end

  def sample_response_sse_data do
    [
      ~s(data: {"type":"response.output_text.delta","delta":"Hello"}\n\n),
      ~s(data: {"type":"response.output_text.delta","delta":" world"}\n\n),
      ~s(data: {"type":"response.completed","response":{"id":"resp-1"}}\n\n)
    ]
    |> Enum.join()
  end

  # A response produced with the web_search server-side tool: it carries a
  # server tool-call output item plus url_citation annotations on the message.
  def sample_response_with_citations do
    %{
      "id" => "resp-search-1",
      "object" => "response",
      "model" => "grok-4.5",
      "status" => "completed",
      "output" => [
        %{"type" => "web_search_call", "id" => "ws_1", "status" => "completed"},
        %{
          "type" => "message",
          "id" => "msg_1",
          "role" => "assistant",
          "status" => "completed",
          "content" => [
            %{
              "type" => "output_text",
              "text" => "xAI ships Grok.",
              "annotations" => [
                %{"type" => "url_citation", "url" => "https://x.ai", "title" => "xAI"},
                %{"type" => "url_citation", "url" => "https://docs.x.ai", "title" => "Docs"},
                %{"type" => "url_citation", "url" => "https://x.ai", "title" => "dup"}
              ]
            }
          ]
        }
      ],
      "usage" => %{
        "input_tokens" => 20,
        "output_tokens" => 40,
        "total_tokens" => 60,
        "num_sources_used" => 3,
        "num_server_side_tools_used" => 1
      }
    }
  end

  # A structured-output response: output_text is a JSON document.
  def sample_response_structured do
    %{
      "id" => "resp-json-1",
      "object" => "response",
      "model" => "grok-4.5",
      "status" => "completed",
      "output" => [
        %{
          "type" => "message",
          "id" => "msg_1",
          "role" => "assistant",
          "status" => "completed",
          "content" => [
            %{
              "type" => "output_text",
              "text" => ~s({"city":"Tokyo","temp_c":18}),
              "annotations" => []
            }
          ]
        }
      ],
      "usage" => %{"input_tokens" => 12, "output_tokens" => 9, "total_tokens" => 21}
    }
  end

  # A queued background response (before completion).
  def sample_response_background_queued do
    %{
      "id" => "resp-bg-1",
      "object" => "response",
      "model" => "grok-4.5",
      "status" => "queued",
      "output" => [],
      "usage" => nil
    }
  end

  # Detailed usage mirroring the real grok-4.5 /responses payload.
  def sample_response_usage_detailed do
    %{
      "input_tokens" => 231,
      "input_tokens_details" => %{"cached_tokens" => 128},
      "output_tokens" => 957,
      "output_tokens_details" => %{"reasoning_tokens" => 594},
      "total_tokens" => 1188,
      "num_sources_used" => 0,
      "num_server_side_tools_used" => 0,
      "cost_in_usd_ticks" => 59_864_000
    }
  end

  # Full Responses SSE stream: reasoning delta, text delta, tool-arg delta, completed.
  def sample_response_sse_full do
    [
      ~s(data: {"type":"response.reasoning_summary_text.delta","delta":"Let me think"}\n\n),
      ~s(data: {"type":"response.output_text.delta","delta":"Answer"}\n\n),
      ~s(data: {"type":"response.function_call_arguments.delta","delta":"{\\"a\\":1}"}\n\n),
      ~s(data: {"type":"response.completed","response":{"id":"resp-9","status":"completed"}}\n\n)
    ]
    |> Enum.join()
  end

  # ===========================================================================
  # Models Responses
  # ===========================================================================

  def sample_models_response do
    %{
      "object" => "list",
      "data" => [
        %{
          "id" => "grok-3",
          "object" => "model",
          "created" => 1_234_567_890,
          "owned_by" => "xai"
        },
        %{
          "id" => "grok-3-mini",
          "object" => "model",
          "created" => 1_234_567_890,
          "owned_by" => "xai"
        },
        %{
          "id" => "grok-4-fast",
          "object" => "model",
          "created" => 1_234_567_890,
          "owned_by" => "xai"
        }
      ]
    }
  end

  def sample_model_response do
    %{
      "id" => "grok-3-mini",
      "object" => "model",
      "created" => 1_234_567_890,
      "owned_by" => "xai"
    }
  end

  # ===========================================================================
  # Image Responses
  # ===========================================================================

  def sample_image_generation_response do
    %{
      "created" => 1_234_567_890,
      "data" => [
        %{
          "url" => "https://example.com/generated-image.png",
          "revised_prompt" => "A beautiful sunset over the ocean"
        }
      ]
    }
  end

  def sample_image_b64_response do
    %{
      "created" => 1_234_567_890,
      "data" => [
        %{
          "b64_json" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ",
          "revised_prompt" => "A red pixel"
        }
      ]
    }
  end

  def sample_image_edit_response do
    %{
      "created" => 1_234_567_890,
      "data" => [
        %{
          "url" => "https://example.com/edited-image.png",
          "revised_prompt" => "An edited image"
        }
      ]
    }
  end

  # ===========================================================================
  # Error Responses
  # ===========================================================================

  def sample_error_response do
    %{
      "error" => %{
        "message" => "Invalid API key provided",
        "type" => "authentication_error",
        "code" => "invalid_api_key"
      }
    }
  end

  def sample_rate_limit_error do
    %{
      "error" => %{
        "message" => "Rate limit exceeded",
        "type" => "rate_limit_error",
        "code" => "rate_limit_exceeded"
      }
    }
  end

  def sample_bad_request_error do
    %{
      "error" => %{
        "message" => "Invalid model specified",
        "type" => "invalid_request_error",
        "code" => "model_not_found"
      }
    }
  end

  # ===========================================================================
  # Video / Audio / Files / Collections / api-key (Wave 2)
  # ===========================================================================

  def sample_video_accepted, do: %{"request_id" => "vid-req-1", "status" => "pending"}

  def sample_video_pending do
    %{"request_id" => "vid-req-1", "status" => "pending", "model" => "grok-imagine-video"}
  end

  def sample_video_done do
    %{
      "request_id" => "vid-req-1",
      "status" => "done",
      "model" => "grok-imagine-video",
      "video" => %{"url" => "https://vidgen.x.ai/abc/video.mp4", "duration" => 8}
    }
  end

  def sample_tts_timestamps do
    %{
      "audio" => Base.encode64("fake-audio-bytes"),
      "content_type" => "audio/mpeg",
      "duration" => 0.92,
      "audio_timestamps" => %{"graph_chars" => ["H", "i"], "graph_times" => [[0.0, 0.1]]}
    }
  end

  def sample_voices, do: %{"voices" => [%{"voice_id" => "eve", "name" => "Eve"}]}

  def sample_transcript, do: %{"text" => "hello world", "language" => "en"}

  def sample_file do
    %{
      "id" => "file-abc123",
      "object" => "file",
      "filename" => "report.pdf",
      "bytes" => 12_345,
      "purpose" => "collections",
      "created_at" => 1_784_600_000
    }
  end

  def sample_files_list, do: %{"data" => [sample_file()]}

  def sample_collection do
    %{
      "collection_id" => "coll-xyz",
      "collection_name" => "SEC Filings",
      "field_definitions" => []
    }
  end

  def sample_search_results do
    %{
      "results" => [
        %{"file_id" => "file-abc123", "score" => 0.91, "text" => "revenue guidance ..."}
      ]
    }
  end

  def sample_api_key_info do
    %{
      "api_key_id" => "key-123",
      "name" => "default",
      "team_id" => "team-9",
      "acls" => ["api-key:model:*"]
    }
  end
end
