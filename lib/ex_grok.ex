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

  alias ExGrok.{Audio, Chat, Client, Collections, Files, Images, Models, Responses, Video}

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

  @doc "Creates a client for xAI's Management API (collections management)."
  defdelegate management_client(management_api_key), to: Client

  @doc "Verifies API credentials by making a test request."
  defdelegate verify_credentials(api_key), to: Client

  @doc "Performs a health check on the client connection."
  defdelegate healthcheck(client), to: Client

  @doc "Fetches metadata about the API key in use (account/access info)."
  defdelegate api_key_info(client), to: Client

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

  @doc "Extracts the reasoning summary text from a Responses API response."
  defdelegate extract_reasoning(response), to: Responses

  @doc "Extracts server-side search citation URLs from a Responses API response."
  defdelegate extract_citations(response), to: Responses

  @doc "Extracts server-side tool-call output items from a Responses API response."
  defdelegate extract_server_tool_calls(response), to: Responses

  @doc "Decodes a Responses API structured output as JSON."
  defdelegate extract_parsed(response), to: Responses

  @doc "Builds a remote MCP tool entry for a Responses tools array."
  defdelegate mcp_tool(server_label, server_url), to: Responses

  @doc "Retrieves a stored/background response by id."
  defdelegate get_response(client, response_id), to: Responses, as: :get

  @doc "Deletes a stored response by id."
  defdelegate delete_response(client, response_id), to: Responses, as: :delete

  @doc "Polls a background response by id until it reaches a terminal status."
  def poll_response(client, response_id, opts \\ []) do
    Responses.poll(client, response_id, opts)
  end

  # ============================================================================
  # Usage
  # ============================================================================

  @doc "Input/prompt token count from a response's usage."
  defdelegate usage_input_tokens(source), to: ExGrok.Usage, as: :input_tokens

  @doc "Output/completion token count from a response's usage."
  defdelegate usage_output_tokens(source), to: ExGrok.Usage, as: :output_tokens

  @doc "Total token count from a response's usage."
  defdelegate usage_total_tokens(source), to: ExGrok.Usage, as: :total_tokens

  @doc "Reasoning token count from a response's usage."
  defdelegate usage_reasoning_tokens(source), to: ExGrok.Usage, as: :reasoning_tokens

  @doc "Cached input token count from a response's usage."
  defdelegate usage_cached_tokens(source), to: ExGrok.Usage, as: :cached_tokens

  @doc "Response cost in USD from a response's usage."
  defdelegate usage_cost_usd(source), to: ExGrok.Usage, as: :cost_usd

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

  # ============================================================================
  # Video
  # ============================================================================

  @doc "Starts an async video generation job; returns a request id."
  def generate_video(client, prompt, opts \\ []) do
    Video.generate(client, prompt, opts)
  end

  @doc "Retrieves a video job by id."
  defdelegate get_video(client, request_id), to: Video, as: :get

  @doc "Polls a video job by id until it reaches a terminal status."
  def poll_video(client, request_id, opts \\ []) do
    Video.poll(client, request_id, opts)
  end

  @doc "Extracts the generated video URL from a video job."
  defdelegate extract_video_url(job), to: Video

  # ============================================================================
  # Audio
  # ============================================================================

  @doc "Synthesizes speech (text-to-speech); returns audio bytes."
  def speech(client, text, opts \\ []) do
    Audio.speech(client, text, opts)
  end

  @doc "Transcribes audio to text (speech-to-text)."
  def transcribe(client, source, opts \\ []) do
    Audio.transcribe(client, source, opts)
  end

  @doc "Lists available text-to-speech voices."
  defdelegate list_voices(client), to: Audio, as: :voices

  @doc "Extracts the transcript text from an STT response."
  defdelegate extract_transcript(response), to: Audio

  # ============================================================================
  # Files & Collections
  # ============================================================================

  @doc "Uploads a file to the Files API."
  def upload_file(client, source, opts \\ []) do
    Files.upload(client, source, opts)
  end

  @doc "Lists uploaded files."
  defdelegate list_files(client), to: Files, as: :list

  @doc "Deletes an uploaded file by id."
  defdelegate delete_file(client, file_id), to: Files, as: :delete

  @doc "Extracts the file id from a Files API response."
  defdelegate extract_file_id(response), to: Files

  @doc "Creates a collection (requires a management client)."
  def create_collection(mgmt_client, name, opts \\ []) do
    Collections.create(mgmt_client, name, opts)
  end

  @doc "Adds an uploaded file to a collection (requires a management client)."
  defdelegate add_document_to_collection(mgmt_client, collection_id, file_id),
    to: Collections,
    as: :add_document

  @doc "Searches documents across collections (normal client)."
  def search_collection(client, query, opts \\ []) do
    Collections.search(client, query, opts)
  end

  @doc "Extracts the collection id from a Collections API response."
  defdelegate extract_collection_id(response), to: Collections
end
