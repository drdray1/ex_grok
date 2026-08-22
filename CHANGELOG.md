# Changelog

## 0.6.0

Structured output on the Responses API never worked. This release fixes it, and
closes the gap in the test suite that let it ship.

### Breaking

- **`ExGrok.Responses.json_schema_format/3` is renamed to `json_schema/3`, and
  its return shape has changed.** It now returns the flat map the Responses API
  requires (`name`/`schema`/`strict` beside `type`) rather than the
  chat-completions nesting. The old name now exists only on
  `ExGrok.Chat.json_schema_format/3`, where the nested shape is correct — so the
  identifier has one meaning, and a stale call site fails to compile rather than
  failing against the live API.

- **`response_format:` is no longer accepted by the Responses API.** It is a
  `/v1/chat/completions` parameter; `/v1/responses` rejects it with a 400. Use
  `text:` instead. Keyword options raise `ArgumentError`; raw params maps passed
  to `create/2`, `stream/3` or `compact/2` return
  `{:error, {:invalid_params, message}}`, since those carry data that may come
  from config or a job payload.

- **Unknown options raise instead of being silently discarded.** `Keyword.take/2`
  used to drop anything unrecognised, which is quieter than a 400 — the request
  succeeded having ignored what you asked for. Cross-endpoint mistakes name their
  equivalent (`max_tokens` → `max_output_tokens`). Use `:extra_params` to send
  parameters this client does not know about yet.

- **Passing both `:reasoning` and `:reasoning_effort` raises.** They write the
  same `"reasoning"` key, so whichever was listed last silently won.

### Migration

```elixir
# before — 400 from the API
Responses.create(client, model, input,
  response_format: Responses.json_schema_format("weather", schema)
)

# after
Responses.create(client, model, input,
  text: Responses.json_schema_text("weather", schema)
)

# chat completions is unchanged, but its builder now lives on Chat
Chat.create_completion(client, model, messages,
  response_format: Chat.json_schema_format("weather", schema)
)
```

### Added

- `ExGrok.Responses.json_schema_text/3` — a ready-to-pass `:text` value, so the
  `"format"` wrapper cannot be forgotten.
- `ExGrok.Responses.stream/5` — the streaming twin of `create/4`. Streaming
  previously had no options arity at all, forcing callers to hand-assemble a
  params map.
- `ExGrok.Chat.stream_completion/5` — same gap on the chat side; the arity-4 form
  hard-coded an empty options list.
- `ExGrok.Chat.json_schema_format/3` and `ExGrok.Chat.function_tool/3` — the
  nested chat-completions builders. Chat users previously hand-wrote both, and
  reaching for the `Responses` equivalents produced a 400.
- `:extra_params` on both modules.
- `ExGrok.mcp_tool/3` — the facade delegated only arity 2, so the documented
  three-argument example raised `UndefinedFunctionError`.

### Fixed

- README pinned installs to `0.1.0` while the library was at `0.5.0`, so anyone
  following it got a build predating the Responses API entirely.

### Testing

The four structured-output tests asserted the builder against its own return
value and never made an HTTP call, so both the wrong key and the wrong nesting
passed green. They are replaced with assertions on the serialized request body,
each of which also **refutes the other endpoint's key** — presence-only
assertions are what missed this. Added streaming/non-streaming body parity tests
so the two paths cannot drift again, and a CI workflow, which did not exist.
