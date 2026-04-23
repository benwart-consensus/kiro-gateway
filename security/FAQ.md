# Frequently Asked Questions: Kiro Gateway

**Date:** April 22, 2026
**Context:** Questions that came up during security review and evaluation
of the gateway for use with third-party clients.

See also:

- [SECURITY_AUDIT.md](SECURITY_AUDIT.md) — Codebase security findings
- [TOS_ANALYSIS.md](TOS_ANALYSIS.md) — Terms of Service risk assessment
- [GATEWAY_SCOPE.md](GATEWAY_SCOPE.md) — What Kiro IDE features are/aren't used

---

## API Protocol

### What protocol does the proxy expose?

Both OpenAI and Anthropic, simultaneously on the same server.

**OpenAI-compatible:**

- `GET /v1/models` — list available models
- `POST /v1/chat/completions` — chat completions (streaming and non-streaming)
- Auth: `Authorization: Bearer {PROXY_API_KEY}`

**Anthropic-compatible:**

- `POST /v1/messages` — messages API (streaming and non-streaming)
- Auth: `x-api-key: {PROXY_API_KEY}` (also accepts `Authorization: Bearer`)

Both endpoints translate incoming requests into Kiro's internal format
(an undocumented AWS protocol using `generateAssistantResponse` on
`q.{region}.amazonaws.com`), then translate responses back. Any client
that speaks either protocol can use it — opencode, Cursor, Continue,
Cline, aider, raw `curl`, etc.

---

## Model Selection

### Can I pick different models per request, or is it locked to one?

Fully dynamic. The gateway does not lock you to a single model.

At startup it fetches available models from Kiro's `/ListAvailableModels`
API and caches them. When your client sends a request with a `model`
field, the gateway's `ModelResolver` normalizes the name and passes it
through to Kiro. It does not override or hardcode the model.

Your client's `/v1/models` call returns the full list. The exact models
depend on your Kiro subscription tier — the gateway fetches whatever
`/ListAvailableModels` returns for your account at startup. Examples
that have been observed:

| Model               | Notes                                        |
| ------------------- | -------------------------------------------- |
| `auto`              | Kiro picks the model                         |
| `claude-sonnet-4`   |                                              |
| `claude-sonnet-4.5` |                                              |
| `claude-haiku-4.5`  |                                              |
| `claude-opus-4`     | May require paid subscription                |
| `claude-opus-4.5`   | May require paid subscription                |
| `claude-3.7-sonnet` | Hidden but functional (hardcoded in gateway) |

This is not an exhaustive list. If Kiro adds new models, they appear
automatically after the gateway restarts and re-fetches the model list.
Models that require a paid tier only show up if your account has access.

The resolver handles name normalization — `claude-haiku-4-5-20251001`
becomes `claude-haiku-4.5`. There is also an alias system
(`auto-kiro` → `auto`) to avoid conflicts with client-specific model
names like Cursor's built-in "auto."

---

## Fake Reasoning

### Why does the fake reasoning feature exist?

Kiro's API does not expose a native extended thinking / chain-of-thought
parameter like Anthropic's `thinking` parameter or OpenAI's
`reasoning_effort`. The underlying Claude models can reason in
`<thinking>` blocks, but Kiro's `generateAssistantResponse` endpoint
has no parameter to enable it.

The fake reasoning feature works around this:

1. **Injects XML tags** (`<thinking_mode>enabled</thinking_mode>`,
   `<max_thinking_length>N</max_thinking_length>`) into the user
   message content. The model sees these and responds with
   `<thinking>...</thinking>` blocks in its output.
2. **Parses the response** with a finite state machine
   (`thinking_parser.py`) that extracts thinking blocks from the text
   stream.
3. **Converts to standard format** — extracted thinking content maps to
   OpenAI's `reasoning_content` field or Anthropic's thinking content
   blocks, so your client sees structured reasoning instead of raw XML.

Without it, clients that request reasoning (e.g., `reasoning_effort:
"high"` in opencode) would get no thinking output — the parameter would
be silently ignored.

If you don't care about chain-of-thought visibility, set
`FAKE_REASONING=false` for a cleaner proxy with no prompt modification.
The model still "thinks" internally — you just don't see it.

---

## Token Usage and Context Size

### Does context usage come through the proxy so clients can show how much is used?

Partially. The numbers are approximate, not exact.

**What Kiro provides:** The API returns a `context_usage` percentage in
the stream (e.g., "you've used 43% of context"). It does not return raw
token counts for prompt or completion.

**What the gateway does:** It reverse-calculates approximate token
counts:

```
max_input_tokens = model_cache.get_max_input_tokens(model)  # default: 200,000
total_tokens = (context_usage_percentage / 100) * max_input_tokens
prompt_tokens = total_tokens - completion_tokens
```

Completion tokens are counted locally via tiktoken. The `usage` block in
responses (`prompt_tokens`, `completion_tokens`, `total_tokens`) is an
estimate.

**What clients see:** Standard OpenAI/Anthropic usage fields populated
with these estimates. Token usage will display in your client, but treat
the numbers as directional rather than precise. The percentage from Kiro
is accurate; the token count derived from it is a best-effort
approximation.

### Can I configure max input tokens per model?

No. There is no per-model config for `max_input_tokens`.

The gateway checks if Kiro's `/ListAvailableModels` response includes a
`tokenLimits.maxInputTokens` field for each model. If present, that
value is cached and used. If missing (common for undocumented APIs), it
falls back to `DEFAULT_MAX_INPUT_TOKENS` which is hardcoded to
`200,000` in `config.py`.

There is no env var or config option to override this per model. If you
need accurate per-model limits, you would need to add a config mapping
in `config.py` and modify `ModelInfoCache.get_max_input_tokens()` to
check it before falling back to the default.

---

## Tool Execution

### Do tools run on the proxy or on my client?

On your client, with one exception.

**Standard flow:** Your client sends tool definitions in the request →
the gateway translates them to Kiro format and forwards them → the
model responds with `tool_use` calls → the gateway translates those
back to OpenAI/Anthropic format → your client receives the tool calls,
executes them locally, and sends results back in the next request. The
gateway never executes tools — it just passes definitions and results
through.

**The exception: `web_search`.** When `WEB_SEARCH_ENABLED=true` (the
default), the gateway intercepts `web_search` tool calls from the model
and executes them itself by calling Kiro's `/mcp` endpoint server-side.
The results are injected back into the response stream before your
client sees them. Your client never knows a tool was called — it just
gets search results as text content.

All your tools (filesystem, shell, MCP servers, etc.) run on the client
side. The gateway is a pass-through for tool definitions and results,
except for that one built-in web search feature.

### If I have MCP servers in my Kiro IDE, will the model see those tools?

No. MCP servers configured in your Kiro IDE are completely ignored by
the gateway. Configure them in your calling client instead. See
[GATEWAY_SCOPE.md](GATEWAY_SCOPE.md) for the full breakdown.

---

## Clean Proxy Configuration

### What is the minimal-modification config?

To get the closest to a clean, unmodified proxy:

```env
FAKE_REASONING=false
WEB_SEARCH_ENABLED=false
TRUNCATION_RECOVERY=false
```

The gateway will still perform:

- Format translation (OpenAI/Anthropic → Kiro internal format)
- Model name normalization
- Tool schema sanitization (removing fields Kiro rejects)
- Payload size validation
- Tool description relocation (for descriptions >10KB)

These are structural requirements for the proxy to function, not
optional enrichments.

---

## Related Documents

| Document                               | What It Covers                                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [SECURITY_AUDIT.md](SECURITY_AUDIT.md) | Code-level security findings: default API key, CORS, debug logging, error leakage, credential handling      |
| [TOS_ANALYSIS.md](TOS_ANALYSIS.md)     | Terms of Service violations, account suspension risk, whether alternative clients are explicitly prohibited |
| [GATEWAY_SCOPE.md](GATEWAY_SCOPE.md)   | What Kiro IDE features the gateway uses vs ignores, architecture diagram, what your client must provide     |
