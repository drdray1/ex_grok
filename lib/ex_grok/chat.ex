defmodule ExGrok.Chat do
  @moduledoc """
  xAI Grok API - Chat completion operations.

  Provides functions to create chat completions, with support for
  streaming, tool calling, and reasoning models.

  ## Examples

      client = ExGrok.Client.new("xai-your-api-key")

      # Simple completion
      {:ok, response} = ExGrok.Chat.create_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("What is 2 + 2?")
      ])
      content = ExGrok.Chat.extract_content(response)

      # With options
      {:ok, response} = ExGrok.Chat.create_completion(client, "grok-3-mini", [
        ExGrok.Chat.system_message("You are a helpful assistant."),
        ExGrok.Chat.user_message("Hello")
      ], temperature: 0.7, max_tokens: 100)

      # Streaming
      ExGrok.Chat.stream_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Tell me a story")
      ], fn chunk ->
        case ExGrok.Streaming.extract_delta_content(chunk) do
          nil -> :ok
          content -> IO.write(content)
        end
      end)
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @allowed_opts ~w(temperature top_p max_tokens max_completion_tokens stop n reasoning_effort response_format tools tool_choice parallel_tool_calls search_parameters deferred)a

  @doc """
  Creates a chat completion with a params map.

  ## Parameters

  The params map supports:

    - `"model"` - Model ID (required)
    - `"messages"` - List of message maps (required)
    - `"temperature"` - Sampling temperature (0-2)
    - `"top_p"` - Nucleus sampling parameter
    - `"max_tokens"` - Maximum tokens in response
    - `"stop"` - Stop sequences
    - `"n"` - Number of completions
    - `"reasoning_effort"` - `"low"` or `"high"` (reasoning models only)
    - `"tools"` - Tool/function definitions
    - `"tool_choice"` - Tool selection behavior
    - `"response_format"` - Structured output format

  ## Examples

      {:ok, response} = ExGrok.Chat.create_completion(client, %{
        "model" => "grok-3-mini",
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      })
  """
  @spec create_completion(client(), map()) :: response()
  def create_completion(client, %{} = params) do
    client
    |> Req.post(url: "/chat/completions", json: params)
    |> Client.handle_response()
  end

  @doc """
  Creates a chat completion with model, messages, and options.

  ## Options

    - `:temperature` - Sampling temperature (0-2)
    - `:top_p` - Nucleus sampling parameter
    - `:max_tokens` - Maximum tokens in response
    - `:stop` - Stop sequences
    - `:n` - Number of completions
    - `:reasoning_effort` - `"low"` or `"high"` (reasoning models only)
    - `:tools` - Tool/function definitions
    - `:tool_choice` - Tool selection behavior
    - `:response_format` - Structured output format

  ## Examples

      {:ok, response} = ExGrok.Chat.create_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Hello")
      ], temperature: 0.7, max_tokens: 100)
  """
  @spec create_completion(client(), String.t(), list(map()), keyword()) :: response()
  def create_completion(client, model, messages, opts \\ []) do
    params = build_params(model, messages, opts)
    create_completion(client, params)
  end

  @doc """
  Streams a chat completion, invoking the callback for each parsed SSE chunk.

  The callback receives a decoded JSON map for each streaming event.

  ## Examples

      ExGrok.Chat.stream_completion(client, %{
        "model" => "grok-3-mini",
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }, fn chunk ->
        case ExGrok.Streaming.extract_delta_content(chunk) do
          nil -> :ok
          content -> IO.write(content)
        end
      end)
  """
  @spec stream_completion(client(), map(), (map() -> any())) :: :ok | {:error, term()}
  def stream_completion(client, %{} = params, callback) when is_function(callback, 1) do
    params = Map.put(params, "stream", true)

    into_fn = fn {:data, data}, {req, resp} ->
      chunks = ExGrok.Streaming.parse_sse(data)
      Enum.each(chunks, callback)
      {:cont, {req, resp}}
    end

    case Req.post(client, url: "/chat/completions", json: params, into: into_fn) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        {:error, {:api_error, status, extract_stream_error(body)}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @doc """
  Streams a chat completion with model, messages, and callback.

  ## Examples

      ExGrok.Chat.stream_completion(client, "grok-3-mini", [
        ExGrok.Chat.user_message("Hello")
      ], fn chunk ->
        IO.inspect(chunk)
      end)
  """
  @spec stream_completion(client(), String.t(), list(map()), (map() -> any())) ::
          :ok | {:error, term()}
  def stream_completion(client, model, messages, callback)
      when is_function(callback, 1) do
    params = build_params(model, messages, [])
    stream_completion(client, params, callback)
  end

  @doc """
  Retrieves a deferred chat completion by request id.

  When a completion is created with `deferred: true`, the API returns a
  `request_id` to poll here (`GET /chat/deferred-completion/:id`). Returns
  `{:ok, completion}` when ready (HTTP 200) or `{:pending}` while still
  processing (HTTP 202).

  ## Examples

      {:ok, %{"request_id" => id}} =
        ExGrok.Chat.create_completion(client, "grok-4", messages, deferred: true)

      case ExGrok.Chat.get_deferred(client, id) do
        {:ok, completion} -> ExGrok.Chat.extract_content(completion)
        {:pending} -> :not_ready_yet
      end
  """
  @spec get_deferred(client(), String.t()) :: {:ok, map()} | {:pending} | {:error, term()}
  def get_deferred(client, request_id) when is_binary(request_id) do
    case Req.get(client, url: "/chat/deferred-completion/#{request_id}") do
      {:ok, %Req.Response{status: 202}} -> {:pending}
      result -> Client.handle_response(result)
    end
  end

  # ===========================================================================
  # Extract Helpers
  # ===========================================================================

  @doc """
  Extracts the content from the first choice's message.

  ## Examples

      iex> extract_content(%{"choices" => [%{"message" => %{"content" => "Hello"}}]})
      "Hello"
  """
  @spec extract_content(map()) :: String.t() | nil
  def extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}), do: content
  def extract_content(_), do: nil

  @doc """
  Extracts tool calls from the first choice's message.

  ## Examples

      iex> extract_tool_calls(%{"choices" => [%{"message" => %{"tool_calls" => [...]}}]})
      [%{"id" => "...", "function" => %{...}}]
  """
  @spec extract_tool_calls(map()) :: list(map())
  def extract_tool_calls(%{"choices" => [%{"message" => %{"tool_calls" => calls}} | _]})
      when is_list(calls),
      do: calls

  def extract_tool_calls(_), do: []

  @doc """
  Extracts usage statistics from the response.

  ## Examples

      iex> extract_usage(%{"usage" => %{"total_tokens" => 30}})
      %{"total_tokens" => 30, ...}
  """
  @spec extract_usage(map()) :: map() | nil
  def extract_usage(%{"usage" => usage}) when is_map(usage), do: usage
  def extract_usage(_), do: nil

  @doc """
  Extracts reasoning content from the first choice's message.

  Only available with reasoning models (e.g., grok-3-mini with reasoning_effort).

  ## Examples

      iex> extract_reasoning_content(%{"choices" => [%{"message" => %{"reasoning_content" => "..."}}]})
      "..."
  """
  @spec extract_reasoning_content(map()) :: String.t() | nil
  def extract_reasoning_content(%{
        "choices" => [%{"message" => %{"reasoning_content" => content}} | _]
      }),
      do: content

  def extract_reasoning_content(_), do: nil

  @doc """
  Extracts the finish reason from the first choice.
  """
  @spec extract_finish_reason(map()) :: String.t() | nil
  def extract_finish_reason(%{"choices" => [%{"finish_reason" => reason} | _]}), do: reason
  def extract_finish_reason(_), do: nil

  # ===========================================================================
  # Message Builders
  # ===========================================================================

  @doc """
  Builds a user message map.

  ## Examples

      iex> user_message("Hello")
      %{"role" => "user", "content" => "Hello"}
  """
  @spec user_message(String.t()) :: map()
  def user_message(content), do: %{"role" => "user", "content" => content}

  @doc """
  Builds a system message map.

  ## Examples

      iex> system_message("You are a helpful assistant.")
      %{"role" => "system", "content" => "You are a helpful assistant."}
  """
  @spec system_message(String.t()) :: map()
  def system_message(content), do: %{"role" => "system", "content" => content}

  @doc """
  Builds an assistant message map.

  ## Examples

      iex> assistant_message("I can help with that.")
      %{"role" => "assistant", "content" => "I can help with that."}
  """
  @spec assistant_message(String.t()) :: map()
  def assistant_message(content), do: %{"role" => "assistant", "content" => content}

  @doc """
  Builds a tool result message map.

  ## Examples

      iex> tool_result_message("call_123", "72°F and sunny")
      %{"role" => "tool", "tool_call_id" => "call_123", "content" => "72°F and sunny"}
  """
  @spec tool_result_message(String.t(), String.t()) :: map()
  def tool_result_message(tool_call_id, content) do
    %{"role" => "tool", "tool_call_id" => tool_call_id, "content" => content}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp build_params(model, messages, opts) do
    base = %{"model" => model, "messages" => messages}

    opts
    |> Keyword.take(@allowed_opts)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.reduce(base, fn {key, value}, acc ->
      Map.put(acc, Atom.to_string(key), value)
    end)
  end

  defp extract_stream_error(body) when is_map(body) do
    case body do
      %{"error" => %{"message" => msg}} -> msg
      %{"error" => error} when is_binary(error) -> error
      _ -> "Unknown error"
    end
  end

  defp extract_stream_error(_), do: "Unknown error"
end
