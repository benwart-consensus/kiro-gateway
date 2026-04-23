# Gateway Scope: What Kiro IDE Features Are Used

**Date:** April 22, 2026
**Purpose:** Clarify what the gateway borrows from your Kiro IDE installation
and what it ignores, so you know what to configure on the calling client side.

---

## Short Answer

The gateway uses **only your Kiro authentication credentials**. Everything
else — MCP servers, steering files, hooks, specs, tools, system prompts,
project context — must come from the client that calls the gateway.

---

## What the Gateway Uses from Kiro

### ✅ Authentication Credentials

The gateway reads credentials from one of three sources (in priority order):

| Source               | Config Variable    | What It Reads                                                                                     |
| -------------------- | ------------------ | ------------------------------------------------------------------------------------------------- |
| kiro-cli SQLite DB   | `KIRO_CLI_DB_FILE` | `access_token`, `refresh_token`, `client_id`, `client_secret`, `profile_arn`, `region`, `scopes`  |
| Kiro IDE JSON file   | `KIRO_CREDS_FILE`  | `accessToken`, `refreshToken`, `profileArn`, `region`, `clientId`, `clientSecret`, `clientIdHash` |
| Environment variable | `REFRESH_TOKEN`    | Refresh token string only                                                                         |

The gateway manages the token lifecycle independently — it refreshes
tokens, handles expiration, and (unless `SQLITE_READONLY=true`) writes
updated tokens back to the credential store.

### ✅ Available Model List

At startup, the gateway calls Kiro's `/ListAvailableModels` API using
your credentials to discover which models are available on your account.
This is the same API the Kiro IDE calls internally. The result is cached
and served through `/v1/models`.

### ✅ Profile ARN and Region

Extracted from your credentials. Used to construct API endpoint URLs
(`q.{region}.amazonaws.com`) and included in requests where required
(Kiro Desktop auth only).

---

## What the Gateway Does NOT Use

### ❌ MCP Servers

MCP servers configured in your Kiro IDE (`.kiro/settings/mcp.json` or
`~/.kiro/settings/mcp.json`) are **completely ignored** by the gateway.
The gateway has no awareness of your MCP configuration.

The one exception is the built-in `web_search` tool: when
`WEB_SEARCH_ENABLED=true` (the default), the gateway auto-injects a
`web_search` tool and routes calls to Kiro's own `/mcp` endpoint. This
is not reading your MCP config — it is a hardcoded feature of the
gateway.

**What you need to do:** Configure MCP servers in your calling client
(opencode, Cursor, Continue, etc.) or provide tools directly in your
API requests.

### ❌ Steering Files

Steering files (`.kiro/steering/*.md`) are a Kiro IDE feature. The
gateway does not read, parse, or inject any steering content.

**What you need to do:** Include any system-level instructions in the
`system` message (Anthropic format) or as a `system` role message
(OpenAI format) in your API requests. Your calling client handles this.

### ❌ Hooks

Agent hooks (`.kiro/hooks/*.json`) are a Kiro IDE feature. The gateway
has no hook system and does not execute pre/post actions.

**What you need to do:** Implement equivalent automation in your calling
client if needed.

### ❌ Specs

Spec-driven workflows are a Kiro IDE feature. The gateway proxies raw
chat completion requests — it has no concept of requirements, design
documents, or task lists.

### ❌ Project Context / Workspace Awareness

The gateway has no knowledge of your project files, directory structure,
open editors, or git state. It is a stateless HTTP proxy.

**What you need to do:** Your calling client (opencode, aider, etc.) is
responsible for gathering project context and including it in the
messages it sends.

### ❌ System Prompts from Kiro IDE

The Kiro IDE injects its own system prompts (identity, capabilities,
rules, etc.) into requests before sending them to the API. The gateway
does not replicate this.

**What you need to do:** Your calling client provides its own system
prompt. The gateway passes it through to Kiro's API as-is (with
optional additions for fake reasoning and truncation recovery, if those
features are enabled).

### ❌ Conversation History / Memory

The Kiro IDE manages conversation state, checkpoints, and session
continuity. The gateway is stateless — each request is independent.

**What you need to do:** Your calling client manages conversation
history and sends the full message array with each request (which is
standard for OpenAI/Anthropic API usage).

### ❌ Extension Ecosystem

Kiro IDE extensions (Open VSX) are not relevant to the gateway.

### ❌ Trusted Commands / Autopilot / Supervised Mode

These are Kiro IDE agent execution features. The gateway only handles
the LLM inference layer — it does not execute code, modify files, or
run commands.

---

## What the Gateway Adds (Not from Kiro IDE)

These features are implemented by the gateway itself, not inherited from
the Kiro IDE:

| Feature                     | Default   | Config                                     | Effect                                                                                              |
| --------------------------- | --------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Fake reasoning              | On        | `FAKE_REASONING=false` to disable          | Injects `<thinking_mode>` XML tags into prompts, parses thinking blocks from responses              |
| Web search tool             | On        | `WEB_SEARCH_ENABLED=false` to disable      | Auto-injects `web_search` tool, routes calls to Kiro's `/mcp` endpoint                              |
| Truncation recovery         | On        | `TRUNCATION_RECOVERY=false` to disable     | Injects synthetic messages when Kiro truncates output                                               |
| Payload auto-trim           | Off       | `AUTO_TRIM_PAYLOAD=true` to enable         | Trims oldest conversation history when payload exceeds ~600KB                                       |
| Tool description relocation | On        | `TOOL_DESCRIPTION_MAX_LENGTH=0` to disable | Moves long tool descriptions (>10KB) to system prompt                                               |
| Model name normalization    | Always on | Not configurable                           | Converts client model names to Kiro format (e.g., `claude-haiku-4-5-20251001` → `claude-haiku-4.5`) |
| Model aliases               | On        | `MODEL_ALIASES` in config                  | Maps custom names to real model IDs (e.g., `auto-kiro` → `auto`)                                    |
| Debug logging               | Off       | `DEBUG_MODE=errors` or `all`               | Saves request/response data to `debug_logs/`                                                        |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Your Calling Client (opencode, Cursor, aider, etc.)    │
│                                                         │
│  Provides:                                              │
│  - System prompt          - Conversation history        │
│  - Tools / MCP servers    - Project context             │
│  - Model selection        - Streaming preference        │
└──────────────────────┬──────────────────────────────────┘
                       │ OpenAI or Anthropic API format
                       ▼
┌─────────────────────────────────────────────────────────┐
│  Kiro Gateway (this proxy)                              │
│                                                         │
│  Uses from Kiro:              Adds on its own:          │
│  - Auth credentials           - Format translation      │
│  - Model list                 - Fake reasoning tags     │
│  - Profile ARN / region       - Web search injection    │
│                                - Truncation recovery    │
│  Does NOT use:                 - Payload size guards    │
│  - MCP servers                 - Tool name validation   │
│  - Steering files              - Model name normalizing │
│  - Hooks / Specs               - Retry logic            │
│  - Project context                                      │
│  - IDE system prompts                                   │
└──────────────────────┬──────────────────────────────────┘
                       │ Kiro internal protocol
                       ▼
┌─────────────────────────────────────────────────────────┐
│  Kiro API (q.{region}.amazonaws.com)                    │
│                                                         │
│  - /generateAssistantResponse                           │
│  - /ListAvailableModels                                 │
│  - /mcp (web search only)                               │
└─────────────────────────────────────────────────────────┘
```

---

## Common Questions

**Q: I have 5 MCP servers in my Kiro IDE. Will the model see those tools?**
No. Configure them in your calling client instead.

**Q: Will my Kiro steering rules apply?**
No. Add equivalent instructions to your client's system prompt.

**Q: Can I use different models per request?**
Yes. Set the `model` field in each request. The gateway normalizes the
name and passes it to Kiro. Use `/v1/models` to see what is available.

**Q: Does the gateway share state between requests?**
No. It is stateless. The only persistent state is the auth token cache
and the model list cache (refreshed hourly).

**Q: If I disable all gateway additions, is it a clean proxy?**
Nearly. With `FAKE_REASONING=false`, `WEB_SEARCH_ENABLED=false`, and
`TRUNCATION_RECOVERY=false`, the gateway still performs format
translation (OpenAI/Anthropic → Kiro internal format), model name
normalization, tool schema sanitization, and payload size validation.
These are structural requirements, not optional enrichments.
