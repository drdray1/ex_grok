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
  alias ExGrok.Options

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @allowed_opts ~w(temperature top_p max_output_tokens reasoning reasoning_effort tools tool_choice parallel_tool_calls previous_response_id store background instructions text extra_params)a

  # Options that belong to /v1/chat/completions, mapped to the Responses
  # equivalent. `Keyword.take/2` used to drop these silently, which is worse
  # than a 400 — the request succeeds and quietly ignores what you asked for.
  @chat_only_opts %{
    response_format: :text,
    max_tokens: :max_output_tokens,
    max_completion_tokens: :max_output_tokens,
    messages: :input,
    stop: nil,
    n: nil,
    search_parameters: nil,
    deferred: nil
  }

  # Output item types that represent a server-side (agentic) tool invocation.
  @server_tool_call_types ~w(web_search_call x_search_call code_execution_call code_interpreter_call collections_search_call file_search_call image_generation_call)

  @doc """
  Creates a response from a params map.

  Supported keys mirror the xAI Responses API: `"model"`, `"input"`, `"tools"`,
  `"tool_choice"`, `"reasoning"`, `"max_output_tokens"`, `"temperature"`,
  `"previous_response_id"`, `"store"`, `"instructions"`, `"text"`.

  Structured output goes under `"text"` -> `"format"`; see `json_schema_text/3`.
  A top-level `"response_format"` raises, because the API would reject it with a
  400 that does not say which library call was wrong.
  """
  @spec create(client(), map()) :: response()
  def create(client, %{} = params) do
    with :ok <- validate_params(params) do
      client
      |> Req.post(url: "/responses", json: params)
      |> Client.handle_response()
    end
  end

  @doc """
  Creates a response from a model, an `input` (a string or a list of input
  items), and options.

  ## Options
    - `:temperature`, `:top_p`, `:max_output_tokens`
    - `:reasoning` — Responses-native map, e.g. `%{"effort" => "high"}`
    - `:reasoning_effort` — convenience; wrapped into `reasoning: %{effort: ...}`
    - `:tools`, `:tool_choice`, `:parallel_tool_calls`
    - `:previous_response_id`, `:store`, `:instructions`
    - `:text` — structured output; see `json_schema_text/3`
    - `:extra_params` — a map merged verbatim into the body, for API
      parameters this client does not know about yet
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
    with :ok <- validate_params(params) do
      do_stream(client, Map.put(params, "stream", true), callback)
    end
  end

  @doc """
  Streams a response from a model, an `input`, and options — the streaming twin
  of `create/4`.

  Without this arity, streaming callers had to hand-assemble the params map,
  which is exactly the population most likely to copy the chat-completions
  structured-output shape and get a 400.
  """
  @spec stream(client(), String.t(), String.t() | list(), (map() -> any()), keyword()) ::
          :ok | {:error, term()}
  def stream(client, model, input, callback, opts \\ []) when is_function(callback, 1) do
    stream(client, build_params(model, input, opts), callback)
  end

  defp do_stream(client, params, callback) do
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
  # Stored / deferred response management
  # ===========================================================================

  @doc """
  Retrieves a stored response by id (`GET /responses/:id`).

  Works for responses created with `store: true` or `background: true`. A
  background response that is not finished yet comes back with
  `"status" => "queued"`/`"in_progress"`.
  """
  @spec get(client(), String.t()) :: response()
  def get(client, response_id) when is_binary(response_id) do
    client
    |> Req.get(url: "/responses/#{response_id}")
    |> Client.handle_response()
  end

  @doc "Deletes a stored response by id (`DELETE /responses/:id`)."
  @spec delete(client(), String.t()) :: response()
  def delete(client, response_id) when is_binary(response_id) do
    client
    |> Req.delete(url: "/responses/#{response_id}")
    |> Client.handle_response()
  end

  @doc """
  Polls `get/2` until the response reaches a terminal status.

  Returns `{:ok, response}` once `status` is `"completed"`/`"failed"`/
  `"cancelled"`, `{:error, :timeout}` if `:max_attempts` is exhausted, or any
  error from `get/2`.

  ## Options
    - `:interval_ms` — delay between polls (default `1000`)
    - `:max_attempts` — maximum polls before giving up (default `60`)
  """
  @spec poll(client(), String.t(), keyword()) :: response() | {:error, :timeout}
  def poll(client, response_id, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 1000)
    max_attempts = Keyword.get(opts, :max_attempts, 60)
    do_poll(client, response_id, interval, max_attempts)
  end

  @terminal_statuses ~w(completed failed cancelled)

  defp do_poll(_client, _id, _interval, attempts) when attempts <= 0, do: {:error, :timeout}

  defp do_poll(client, id, interval, attempts) do
    case get(client, id) do
      {:ok, body} ->
        if extract_status(body) in @terminal_statuses do
          {:ok, body}
        else
          Process.sleep(interval)
          do_poll(client, id, interval, attempts - 1)
        end

      error ->
        error
    end
  end

  @doc """
  Compacts a conversation to reduce tokens (`POST /responses/compact`).

  Accepts the same param map shape as `create/2` (`"model"`, `"input"`), and
  returns a condensed response the API can continue from.
  """
  @spec compact(client(), map()) :: response()
  def compact(client, %{} = params) do
    with :ok <- validate_params(params) do
      client
      |> Req.post(url: "/responses/compact", json: params)
      |> Client.handle_response()
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

  @doc """
  All annotation maps attached to `output_text` content items.

  Annotations carry citation metadata (e.g. `%{"type" => "url_citation",
  "url" => ..., "title" => ...}`) produced by server-side search tools.
  """
  @spec extract_annotations(map()) :: list(map())
  def extract_annotations(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(&(&1["content"] || []))
    |> Enum.filter(&(&1["type"] == "output_text"))
    |> Enum.flat_map(&(&1["annotations"] || []))
  end

  def extract_annotations(_), do: []

  @doc """
  Citation URLs gathered from `url_citation` annotations, de-duplicated in order.

  Populated when the response used `web_search`/`x_search` server-side tools.
  """
  @spec extract_citations(map()) :: list(String.t())
  def extract_citations(response) do
    response
    |> extract_annotations()
    |> Enum.filter(&(&1["type"] == "url_citation"))
    |> Enum.map(& &1["url"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Server-side tool-call output items (web search, code execution, etc.).

  These are the `*_call` items xAI adds to `output` when the model invokes an
  agentic tool on the server; distinct from client-side `function_call` items.
  """
  @spec extract_server_tool_calls(map()) :: list(map())
  def extract_server_tool_calls(%{"output" => output}) when is_list(output),
    do: Enum.filter(output, &(&1["type"] in @server_tool_call_types))

  def extract_server_tool_calls(_), do: []

  @doc """
  Decodes the response's `output_text` as JSON (for structured outputs).

  Returns `{:ok, term}` when the concatenated output text parses as JSON,
  `{:error, reason}` otherwise (including when there is no output text).
  """
  @spec extract_parsed(map()) :: {:ok, term()} | {:error, term()}
  def extract_parsed(response) do
    case extract_output_text(response) do
      nil -> {:error, :no_output_text}
      text -> Jason.decode(text)
    end
  end

  @doc "Incremental text from a streaming `response.output_text.delta` event, or nil."
  @spec delta_text(map()) :: String.t() | nil
  def delta_text(%{"type" => "response.output_text.delta", "delta" => delta})
      when is_binary(delta),
      do: delta

  def delta_text(_), do: nil

  @doc "Incremental reasoning-summary text from a streaming event, or nil."
  @spec reasoning_delta(map()) :: String.t() | nil
  def reasoning_delta(%{"type" => "response.reasoning_summary_text.delta", "delta" => delta})
      when is_binary(delta),
      do: delta

  def reasoning_delta(_), do: nil

  @doc "Incremental function-call arguments text from a streaming event, or nil."
  @spec function_call_arguments_delta(map()) :: String.t() | nil
  def function_call_arguments_delta(%{
        "type" => "response.function_call_arguments.delta",
        "delta" => delta
      })
      when is_binary(delta),
      do: delta

  def function_call_arguments_delta(_), do: nil

  @doc """
  The final, complete response object from a `response.completed` streaming
  event, or nil for any other event.
  """
  @spec completed_response(map()) :: map() | nil
  def completed_response(%{"type" => "response.completed", "response" => response})
      when is_map(response),
      do: response

  def completed_response(_), do: nil

  @doc "The `type` field of a streaming event (for routing), or nil."
  @spec event_type(map()) :: String.t() | nil
  def event_type(%{"type" => type}), do: type
  def event_type(_), do: nil

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

  @doc ~s(A text content part for multimodal input: `%{"type" => "input_text", "text" => text}`.)
  def input_text(text), do: %{"type" => "input_text", "text" => text}

  @doc """
  An image content part for multimodal input. `image_url` is a public URL or a
  `data:` URI. Extra keys (e.g. `detail: "high"`) are merged from `opts`.

      user_input([input_text("What is this?"), input_image(url, detail: "high")])
  """
  def input_image(image_url, opts \\ []) do
    opts
    |> Enum.reduce(%{"type" => "input_image", "image_url" => image_url}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), v)
    end)
  end

  # ---------------------------------------------------------------------------
  # Server-side (agentic) tool builders — pass these in `tools: [...]`.
  # ---------------------------------------------------------------------------

  @doc """
  The server-side `web_search` tool. Optional config keys (e.g.
  `allowed_domains`, `excluded_domains`, `enable_image_understanding`) are
  merged in from `opts`.

      create(client, "grok-4.5", input, tools: [web_search_tool(allowed_domains: ["x.ai"])])
  """
  def web_search_tool(opts \\ []), do: server_tool("web_search", opts)

  @doc "The server-side `x_search` tool (searches X/social). Optional config from `opts`."
  def x_search_tool(opts \\ []), do: server_tool("x_search", opts)

  @doc "The server-side `code_execution` tool (Grok-run Python). Optional config from `opts`."
  def code_execution_tool(opts \\ []), do: server_tool("code_execution", opts)

  @doc "The server-side `collections_search` tool (query uploaded documents). Optional config from `opts`."
  def collections_search_tool(opts \\ []), do: server_tool("collections_search", opts)

  @doc """
  A **remote MCP** tool entry, connecting Grok to an external MCP server.

  `server_label` and `server_url` are required; extra keys (e.g.
  `allowed_tools`, `headers`, `require_approval`) merge in from `opts`.

      create(client, "grok-4.5", input, tools: [
        mcp_tool("docs", "https://mcp.example.com/sse", allowed_tools: ["search"])
      ])
  """
  def mcp_tool(server_label, server_url, opts \\ []) do
    server_tool("mcp", [{:server_label, server_label}, {:server_url, server_url} | opts])
  end

  @doc """
  A `text.format` value requesting strict JSON-schema structured output.

  The Responses API takes this **flat** — `name`, `schema` and `strict` sit
  beside `type`. Chat completions nests the same fields under a `"json_schema"`
  key instead; `ExGrok.Chat.json_schema_format/3` builds that one. Sending
  either shape to the other endpoint is a 400.

  Usually you want `json_schema_text/3`, which wraps this for the `:text`
  option. Reach for this directly only when composing a `text` object that
  carries sibling keys alongside `"format"`.

  `opts` accepts `strict:` (default `true`) and `description:`.
  """
  def json_schema(name, schema, opts \\ []) do
    %{
      "type" => "json_schema",
      "name" => name,
      "schema" => schema,
      "strict" => Keyword.get(opts, :strict, true)
    }
    |> maybe_put_string("description", Keyword.get(opts, :description))
  end

  @doc """
  A ready-to-pass `:text` option for strict JSON-schema structured output.

      create(client, model, input, text: json_schema_text("campaign", schema))

  Exists so the `"format"` wrapper cannot be forgotten — omitting it sends
  `%{"text" => %{"type" => "json_schema", ...}}`, which is the same class of
  400 this function exists to prevent, one level down.
  """
  def json_schema_text(name, schema, opts \\ []) do
    %{"format" => json_schema(name, schema, opts)}
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp server_tool(type, opts) do
    opts
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.reduce(%{"type" => type}, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  defp build_params(model, input, opts) do
    validate_opts!(opts)

    {extra, opts} = Options.pop_extra(opts)
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
    # Merged last so an escape-hatch value wins over a built one.
    |> Map.merge(extra)
  end

  # An unknown option used to vanish inside `Keyword.take/2`. That is quieter
  # than the bug this module was fixed for: no 400, no warning, just a request
  # that silently ignores what the caller asked for. `:extra_params` keeps the
  # strictness from being a dead end when xAI ships a parameter we do not know.
  defp validate_opts!(opts) do
    Options.validate!(
      opts,
      @allowed_opts,
      @chat_only_opts,
      "the Responses API (/v1/responses)",
      %{
        response_format: Options.structured_output_hint()
      }
    )

    if Keyword.has_key?(opts, :reasoning) and Keyword.has_key?(opts, :reasoning_effort) do
      raise ArgumentError,
            "pass either :reasoning or :reasoning_effort, not both — they write the " <>
              "same \"reasoning\" key, so whichever you listed last silently wins"
    end

    :ok
  end

  # Raw params maps are the escape hatch for data that may come from config, a
  # job payload or JSON, so a bad value returns a tuple rather than raising —
  # `create/2` and friends publish `{:ok, _} | {:error, _}` and callers forward
  # external input through them.
  defp validate_params(%{} = params) do
    if Map.has_key?(params, "response_format") do
      {:error,
       {:invalid_params,
        "\"response_format\" is a /v1/chat/completions parameter and is rejected by " <>
          "/v1/responses. Put structured output under \"text\" => %{\"format\" => ...}; " <>
          "ExGrok.Responses.json_schema_text/3 builds it."}}
    else
      :ok
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  defp extract_stream_error(%{"error" => %{"message" => msg}}) when is_binary(msg), do: msg
  defp extract_stream_error(%{"error" => error}) when is_binary(error), do: error
  defp extract_stream_error(_), do: "Unknown error"
end
