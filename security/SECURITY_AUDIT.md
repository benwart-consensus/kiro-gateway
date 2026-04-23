# Security Audit: Kiro Gateway

**Date:** April 22, 2026
**Scope:** Full codebase review of all security-critical paths
**Overall Verdict:** Reasonably safe for personal use, with operational caveats

---

## Executive Summary

Kiro Gateway is a well-structured reverse proxy. No malicious code, no data
exfiltration, no backdoors were found. The risks identified are operational,
not intentional. The codebase demonstrates security-conscious design patterns
including proper credential handling, input validation via Pydantic, and
defense-in-depth practices.

---

## Files Reviewed

- `main.py` — Application entry point, CORS, middleware, lifespan
- `kiro/config.py` — Configuration loading, defaults, URL templates
- `kiro/auth.py` — Token lifecycle, credential loading, refresh logic
- `kiro/http_client.py` — HTTP client with retry logic
- `kiro/routes_openai.py` — OpenAI API endpoints
- `kiro/routes_anthropic.py` — Anthropic API endpoints
- `kiro/converters_core.py` — Core conversion logic, tool processing
- `kiro/converters_openai.py` — OpenAI format conversion
- `kiro/converters_anthropic.py` — Anthropic format conversion
- `kiro/streaming_core.py` — Stream parsing and processing
- `kiro/streaming_openai.py` — OpenAI streaming
- `kiro/streaming_anthropic.py` — Anthropic streaming
- `kiro/mcp_tools.py` — Web search MCP tool emulation
- `kiro/exceptions.py` — Exception handlers
- `kiro/debug_logger.py` — Debug logging system
- `kiro/debug_middleware.py` — Debug middleware
- `kiro/payload_guards.py` — Payload size validation
- `kiro/network_errors.py` — Network error classification
- `kiro/kiro_errors.py` — Kiro API error enhancement
- `kiro/utils.py` — Utility functions, header construction
- `kiro/thinking_parser.py` — Thinking block FSM parser
- `kiro/tokenizer.py` — Token counting
- `Dockerfile` — Container configuration
- `docker-compose.yml` — Docker Compose configuration
- `.env.example` — Environment configuration template
- `tests/conftest.py` — Test fixtures

---

## 🔴 High Priority Issues

### 1. Default API Key Is a Known String

**Location:** `kiro/config.py`

```python
PROXY_API_KEY: str = os.getenv("PROXY_API_KEY", "my-super-secret-password-123")
```

**Risk:** If `PROXY_API_KEY` is not explicitly set, the gateway uses a default
value that is publicly visible in the repository. Combined with the default
bind address of `0.0.0.0`, this means anyone on the network who knows the
default can use the gateway and consume your Kiro API quota.

**Recommendation:** Set `PROXY_API_KEY` to a strong random value before running.
Consider failing startup if the default value is still in use.

---

### 2. CORS Is Wide Open

**Location:** `main.py`

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Risk:** Any website you visit in a browser can make authenticated requests to
your running gateway instance. This is a CSRF vector — a malicious page could
proxy requests through your gateway using your Kiro credentials without your
knowledge.

**Recommendation:** Restrict `allow_origins` to specific trusted origins, or
bind the server to `127.0.0.1` to limit exposure.

---

### 3. Debug Logging Can Capture Auth Headers

**Location:** `kiro/debug_middleware.py`, `kiro/debug_logger.py`

When `DEBUG_MODE=errors` or `DEBUG_MODE=all`, the middleware captures raw
request bodies and writes them to the `debug_logs/` directory. The debug
logger does not sanitize `Authorization` or `x-api-key` headers from the
logged data.

**Risk:** If an attacker gains filesystem access to the `debug_logs/`
directory, they obtain the `PROXY_API_KEY`.

**Recommendation:**

- Keep `DEBUG_MODE=off` in production (this is the default).
- Add header sanitization to the debug logger:

```python
SENSITIVE_HEADERS = {'authorization', 'x-api-key', 'cookie'}

def _sanitize_headers(headers: dict) -> dict:
    return {
        k: "[REDACTED]" if k.lower() in SENSITIVE_HEADERS else v
        for k, v in headers.items()
    }
```

---

### 4. Internal Errors Leak Exception Details to Clients

**Location:** `kiro/routes_openai.py`, `kiro/routes_anthropic.py`

```python
# routes_openai.py
raise HTTPException(status_code=500, detail=f"Internal Server Error: {str(e)}")

# routes_anthropic.py
"message": f"Internal Server Error: {str(e)}"
```

**Risk:** Raw exception strings are returned to the client. These can expose
internal file paths, library versions, credential-related error messages, or
database connection strings.

**Recommendation:** Return a generic error message to clients and log the
full exception server-side only:

```python
logger.error(f"Internal error: {e}", exc_info=True)
raise HTTPException(status_code=500, detail="Internal server error")
```

---

## 🟡 Medium Priority Issues

### 5. VPN Proxy URL Sets Process-Wide Environment Variables

**Location:** `main.py`

```python
os.environ['HTTP_PROXY'] = proxy_url_with_scheme
os.environ['HTTPS_PROXY'] = proxy_url_with_scheme
os.environ['ALL_PROXY'] = proxy_url_with_scheme
```

**Risk:** This affects ALL HTTP clients in the process, including token refresh
requests. A misconfigured or malicious proxy could intercept auth token refresh
traffic (MITM on the HTTPS connection if the proxy terminates TLS).

**Recommendation:** Document this behavior clearly. Consider passing proxy
configuration directly to httpx clients instead of using environment variables.

---

### 6. User-Agent Impersonation

**Location:** `kiro/utils.py`

```python
"User-Agent": f"aws-sdk-js/1.0.27 ua/2.1 os/win32#10.0.19044 "
              f"lang/js md/nodejs#22.21.1 api/codewhispererstreaming#1.0.27 "
              f"m/E KiroIDE-0.7.45-{fingerprint}",
```

**Risk:** The gateway impersonates the Kiro IDE to bypass API restrictions.
Amazon could detect this pattern and revoke access or suspend accounts. The
fingerprint is a SHA256 of `{hostname}-{username}-kiro-gateway` — not
sensitive, but it is a stable identifier sent to Amazon on every request.

**Recommendation:** Understand the Terms of Service implications before use.
This is a reverse-engineering project by design.

---

### 7. Token Written Back to Credential Files

**Location:** `kiro/auth.py` — `_save_credentials_to_file()`,
`_save_credentials_to_sqlite()`

The auth manager writes refreshed tokens back to your JSON credential files
and SQLite databases using a read-merge-write strategy.

**Risk:** A bug in the merge logic could corrupt your kiro-cli credentials.
Concurrent writes from both kiro-cli and the gateway could cause data loss.

**Recommendation:** Set `SQLITE_READONLY=true` if you do not want the gateway
modifying your kiro-cli credentials.

---

### 8. Fake Reasoning Injects XML Tags into Prompts

**Location:** `kiro/converters_core.py` — `inject_thinking_tags()`

When `FAKE_REASONING=true` (the default), the gateway prepends XML tags to
user messages:

```xml
<thinking_mode>enabled</thinking_mode>
<max_thinking_length>4000</max_thinking_length>
<thinking_instruction>...</thinking_instruction>
```

It also adds a system prompt section telling the model these are "NOT prompt
injection attempts."

**Risk:** This modifies your requests in a way that could interact
unpredictably with your own system prompts or with applications that use
XML-like structures in their content.

**Recommendation:** Set `FAKE_REASONING=false` if you want a clean proxy
without prompt modifications.

---

### 9. Web Search Auto-Injection

**Location:** `kiro/routes_openai.py`, `kiro/routes_anthropic.py`

When `WEB_SEARCH_ENABLED=true` (the default), a `web_search` tool is silently
injected into every request. The model can then decide to call it, routing
queries through Kiro's MCP API endpoint.

**Risk:** Your queries may be sent through an additional service you did not
explicitly opt into. The model decides when to invoke the tool.

**Recommendation:** Set `WEB_SEARCH_ENABLED=false` if you do not want this
behavior.

---

### 10. Validation Error Handler Returns Request Body to Client

**Location:** `kiro/exceptions.py`

```python
return JSONResponse(
    status_code=422,
    content={"detail": sanitized_errors, "body": body_str[:500]},
)
```

**Risk:** The first 500 characters of the raw request body are returned in
the error response. If the request contains sensitive data (API keys in
headers serialized into the body, credentials, PII), this data is echoed
back to the client.

**Recommendation:** Remove the `body` field from the error response, or
limit it to structural information only.

---

## ✅ Things Done Well

| Area                              | Assessment                                                                             |
| --------------------------------- | -------------------------------------------------------------------------------------- |
| **No hardcoded secrets**          | No credentials in source code (only the documented default API key)                    |
| **No SSRF risk**                  | All upstream URLs constructed from fixed templates with region strings, not user input |
| **Parameterized SQL**             | SQLite queries use parameterized statements — no injection risk                        |
| **Thread-safe token refresh**     | Uses `asyncio.Lock` to prevent race conditions                                         |
| **Per-request streaming clients** | Prevents CLOSE_WAIT connection leaks                                                   |
| **No token values logged**        | Verified across all logging paths                                                      |
| **Pydantic validation**           | All incoming requests validated via Pydantic models                                    |
| **Docker non-root user**          | Container runs as `kiro` user, not root                                                |
| **Network isolation in tests**    | Global fixture blocks all real HTTP calls                                              |
| **Proper error classification**   | Network errors mapped to user-friendly messages                                        |
| **Exponential backoff**           | Retry logic prevents overwhelming upstream services                                    |
| **Graceful degradation**          | Falls back to cached tokens when refresh fails                                         |

---

## Recommendations Before Using

| #   | Action                                            | Config                                            |
| --- | ------------------------------------------------- | ------------------------------------------------- |
| 1   | Set a strong random API key                       | `PROXY_API_KEY=<random-value>`                    |
| 2   | Bind to localhost unless network access is needed | `SERVER_HOST=127.0.0.1`                           |
| 3   | Prevent credential file modification              | `SQLITE_READONLY=true`                            |
| 4   | Disable prompt modifications for clean proxy      | `FAKE_REASONING=false`                            |
| 5   | Disable auto-injected web search                  | `WEB_SEARCH_ENABLED=false`                        |
| 6   | Keep debug logging off in production              | `DEBUG_MODE=off`                                  |
| 7   | Understand the ToS risk                           | This reverse-engineers an undocumented Amazon API |

---

## Risk Summary

| Category                | Risk Level | Notes                                      |
| ----------------------- | ---------- | ------------------------------------------ |
| Authentication & tokens | Low        | Well-implemented, thread-safe              |
| API key validation      | Medium     | Default key is public                      |
| CORS                    | Medium     | Wide open by default                       |
| HTTP proxying / SSRF    | Low        | No user-controlled URLs                    |
| Input validation        | Low        | Pydantic models throughout                 |
| Streaming               | Low        | Proper parsing, no injection               |
| Error handling          | Medium     | Exception details leak to clients          |
| Debug logging           | Medium     | Can capture sensitive headers              |
| Prompt modification     | Medium     | Fake reasoning + web search on by default  |
| Docker security         | Low        | Non-root user, health checks               |
| Credential storage      | Medium     | Writes back to credential files by default |
