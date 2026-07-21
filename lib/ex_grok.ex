defmodule ExGrok do
  @moduledoc """
  Elixir client for the xAI Grok API.

  Provides a unified interface for chat completions, model listing,
  and image generation using Grok models.

  ## Quick Start

      client = ExGrok.new("xai-your-api-key")

      {:ok, response} = ExGrok.create_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("What is the meaning of life?")
      ])

      content = ExGrok.extract_content(response)

  ## Streaming

      ExGrok.stream_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Tell me a story")
      ], fn chunk ->
        case ExGrok.Streaming.extract_delta_content(chunk) do
          nil -> :ok
          content -> IO.write(content)
        end
      end)

  ## Configuration

  All configuration is optional — sensible defaults are provided:

      config :ex_grok,
        config: [
          base_url: "https://api.x.ai/v1",
          timeout: 120_000
        ]
  """

  alias ExGrok.{Chat, Client, Images, Models, Responses}

  # ============================================================================
  # Client
  # ============================================================================

  @doc """
  Creates a new Grok API client with authentication.

  ## Options

    - `:plug` - Test plug for `Req.Test` (default: nil)

  ## Examples

      client = ExGrok.new("xai-your-api-key")
  """
  def new(api_key, opts \\ []) do
    Client.new(api_key, opts)
  end

  @doc "Verifies API credentials by making a test request."
  defdelegate verify_credentials(api_key), to: Client

  @doc "Performs a health check on the client connection."
  defdelegate healthcheck(client), to: Client

  # ============================================================================
  # Chat Completions
  # ============================================================================

  @doc "Creates a chat completion with a params map."
  defdelegate create_completion(client, params), to: Chat

  @doc """
  Creates a chat completion with model, messages, and options.

  ## Examples

      {:ok, resp} = ExGrok.create_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Hello")
      ], temperature: 0.7)
  """
  def create_completion(client, model, messages, opts \\ []) do
    Chat.create_completion(client, model, messages, opts)
  end

  @doc "Streams a chat completion with a params map and callback."
  defdelegate stream_completion(client, params, callback), to: Chat

  @doc """
  Streams a chat completion with model, messages, and callback.

  ## Examples

      ExGrok.stream_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Hello")
      ], fn chunk -> IO.inspect(chunk) end)
  """
  defdelegate stream_completion(client, model, messages, callback), to: Chat

  @doc "Extracts content from the first choice's message."
  defdelegate extract_content(response), to: Chat

  @doc "Extracts tool calls from the first choice's message."
  defdelegate extract_tool_calls(response), to: Chat

  @doc "Extracts usage statistics from the response."
  defdelegate extract_usage(response), to: Chat

  @doc "Extracts reasoning content from the response."
  defdelegate extract_reasoning_content(response), to: Chat

  @doc "Extracts finish reason from the first choice."
  defdelegate extract_finish_reason(response), to: Chat

  # Message helpers

  @doc "Builds a user message map."
  defdelegate user_message(content), to: Chat

  @doc "Builds a system message map."
  defdelegate system_message(content), to: Chat

  @doc "Builds an assistant message map."
  defdelegate assistant_message(content), to: Chat

  @doc "Builds a tool result message map."
  defdelegate tool_result_message(tool_call_id, content), to: Chat

  # ============================================================================
  # Responses API (/v1/responses)
  # ============================================================================

  @doc "Creates a response via the Responses API with a params map."
  defdelegate create_response(client, params), to: Responses, as: :create

  @doc "Creates a response via the Responses API with model, input, and options."
  def create_response(client, model, input, opts \\ []) do
    Responses.create(client, model, input, opts)
  end

  @doc "Streams a response via the Responses API."
  defdelegate stream_response(client, params, callback), to: Responses, as: :stream

  @doc "Extracts concatenated output text from a Responses API response."
  defdelegate extract_output_text(response), to: Responses

  @doc "Extracts function-call items from a Responses API response."
  defdelegate extract_function_calls(response), to: Responses

  @doc "Extracts the raw output items from a Responses API response."
  defdelegate extract_output_items(response), to: Responses

  # ============================================================================
  # Models
  # ============================================================================

  @doc "Lists all available models."
  defdelegate list_models(client), to: Models

  @doc "Retrieves a single model by ID."
  defdelegate get_model(client, model_id), to: Models

  @doc "Extracts models list from response."
  defdelegate extract_models(response), to: Models

  @doc "Extracts model ID strings from response."
  defdelegate extract_model_ids(response), to: Models

  # ============================================================================
  # Images
  # ============================================================================

  @doc "Generates images from a text prompt."
  def generate_image(client, prompt, opts \\ []) do
    Images.generate(client, prompt, opts)
  end

  @doc "Edits an image based on a text prompt."
  def edit_image(client, prompt, opts \\ []) do
    Images.edit(client, prompt, opts)
  end

  @doc "Extracts image data from response."
  defdelegate extract_images(response), to: Images

  @doc "Extracts image URLs from response."
  defdelegate extract_image_urls(response), to: Images
end
