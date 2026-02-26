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
end
