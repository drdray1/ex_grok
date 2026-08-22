# ExGrok

Elixir client for the [xAI Grok API](https://docs.x.ai/).

Covers the full xAI surface: chat completions, the agentic Responses API (server-side + MCP tools, structured output, vision, stateful/background), image and video generation, audio (TTS/STT), the realtime Voice Agent (WebSocket), Files & Collections storage, models, and per-request usage/cost stats.

## Installation

```elixir
def deps do
  [
    {:ex_grok, git: "https://github.com/drdray1/ex_grok.git", tag: "0.6.2"}
  ]
end
```

## Quick Start

```elixir
# Create a client
client = ExGrok.new("xai-your-api-key")

# Chat completion
{:ok, response} = ExGrok.create_completion(client, "grok-3-mini", [
  ExGrok.Chat.user_message("What is the meaning of life?")
])

content = ExGrok.extract_content(response)
# => "The meaning of life is..."

# With system message and options
{:ok, response} = ExGrok.create_completion(client, "grok-3-mini", [
  ExGrok.Chat.system_message("You are a helpful assistant."),
  ExGrok.Chat.user_message("Hello!")
], temperature: 0.7, max_tokens: 200)
```

## Responses API (`/v1/responses`)

xAI's newer, agent-oriented interface. Takes an `input` list and returns a typed
`output` list (`reasoning`, `message`, `function_call`) — with first-class
support for reasoning models and multi-turn tool calling.

```elixir
{:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", [
  ExGrok.Responses.system_input("You are a helpful assistant."),
  ExGrok.Responses.user_input("What is 2 + 2?")
], reasoning_effort: "high")

ExGrok.Responses.extract_output_text(resp)
# => "4"
```

Tool calling (stateless full-input replay):

```elixir
tools = [ExGrok.Responses.function_tool("get_weather", "Get weather", schema)]
{:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", input, tools: tools)

case ExGrok.Responses.extract_function_calls(resp) do
  [] ->
    ExGrok.Responses.extract_output_text(resp)

  calls ->
    outputs =
      Enum.map(calls, fn c ->
        ExGrok.Responses.function_call_output(c["call_id"], run(c))
      end)

    # re-send the input + the model's own output items + the tool outputs:
    new_input = input ++ ExGrok.Responses.extract_output_items(resp) ++ outputs
    ExGrok.Responses.create(client, "grok-4.5", new_input, tools: tools)
end
```

### Server-side (agentic) tools

Grok runs these tools on xAI's servers — web search, X search, code execution,
and document (collections) search — and returns citations inline:

```elixir
{:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", [
  ExGrok.Responses.user_input("What did xAI announce this week?")
], tools: [
  ExGrok.Responses.web_search_tool(allowed_domains: ["x.ai"]),
  ExGrok.Responses.x_search_tool(),
  ExGrok.Responses.code_execution_tool()
])

ExGrok.Responses.extract_output_text(resp)
ExGrok.Responses.extract_citations(resp)          # => ["https://x.ai", ...]
ExGrok.Responses.extract_server_tool_calls(resp)  # => [%{"type" => "web_search_call", ...}]
```

### Structured outputs

> **The two endpoints take different shapes.** `/v1/responses` wants a flat
> format map under `text.format`; `/v1/chat/completions` wants the same fields
> nested under `response_format.json_schema`. Sending one to the other is a 400,
> so each module builds its own — `ExGrok.Responses.json_schema/3` and
> `ExGrok.Chat.json_schema_format/3`. Passing `response_format:` to the
> Responses API raises with the fix in the message.

```elixir
schema = %{
  "type" => "object",
  "properties" => %{"city" => %{"type" => "string"}, "temp_c" => %{"type" => "number"}},
  "required" => ["city", "temp_c"]
}

# Responses API — text.format
{:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", input,
  text: ExGrok.Responses.json_schema_text("weather", schema)
)

{:ok, %{"city" => "Tokyo", "temp_c" => 18}} = ExGrok.Responses.extract_parsed(resp)
```

```elixir
# Chat Completions — response_format
{:ok, resp} = ExGrok.create_completion(client, "grok-4.5", messages,
  response_format: ExGrok.Chat.json_schema_format("weather", schema)
)

{:ok, %{"city" => "Tokyo"}} = Jason.decode(ExGrok.extract_content(resp))
```

`json_schema_text/3` is just `%{"format" => json_schema(...)}`; use
`json_schema/3` directly when you need to put sibling keys in the `text` object.

### Vision / multimodal input

```elixir
ExGrok.Responses.create(client, "grok-4.5", [
  ExGrok.Responses.user_input([
    ExGrok.Responses.input_text("What is in this image?"),
    ExGrok.Responses.input_image("https://example.com/photo.jpg", detail: "high")
  ])
])
```

### Stateful & background responses

```elixir
# Stateful chaining — no need to resend history:
{:ok, r1} = ExGrok.Responses.create(client, "grok-4.5", input, store: true)
{:ok, r2} = ExGrok.Responses.create(client, "grok-4.5", next_input,
  previous_response_id: ExGrok.Responses.extract_response_id(r1))

# Background (async) — create, then poll to completion:
{:ok, bg} = ExGrok.Responses.create(client, "grok-4.5", input, background: true)
{:ok, done} = ExGrok.Responses.poll(client, ExGrok.Responses.extract_response_id(bg))

ExGrok.Responses.get(client, id)     # fetch a stored response
ExGrok.Responses.delete(client, id)  # delete a stored response
```

Chat completions have an equivalent deferred flow:

```elixir
{:ok, %{"request_id" => id}} =
  ExGrok.Chat.create_completion(client, "grok-4", messages, deferred: true)

case ExGrok.Chat.get_deferred(client, id) do
  {:ok, completion} -> ExGrok.Chat.extract_content(completion)
  {:pending} -> :not_ready_yet
end
```

### Usage & cost

`ExGrok.Usage` reads either API's usage shape (Chat or Responses):

```elixir
ExGrok.Usage.input_tokens(resp)
ExGrok.Usage.output_tokens(resp)
ExGrok.Usage.reasoning_tokens(resp)   # nested output_tokens_details
ExGrok.Usage.cached_tokens(resp)
ExGrok.Usage.cost_usd(resp)           # from cost_in_usd_ticks
```

## Streaming

```elixir
ExGrok.stream_completion(client, "grok-3-mini", [
  ExGrok.Chat.user_message("Tell me a story")
], fn chunk ->
  case ExGrok.Streaming.extract_delta_content(chunk) do
    nil -> :ok
    content -> IO.write(content)
  end
end)
```

Options work on the streaming path too, and on the Responses API:

```elixir
ExGrok.stream_completion(client, "grok-3-mini", messages, callback, temperature: 0.7)

ExGrok.stream_response(client, "grok-4.5", input, callback,
  text: ExGrok.Responses.json_schema_text("weather", schema)
)
```

Or with a params map:

```elixir
ExGrok.stream_completion(client, %{
  "model" => "grok-3-mini",
  "messages" => [%{"role" => "user", "content" => "Hello"}]
}, fn chunk ->
  IO.inspect(chunk)
end)
```

## Reasoning Models

```elixir
{:ok, response} = ExGrok.create_completion(client, "grok-3-mini", [
  ExGrok.Chat.user_message("Solve: what is 127 * 43?")
], reasoning_effort: "high")

# Get the reasoning chain
reasoning = ExGrok.extract_reasoning_content(response)
# => "Let me think step by step..."

# Get the final answer
answer = ExGrok.extract_content(response)
# => "5461"
```

## Tool Calling

```elixir
tools = [
  %{
    "type" => "function",
    "function" => %{
      "name" => "get_weather",
      "description" => "Get current weather for a location",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "location" => %{"type" => "string", "description" => "City name"}
        },
        "required" => ["location"]
      }
    }
  }
]

{:ok, response} = ExGrok.create_completion(client, "grok-3", [
  ExGrok.Chat.user_message("What's the weather in Tokyo?")
], tools: tools)

tool_calls = ExGrok.extract_tool_calls(response)
```

## Models

```elixir
{:ok, response} = ExGrok.list_models(client)
model_ids = ExGrok.extract_model_ids(response)
# => ["grok-3", "grok-3-mini", "grok-4-fast", ...]

{:ok, model} = ExGrok.get_model(client, "grok-3-mini")
```

## Image Generation

```elixir
{:ok, response} = ExGrok.generate_image(client, "A sunset over the ocean")
urls = ExGrok.extract_image_urls(response)

# With options
{:ok, response} = ExGrok.generate_image(client, "A cat in space",
  model: "grok-2-image",
  n: 2,
  response_format: "b64_json"
)
```

## Video Generation (Grok Imagine)

Video generation is asynchronous — start a job, then poll to completion:

```elixir
{:ok, %{"request_id" => id}} =
  ExGrok.generate_video(client, "A neon city at night, cinematic", duration: 8)

{:ok, done} = ExGrok.poll_video(client, id)
ExGrok.extract_video_url(done)
# => "https://vidgen.x.ai/.../video.mp4"

# Image-to-video
ExGrok.generate_video(client, "slow pan across the scene",
  image: "https://example.com/frame.jpg", resolution: "720p")
```

## Audio (Text-to-Speech & Speech-to-Text)

```elixir
# TTS -> raw audio bytes
{:ok, mp3} = ExGrok.speech(client, "Hello from Grok", voice_id: "eve")
ExGrok.Audio.save(mp3, "hello.mp3")

{:ok, voices} = ExGrok.list_voices(client)

# STT -> transcript
{:ok, resp} = ExGrok.transcribe(client, {:file, "meeting.wav"}, language: "en")
ExGrok.extract_transcript(resp)
```

## Files & Collections

Upload files, group them into a collection, and search them semantically.
Collection **management** uses a separate Management API key and host:

```elixir
# Upload (normal client)
{:ok, file} = ExGrok.upload_file(client, {:file, "report.pdf"}, purpose: "collections")
file_id = ExGrok.extract_file_id(file)

# Manage collections (management client)
mgmt = ExGrok.management_client("xai-management-key")
{:ok, coll} = ExGrok.create_collection(mgmt, "SEC Filings")
cid = ExGrok.extract_collection_id(coll)
{:ok, _} = ExGrok.add_document_to_collection(mgmt, cid, file_id)

# Search (normal client, api.x.ai)
{:ok, results} = ExGrok.search_collection(client, "revenue guidance", collection_ids: [cid])
ExGrok.Collections.extract_search_results(results)
```

You can also let Grok search a collection itself, agentically, via the
`collections_search` server-side tool (see the Responses section).

## Remote MCP Tools

Connect Grok to an external MCP server as a tool in the Responses API:

```elixir
ExGrok.Responses.create(client, "grok-4.5", input, tools: [
  ExGrok.mcp_tool("docs", "https://mcp.example.com/sse", allowed_tools: ["search"])
])
```

## Account & Stats

```elixir
{:ok, info} = ExGrok.api_key_info(client)   # key/team/permission metadata
```

Per-request token and cost stats are available through `ExGrok.Usage`
(see the Usage section above).

## Realtime Voice Agent (WebSocket)

A bidirectional voice session over `wss://api.x.ai/v1/realtime`. Build events
with the pure `ExGrok.Realtime` codec and drive the socket with
`ExGrok.Realtime.Connection` (a `Mint.WebSocket` GenServer):

```elixir
alias ExGrok.Realtime

{:ok, conn} =
  ExGrok.realtime_connect(
    api_key: System.fetch_env!("XAI_API_KEY"),
    on_event: fn event ->
      case Realtime.audio_delta(event) do
        nil -> :ok
        b64 -> play(Base.decode64!(b64))   # streamed assistant audio
      end
    end
  )

ExGrok.Realtime.Connection.send_event(conn, Realtime.session_update(%{
  "voice" => "eve",
  "instructions" => "You are a helpful assistant.",
  "turn_detection" => %{"type" => "server_vad"}
}))

ExGrok.Realtime.Connection.append_audio(conn, mic_chunk)  # stream mic PCM up
ExGrok.Realtime.Connection.commit(conn)                    # end the turn
ExGrok.Realtime.Connection.create_response(conn)           # ask for a reply
```

The codec (`session_update/1`, `append_audio_event/1`, `commit_event/0`,
`create_response_event/1`, `text_item/1`, `function_call_output/2`,
`parse_event/1`, `audio_delta/1`) is pure and unit-tested; the connection
handles the live socket.

## Configuration

All configuration is optional. Sensible defaults are provided:

```elixir
# config/config.exs
config :ex_grok,
  config: [
    base_url: "https://api.x.ai/v1",   # default
    timeout: 120_000                     # default (2 minutes)
  ]
```

## Unknown options

Both `ExGrok.Chat` and `ExGrok.Responses` validate their keyword options and
raise `ArgumentError` on anything they do not recognise, naming the equivalent
where one exists (`max_tokens` → `max_output_tokens`, `response_format` → `text`).
Previously unknown options were silently discarded, which is quieter than a 400:
the request succeeds having ignored what you asked for.

To send a parameter this client does not know about yet, use `:extra_params` —
a map merged verbatim into the request body, so strictness is never a dead end:

```elixir
ExGrok.Responses.create(client, "grok-4.5", input, extra_params: %{"new_param" => 1})
```

## API Modules

| Module | Description |
|--------|-------------|
| `ExGrok.Chat` | Chat completions with streaming, reasoning, and deferred results |
| `ExGrok.Responses` | Responses API — agentic tools (incl. MCP), structured output, vision, stateful/background |
| `ExGrok.Usage` | Typed token/cost accessors normalizing both API surfaces |
| `ExGrok.Models` | Model listing and retrieval |
| `ExGrok.Images` | Image generation and editing |
| `ExGrok.Video` | Grok Imagine video generation (async) |
| `ExGrok.Audio` | Text-to-speech and speech-to-text |
| `ExGrok.Files` | Files API — upload/list/get/download/delete |
| `ExGrok.Collections` | Collections management (Management API) + document search |
| `ExGrok.Realtime` | Realtime Voice Agent event codec (pure) |
| `ExGrok.Realtime.Connection` | Realtime Voice Agent WebSocket connection |
| `ExGrok.Streaming` | SSE parsing utilities |
| `ExGrok.Client` | HTTP client, management client, and response handling |
| `ExGrok.Auth` | Bearer token authentication (Req plugin) |

## Testing

Tests use `Req.Test` for HTTP stubbing — no external API calls:

```bash
mix test
```

## License

MIT
