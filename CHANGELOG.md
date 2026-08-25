# Changelog

## 0.6.5

`Audio` was the last module still filtering its options with a bare
`Keyword.take/2`, which is the failure `ExGrok.Options` exists to prevent — and
whose moduledoc has described it accurately since 0.6.0:

> an unrecognised option vanishes inside `Keyword.take/2` and the request
> succeeds having ignored what the caller asked for — quieter, and so worse,
> than the 400 you would get for sending it.

That is not hypothetical. A downstream app configured `vad_threshold` on every
transcription for weeks. The allowlist was `~w(language format keyterm)a`, so
the option was dropped before the request was built, and every call returned
`200`.

### Added

- **STT gains the documented options**: `vad_threshold`, `filler_words`,
  `diarize`, `multichannel`, `channels`, `audio_format`, `sample_rate`.
- **`:extra_params` on `transcribe/3` and `speech/3`**, as Chat and Responses
  already had. Merged last, so it can also override a field this client builds.
  With it, the allowlist stops being a dead end the day xAI ships something new.
- **List values become repeated multipart fields**, which is how `keyterm`
  carries more than one term (xAI allows up to 100).

### Changed

- **`transcribe/3` and `speech/3` now raise `ArgumentError` on an unknown
  option** instead of silently discarding it. This is a breaking change for
  callers currently passing a name that does nothing — which is the point.

### Notes from calling the API, not reading the reference

- `/v1/stt` **accepts parameters that do not exist** and answers `200` with an
  identical transcript. Unlike `/v1/responses`, which returns
  `400 "Argument not supported"`, this endpoint validates nothing. A live test
  asserting `{:ok, _}` after sending an option therefore proves nothing at all,
  so the new STT live tests are differential: send the option, send it without,
  compare the output.
- **`vad_threshold` is inert on `grok-stt`.** `0.05` and `0.95` give identical
  results on the same audio. It is in the allowlist because the endpoint takes
  it and it may yet be wired up; the live suite pins the current behaviour so a
  change is noticed.
- **Long audio is under-transcribed, not under-read.** `grok-stt` reports the
  full duration of a 499 s upload and then writes out ~82 words. The same audio
  cut into 100 s pieces yields far more, including passages the whole-file call
  omits entirely. Nothing in this library can fix that; callers with long audio
  should chunk it.

## 0.6.3

Everything here came from calling the API instead of reading its reference. The
reference is wrong in both directions, and 0.6.2's allowlist trusted it.

### Breaking

- **`background` is removed.** `/v1/responses` answers
  `400 "Argument not supported: background"`, so the documented background/async
  feature never worked for anyone. `poll/3`, `get/2` and `delete/2` stay — they
  are valid for `store: true` retrieval — but stop being described as an async
  mechanism. For asynchronous work use `ExGrok.Chat` with `deferred: true` and
  `get_deferred/2`, which is verified working.
- **`metadata` is removed** from the Responses allowlist: also a hard
  `400 "Argument not supported"`, though the reference merely calls it
  "maintained for compatibility".
- **`search_parameters` is removed from both modules.** Live search is retired:
  `410 "Live search is deprecated. Please switch to the Agent Tools API"`. Use
  `web_search_tool/1` / `x_search_tool/1` via `tools:` instead.
- **`401`, `403`, `404` and `429` now carry the API's message** —
  `{:error, {:forbidden, message}}` rather than `{:error, :forbidden}`. These
  were the only statuses whose body was discarded, and they are the ones where
  it matters: a real 403 here reads *"Your newly created team doesn't have any
  credits or licenses yet. You can purchase those on https://console.x.ai/team/…"* —
  the diagnosis and the fix, previously thrown away.

`truncation` stays allowed despite the reference calling it unsupported; the API
accepts it. That asymmetry with `metadata` is precisely why these were tested
rather than inferred.

### Fixed

- `responses_test.exs` asserted that `background: true` reached the request
  body. True, and worthless — a wire-shape assertion cannot tell you the server
  refused it, and the test locked in a feature that always failed. Inverted.

## 0.6.2

Corrects the allowlist that 0.6.0 made strict. Turning it into a raising
guardrail meant every parameter missing from it became a hard blocker rather
than a silent drop — so an incomplete list was suddenly a much bigger problem
than it had been.

- **`search_parameters` is accepted by both endpoints.** 0.6.0 classified it
  chat-only, so `Responses.create/4` raised and told callers it belonged to the
  other endpoint. That was wrong advice, not merely a missing entry.
- Added the rest of the documented `POST /v1/responses` parameters, which were
  all raising: `top_k`, `min_p`, `max_turns`, `include`, `metadata`,
  `truncation`, `user`, `service_tier`, `prompt_cache_key`,
  `context_management`, `logprobs`, `top_logprobs`.

Checked against xAI's API reference rather than inferred — guessing at the
parameter set is what produced the original bug.

## 0.6.1

**Corrects a false claim in 0.6.0.** Its README, changelog and release notes all
said *both* `ExGrok.Chat` and `ExGrok.Responses` validate their keyword options
and support `:extra_params`. Only `Responses` did. On `Chat`, `text:`,
`max_output_tokens:` and `extra_params:` were still silently discarded — the
exact bug class 0.6.0 set out to kill, and the direction that matters most: a
Responses user moving to Chat lost structured output and got prose back with a
200.

Documentation promising a guardrail that is not there is worse than no
guardrail, because it stops people checking.

- `ExGrok.Chat` now validates options and raises `ArgumentError` on unknown
  ones, naming the chat equivalent for Responses-only spellings
  (`text` → `response_format`, `max_output_tokens` → `max_tokens`).
- `ExGrok.Chat` supports `:extra_params`.
- `Chat.create_completion/2` and `stream_completion/3` reject a raw params map
  carrying a top-level `"text"`, mirroring the guard `Responses` already had.
- The shared logic moved to `ExGrok.Options` so the two sides cannot drift
  again — the drift is what produced this.

The suite missed it because the tests were asymmetric in the same way as the
code: `responses_test.exs` had a full option-validation block, `chat_test.exs`
had none. That block now exists on both sides.

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
