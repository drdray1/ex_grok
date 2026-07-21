# ExGrok

Elixir client for the [xAI Grok API](https://docs.x.ai/).

Supports chat completions (with streaming and reasoning), model listing, and image generation.

## Installation

```elixir
def deps do
  [
    {:ex_grok, git: "https://github.com/drdray1/ex_grok.git", tag: "0.1.0"}
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

```elixir
schema = %{
  "type" => "object",
  "properties" => %{"city" => %{"type" => "string"}, "temp_c" => %{"type" => "number"}},
  "required" => ["city", "temp_c"]
}

{:ok, resp} = ExGrok.Responses.create(client, "grok-4.5", input,
  response_format: ExGrok.Responses.json_schema_format("weather", schema)
)

{:ok, %{"city" => "Tokyo", "temp_c" => 18}} = ExGrok.Responses.extract_parsed(resp)
```

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

## API Modules

| Module | Description |
|--------|-------------|
| `ExGrok.Chat` | Chat completions with streaming, reasoning, and deferred results |
| `ExGrok.Responses` | Responses API — agentic tools, structured output, vision, stateful/background |
| `ExGrok.Usage` | Typed token/cost accessors normalizing both API surfaces |
| `ExGrok.Models` | Model listing and retrieval |
| `ExGrok.Images` | Image generation and editing |
| `ExGrok.Streaming` | SSE parsing utilities |
| `ExGrok.Client` | HTTP client and response handling |
| `ExGrok.Auth` | Bearer token authentication (Req plugin) |

## Testing

Tests use `Req.Test` for HTTP stubbing — no external API calls:

```bash
mix test
```

## License

MIT
