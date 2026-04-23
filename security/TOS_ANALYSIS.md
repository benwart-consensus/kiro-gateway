# Terms of Service Analysis: Kiro Gateway

**Date:** April 22, 2026
**Scope:** Assessment of Kiro Gateway against applicable AWS/Kiro terms
**Disclaimer:** This is a technical analysis, not legal advice. Consult a
qualified attorney for definitive guidance on your specific situation.

---

## Executive Summary

Kiro Gateway operates as an unauthorized third-party proxy that intercepts,
modifies, and re-routes requests to undocumented Kiro/Amazon Q Developer API
endpoints. Based on a review of the applicable terms, **this project likely
violates multiple provisions** of the AWS Customer Agreement, AWS Intellectual
Property License, AWS Service Terms, and the Kiro License. The risk of account
suspension is real, though enforcement patterns are uncertain.

---

## Applicable Terms Reviewed

| Document                                     | URL                                                                                                | Last Checked |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------ |
| AWS Customer Agreement                       | [aws.amazon.com/agreement](https://aws.amazon.com/agreement/app/)                                  | April 2026   |
| AWS Intellectual Property License            | [aws.amazon.com/legal/aws-ip-license-terms](https://aws.amazon.com/jp/legal/aws-ip-license-terms/) | April 2026   |
| AWS Service Terms (Section 50 — AI Services) | [aws.amazon.com/service-terms](https://aws.amazon.com/service-terms/)                              | April 2026   |
| AWS Acceptable Use Policy                    | [aws.amazon.com/aup](https://aws.amazon.com/aup/)                                                  | April 2026   |
| Kiro License                                 | [kiro.dev/license](https://kiro.dev/license/)                                                      | April 2026   |
| Kiro Privacy and Security                    | [kiro.dev/docs/privacy-and-security](https://kiro.dev/docs/privacy-and-security/)                  | April 2026   |

---

## Violation Analysis

### 1. 🔴 AWS IP License — Section 4: License Restrictions

> "Neither you nor any End User will use the Services or AWS Content in any
> manner or for any purpose other than as expressly permitted by this License
> and the Agreement. Neither you nor any End User will, or will attempt to
> (a) modify, distribute, alter, tamper with, repair, or otherwise create
> derivative works of any Content included in the Services or AWS Content...
> or (b) sublicense the Services or AWS Content."
>
> — [AWS Intellectual Property License, Section 4](https://aws.amazon.com/jp/legal/aws-ip-license-terms/)

**How Kiro Gateway violates this:**

- The gateway **modifies requests and responses** in transit. It injects
  thinking tags, rewrites tool descriptions, auto-injects web search tools,
  and reformats streaming responses from Kiro's internal format to
  OpenAI/Anthropic formats. This constitutes creating derivative works of
  AWS Content (the API responses).
- The gateway effectively **sublicenses** access to Kiro's API by exposing
  it through OpenAI-compatible and Anthropic-compatible endpoints. Any
  client that can speak the OpenAI API format can now use Kiro through
  the gateway, which was not the intended access method.

**Risk level: HIGH** — This is the most clear-cut violation.

---

### 2. 🔴 AWS IP License — Section 3: Scope of License

> "AWS Licensor grants you a limited, royalty-free, revocable, non-exclusive,
> non-sublicensable, non-transferrable license to copy and use the AWS Content
> solely in connection with your permitted use of the Services during the Term."
>
> — [AWS Intellectual Property License, Section 3](https://aws.amazon.com/jp/legal/aws-ip-license-terms/)

**How Kiro Gateway violates this:**

- The license permits use of AWS Content "solely in connection with your
  permitted use of the Services." The Services here means Kiro IDE or
  Kiro CLI — the official clients. Using the underlying API through a
  reverse-engineered proxy is not a "permitted use of the Services."
- The gateway copies and transforms API responses (AWS Content) for
  redistribution through a different API format, which exceeds the
  scope of the license grant.

**Risk level: HIGH**

---

### 3. 🔴 Kiro License — Use as "AWS Content"

> "The Kiro IDE and Kiro CLI are each licensed to you as 'AWS Content' under
> the AWS Customer Agreement or other written agreement with us governing
> your use of AWS services, and the AWS Intellectual Property License."
>
> — [kiro.dev/license](https://kiro.dev/license/)

**How Kiro Gateway violates this:**

- Kiro is licensed specifically as the IDE and CLI applications. The
  underlying API endpoints (`q.{region}.amazonaws.com/generateAssistantResponse`,
  `/ListAvailableModels`, `/mcp`) are internal service endpoints, not
  independently licensed services.
- The gateway bypasses the licensed client software entirely and calls
  these endpoints directly, which is outside the scope of the license.

**Risk level: HIGH**

---

### 4. 🟡 AWS Service Terms — Section 50.11: Model Extraction

> "Neither you nor your End Users will, or will attempt to, extract or derive
> underlying components, including any model, model parameters, or model
> weights or reproduce the training data of AI Services."
>
> — [AWS Service Terms, Section 50.11](https://aws.amazon.com/service-terms/)

**How Kiro Gateway relates:**

- The gateway does not extract model weights or training data. It proxies
  requests and responses without attempting to reverse-engineer the model
  itself.
- However, the act of reverse-engineering the API protocol, authentication
  flow, and request/response formats could be interpreted as "extracting
  or deriving underlying components" of the AI Service, depending on how
  broadly Amazon interprets this clause.

**Risk level: MEDIUM** — Arguable, but not the strongest claim.

---

### 5. 🟡 AWS Service Terms — Section 50.3: Data Use for Service Improvement

> "You agree and instruct that for... Kiro Free Tier, and Kiro individual
> subscribers: (a) we may use and store AI Content that is processed by each
> of the foregoing AI Services to develop and improve the applicable AI
> Service..."
>
> — [AWS Service Terms, Section 50.3](https://aws.amazon.com/service-terms/)

**How Kiro Gateway relates:**

- By modifying requests (injecting thinking tags, rewriting tool
  descriptions) before they reach the Kiro API, the gateway sends
  content to Amazon that differs from what the user originally intended.
  This pollutes the training/improvement data pipeline with synthetic
  modifications.
- Users on the Free Tier or individual plans cannot opt out of this data
  use without AWS Organizations. The gateway's modifications become part
  of the data Amazon uses for service improvement.

**Risk level: MEDIUM** — Indirect consequence, not a direct violation.

---

### 6. 🟡 User-Agent Impersonation

The gateway sends a hardcoded User-Agent string that impersonates the
Kiro IDE:

```
aws-sdk-js/1.0.27 ua/2.1 os/win32#10.0.19044 lang/js md/nodejs#22.21.1
api/codewhispererstreaming#1.0.27 m/E KiroIDE-0.7.45-{fingerprint}
```

**How this creates risk:**

- This misrepresents the client software to Amazon's servers. The gateway
  is not the Kiro IDE, not running on Windows, not using Node.js, and not
  using the AWS SDK for JavaScript.
- Amazon likely uses User-Agent strings for analytics, abuse detection,
  and feature gating. Spoofing this string could be considered a violation
  of the AWS Acceptable Use Policy's prohibition on violating "the
  security, integrity, or availability of any user, network, computer or
  communications system, software application, or network or computing
  device."
- If Amazon implements client verification or integrity checks, this
  impersonation would be the first thing to trigger detection.

**Risk level: MEDIUM** — Common in reverse-engineering projects, but
explicitly deceptive.

---

### 7. 🟡 AWS Service Terms — Section 50.5: Competing Service Development

> "Except where permitted by the AI Service, you may not use an AI Service
> to generate Content for the express purpose of training an AI model or
> service or developing a substantially similar AI model or service."
>
> — [AWS Service Terms, Section 50.5](https://aws.amazon.com/service-terms/)

**How Kiro Gateway relates:**

- The gateway itself is not an AI model or service — it is a proxy. It
  does not train models or develop competing AI.
- However, by exposing Kiro's capabilities through standard API formats,
  it enables use cases that Amazon may not have intended, such as
  integrating Kiro's models into third-party applications.

**Risk level: LOW** — Unlikely to apply unless the gateway is used
specifically for model training.

---

### 8. 🟡 AWS Service Terms — Section 50.14: Kiro-Specific Terms

> "If you purchase your Kiro subscription on a payment portal powered by
> Stripe, then for purposes of your use of Kiro, Amazon Web Services, Inc.
> is the AWS Contracting Party under the Agreement."
>
> — [AWS Service Terms, Section 50.14](https://aws.amazon.com/service-terms/)

**How Kiro Gateway relates:**

- This section is brief but establishes that Kiro usage falls under the
  full AWS Customer Agreement. All general AWS terms apply, including
  the IP License restrictions.
- There is no carve-out or exception for third-party API access.

**Risk level: INFORMATIONAL** — Confirms that all AWS terms apply.

---

### 9. 🟢 AWS Service Terms — Section 2: Betas and Previews

> "AWS may suspend or terminate your access to or use of any Beta Service
> or Beta Region at any time."
>
> — [AWS Service Terms, Section 2.4](https://aws.amazon.com/service-terms/)

**How Kiro Gateway relates:**

- Kiro was in preview/beta during its initial launch. If any features
  used by the gateway are still in preview, Amazon has even broader
  rights to suspend access without cause.
- Beta terms explicitly state that AWS can terminate access "at any time"
  and that content "may be deleted or inaccessible."

**Risk level: LOW** — Applies broadly to all Kiro users, not specific
to the gateway.

---

## Are Alternative Clients Explicitly Prohibited?

**No. The prohibition is implicit, not explicit.**

None of the reviewed terms contain language like "you may only access Kiro
through the official IDE or CLI" or "third-party clients are prohibited."
The restriction is structural — inferred from the scope of what is licensed
— rather than directly stated.

### What the terms actually say

1. **The Kiro License** states that the IDE and CLI are licensed as "AWS
   Content." It does not mention the underlying API as a separately
   available service. The API endpoints
   (`q.{region}.amazonaws.com/generateAssistantResponse`,
   `/ListAvailableModels`, `/mcp`) are undocumented internal endpoints.
   They are not listed in any AWS service documentation, do not have
   their own pricing page, and do not appear in the AWS SDK.

2. **The IP License §3** grants a license to use AWS Content "solely in
   connection with your permitted use of the Services." The "Services"
   here means Kiro-as-a-product (the IDE and CLI), not the raw HTTP
   endpoints behind it. The terms never say "you must use our client."
   The argument Amazon would make is: if the only licensed service is
   the IDE/CLI, then calling the backend API directly is not a
   "permitted use of the Services" — it is using something that was
   never offered as a service at all.

3. **The IP License §4** prohibits creating derivative works of AWS
   Content and sublicensing. This is the closest to an explicit
   prohibition, but it targets what you _do_ with the content, not
   _how you access_ it.

### What the terms do not say

For comparison, other AI providers have explicit prohibitions:

- **Anthropic's Terms** prohibit accessing their API "through any
  automated, deceptive, or unauthorized means."
- **OpenAI's Terms** prohibit "using any automated or programmatic
  method to extract data or output from the Services."

AWS's terms for Kiro contain no equivalent clause. The prohibition on
alternative clients must be inferred from the fact that the API was
never publicly documented or offered as a standalone service.

### Why this matters

This is a weaker enforcement position for Amazon. To act against an
alternative client, they would need to argue that accessing an
undocumented endpoint is inherently outside the scope of permitted use,
rather than pointing to a specific clause that says "do not do this."

The IP License's broad "solely in connection with your permitted use"
language gives Amazon room to make this argument, but it is less
predictable than an explicit prohibition. A user could counter-argue
that they are using the same service (Kiro) and simply accessing it
through a different interface, which the terms do not forbid.

**Bottom line:** Amazon could enforce against alternative clients, but
they would be relying on an implicit scope limitation rather than a
clear prohibition. This makes enforcement less predictable but not
impossible. The risk is real but the legal footing is ambiguous.

---

## Account Suspension Risk Assessment

### What could trigger enforcement

| Trigger                                                    | Likelihood | Detection Method                |
| ---------------------------------------------------------- | ---------- | ------------------------------- |
| Unusual API usage patterns (high volume, non-IDE patterns) | Medium     | Server-side analytics           |
| User-Agent mismatch with actual client behavior            | Medium     | Request fingerprinting          |
| API calls from non-IDE IP addresses or environments        | Low        | IP/environment correlation      |
| Public visibility of the project on GitHub                 | Medium     | Manual review, reports          |
| Automated abuse detection (Section 1.24.1)                 | Medium     | Amazon Bedrock abuse mechanisms |
| Community reports or competitor complaints                 | Low        | Manual review                   |

### What Amazon would likely do

Based on AWS's general enforcement patterns:

1. **Most likely first step:** Automated rate limiting or throttling of
   the account, possibly without notification.
2. **Second step:** Email notification citing a ToS violation with a
   request to cease the activity.
3. **Escalation:** Account suspension with an opportunity to appeal.
4. **Worst case:** Permanent account termination with loss of all
   associated data and services.

### Factors that increase risk

- Using the gateway with a **paid Kiro subscription** (Amazon has more
  incentive to protect paid service integrity)
- **High request volume** that exceeds normal IDE usage patterns
- **Sharing the gateway** with multiple users (sublicensing)
- Using the gateway for **commercial purposes**
- The project being **publicly available** on GitHub with clear
  documentation of how it reverse-engineers the API

### Factors that decrease risk

- Using the gateway for **personal, individual use only**
- **Low request volume** consistent with normal development usage
- Amazon's general **reluctance to enforce** against individual
  developers for non-abusive usage
- The gateway does not **extract model weights** or training data
- The gateway does not **resell access** commercially
- Kiro is still relatively **new** and Amazon may prioritize adoption
  over enforcement during this period

---

## Comparison with Similar Projects

Projects that reverse-engineer AI service APIs have a mixed enforcement
history:

- **ChatGPT reverse proxies:** OpenAI has actively shut down public
  proxies and revoked API keys used for unauthorized access.
- **GitHub Copilot proxies:** Microsoft/GitHub has been less aggressive
  but has updated authentication to break unauthorized clients.
- **Claude API proxies:** Anthropic has revoked keys and updated their
  ToS to explicitly prohibit proxy usage.

Amazon has historically been less aggressive about enforcing against
individual developers using AWS services in unconventional ways, but
this pattern may not hold for AI services where model access has direct
cost implications.

---

## Summary of Violations

| #   | Provision                                                             | Severity | Confidence |
| --- | --------------------------------------------------------------------- | -------- | ---------- |
| 1   | IP License §4 — License Restrictions (derivative works, sublicensing) | High     | High       |
| 2   | IP License §3 — Scope of License (use outside permitted services)     | High     | High       |
| 3   | Kiro License — Use outside licensed clients                           | High     | High       |
| 4   | Service Terms §50.11 — Component extraction (API reverse engineering) | Medium   | Medium     |
| 5   | Service Terms §50.3 — Data pollution from request modification        | Medium   | Low        |
| 6   | AUP — User-Agent impersonation                                        | Medium   | Medium     |
| 7   | Service Terms §50.5 — Competing service development                   | Low      | Low        |

---

## Recommendations

### If you decide to use Kiro Gateway

1. **Use your own credentials only.** Never share the gateway or your
   credentials with others. This avoids the sublicensing issue.
2. **Keep usage volume low.** Stay within patterns that look like normal
   IDE usage.
3. **Disable request modifications.** Set `FAKE_REASONING=false` and
   `WEB_SEARCH_ENABLED=false` to minimize the derivative works argument.
4. **Do not use for commercial purposes.** Personal experimentation
   carries less enforcement risk than commercial use.
5. **Have a backup plan.** Do not build critical workflows that depend
   on continued access through the gateway.
6. **Monitor your account.** Watch for any communications from Amazon
   about unusual usage or ToS concerns.

### If you want to avoid risk entirely

- Use Kiro through the official IDE or CLI only.
- If you need OpenAI-compatible API access to Claude models, use
  [Amazon Bedrock](https://aws.amazon.com/bedrock/) which provides
  official, documented API access with proper licensing.
- If you need Anthropic-compatible API access, use the
  [Anthropic API](https://docs.anthropic.com/) directly.

---

## Sources

All terms referenced in this document were accessed on April 22, 2026.
Content was rephrased for compliance with licensing restrictions. Direct
quotations are limited to 30 words or fewer per source.

- [AWS Customer Agreement](https://aws.amazon.com/agreement/app/)
- [AWS Intellectual Property License](https://aws.amazon.com/jp/legal/aws-ip-license-terms/)
- [AWS Service Terms](https://aws.amazon.com/service-terms/)
- [AWS Acceptable Use Policy](https://aws.amazon.com/aup/)
- [Kiro License](https://kiro.dev/license/)
- [Kiro Privacy and Security](https://kiro.dev/docs/privacy-and-security/)
