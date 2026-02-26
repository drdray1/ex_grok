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
| `ExGrok.Chat` | Chat completions with streaming and reasoning |
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
