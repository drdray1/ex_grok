defmodule ExGrok.Responses do
  @moduledoc """
  xAI Grok **Responses API** (`/v1/responses`) operations.

  The Responses API is xAI's newer, agent-oriented interface. Unlike
  `ExGrok.Chat` (`/v1/chat/completions`), it takes an `input` list of items and
  returns a top-level `output` list of typed items (`reasoning`, `message`,
  `function_call`), with first-class support for reasoning models and multi-turn
  tool calling.

  ## Basic usage

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", [
        ExGrok.Responses.system_input("You are a helpful assistant."),
        ExGrok.Responses.user_input("What is 2 + 2?")
      ])

      ExGrok.Responses.extract_output_text(resp)
      # => "4"

  ## Tool calling (stateless full-input replay)

      tools = [ExGrok.Responses.function_tool("get_weather", "Get weather", schema)]

      {:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", input, tools: tools)

      case ExGrok.Responses.extract_function_calls(resp) do
        [] ->
          ExGrok.Responses.extract_output_text(resp)

        calls ->
          # execute each call locally, then continue by re-sending the input plus
          # the model's own output items and a function_call_output per call:
          outputs = Enum.map(calls, fn c ->
            ExGrok.Responses.function_call_output(c["call_id"], run(c))
          end)

          new_input = input ++ ExGrok.Responses.extract_output_items(resp) ++ outputs
          ExGrok.Responses.create(client, "grok-4.5", new_input, tools: tools)
      end
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @allowed_opts ~w(temperature top_p max_output_tokens reasoning reasoning_effort tools tool_choice parallel_tool_calls previous_response_id store instructions response_format)a

  @doc """
  Creates a response from a params map.

  Supported keys mirror the xAI Responses API: `"model"`, `"input"`, `"tools"`,
  `"tool_choice"`, `"reasoning"`, `"max_output_tokens"`, `"temperature"`,
  `"previous_response_id"`, `"store"`, `"instructions"`.
  """
  @spec create(client(), map()) :: response()
  def create(client, %{} = params) do
    client
    |> Req.post(url: "/responses", json: params)
    |> Client.handle_response()
  end

  @doc """
  Creates a response from a model, an `input` (a string or a list of input
  items), and options.

  ## Options
    - `:temperature`, `:top_p`, `:max_output_tokens`
    - `:reasoning` — Responses-native map, e.g. `%{"effort" => "high"}`
    - `:reasoning_effort` — convenience; wrapped into `reasoning: %{effort: ...}`
    - `:tools`, `:tool_choice`, `:parallel_tool_calls`
    - `:previous_response_id`, `:store`, `:instructions`, `:response_format`
  """
  @spec create(client(), String.t(), String.t() | list(), keyword()) :: response()
  def create(client, model, input, opts \\ []) do
    create(client, build_params(model, input, opts))
  end

  @doc """
  Streams a response, invoking `callback` for each decoded SSE event map.

  Streaming event `type` values follow the Responses API convention (e.g.
  `"response.output_text.delta"`); use `delta_text/1` to pull incremental text.
  """
  @spec stream(client(), map(), (map() -> any())) :: :ok | {:error, term()}
  def stream(client, %{} = params, callback) when is_function(callback, 1) do
    params = Map.put(params, "stream", true)

    into_fn = fn {:data, data}, {req, resp} ->
      data
      |> ExGrok.Streaming.parse_sse()
      |> Enum.each(callback)

      {:cont, {req, resp}}
    end

    case Req.post(client, url: "/responses", json: params, into: into_fn) do
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

  # ===========================================================================
  # Extract helpers (operate on the decoded response body)
  # ===========================================================================

  @doc "Concatenated `output_text` from all `message` items, or nil."
  @spec extract_output_text(map()) :: String.t() | nil
  def extract_output_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(&(&1["content"] || []))
    |> Enum.filter(&(&1["type"] == "output_text"))
    |> Enum.map_join("", & &1["text"])
    |> blank_to_nil()
  end

  def extract_output_text(_), do: nil

  @doc "The `function_call` output items (each `%{\"call_id\", \"name\", \"arguments\"}`)."
  @spec extract_function_calls(map()) :: list(map())
  def extract_function_calls(%{"output" => output}) when is_list(output),
    do: Enum.filter(output, &(&1["type"] == "function_call"))

  def extract_function_calls(_), do: []

  @doc "Concatenated reasoning `summary` text, or nil (reasoning models only)."
  @spec extract_reasoning(map()) :: String.t() | nil
  def extract_reasoning(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "reasoning"))
    |> Enum.flat_map(&(&1["summary"] || []))
    |> Enum.map_join("\n", & &1["text"])
    |> blank_to_nil()
  end

  def extract_reasoning(_), do: nil

  @doc "The raw `output` list of items (for stateless tool-call continuation)."
  @spec extract_output_items(map()) :: list(map())
  def extract_output_items(%{"output" => output}) when is_list(output), do: output
  def extract_output_items(_), do: []

  @doc "Usage stats map, or nil."
  @spec extract_usage(map()) :: map() | nil
  def extract_usage(%{"usage" => usage}) when is_map(usage), do: usage
  def extract_usage(_), do: nil

  @doc "The response id (for `previous_response_id` chaining), or nil."
  @spec extract_response_id(map()) :: String.t() | nil
  def extract_response_id(%{"id" => id}) when is_binary(id), do: id
  def extract_response_id(_), do: nil

  @doc "The response status (e.g. `\"completed\"`), or nil."
  @spec extract_status(map()) :: String.t() | nil
  def extract_status(%{"status" => status}), do: status
  def extract_status(_), do: nil

  @doc "Incremental text from a streaming `response.output_text.delta` event, or nil."
  @spec delta_text(map()) :: String.t() | nil
  def delta_text(%{"type" => "response.output_text.delta", "delta" => delta})
      when is_binary(delta),
      do: delta

  def delta_text(_), do: nil

  # ===========================================================================
  # Input item + tool builders
  # ===========================================================================

  @doc ~s(A user input item: `%{"role" => "user", "content" => content}`.)
  def user_input(content), do: %{"role" => "user", "content" => content}

  @doc ~s(A system input item: `%{"role" => "system", "content" => content}`.)
  def system_input(content), do: %{"role" => "system", "content" => content}

  @doc ~s(An assistant input item: `%{"role" => "assistant", "content" => content}`.)
  def assistant_input(content), do: %{"role" => "assistant", "content" => content}

  @doc """
  A tool-result input item to return a function's output to the model:
  `%{"type" => "function_call_output", "call_id" => call_id, "output" => output}`.
  """
  def function_call_output(call_id, output),
    do: %{"type" => "function_call_output", "call_id" => call_id, "output" => output}

  @doc """
  A function tool definition in the Responses API's **flat** shape:
  `%{"type" => "function", "name" => ..., "description" => ..., "parameters" => ...}`.
  """
  def function_tool(name, description, parameters) do
    %{
      "type" => "function",
      "name" => name,
      "description" => description,
      "parameters" => parameters
    }
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp build_params(model, input, opts) do
    base = %{"model" => model, "input" => input}

    opts
    |> Keyword.take(@allowed_opts)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.reduce(base, fn
      {:reasoning_effort, effort}, acc ->
        Map.put(acc, "reasoning", %{"effort" => to_string(effort)})

      {key, value}, acc ->
        Map.put(acc, Atom.to_string(key), value)
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  defp extract_stream_error(%{"error" => %{"message" => msg}}) when is_binary(msg), do: msg
  defp extract_stream_error(%{"error" => error}) when is_binary(error), do: error
  defp extract_stream_error(_), do: "Unknown error"
end
