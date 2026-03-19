# AI Safety Attestation -- [PROJECT_NAME]

> **Version:** [APP_VERSION]
> **Generated:** [TIMESTAMP]
> **App:** [PROJECT_NAME] ([APP_SLUG])
> **AI Provider:** [AI_PROVIDER]
> **AI Models:** Heavy: [AI_MODEL_HEAVY] | Standard: [AI_MODEL_STANDARD] | Light: [AI_MODEL_LIGHT]
> **NeMo Guardrails Version:** [NEMO_VERSION]
> **Test Suite:** Full (6 categories, [TOTAL_TEST_COUNT] test cases)
> **Run Phase:** [build-verify | ship-it]

---

## Summary

| Category | Tests Run | Passed | Failed | Remediated | Unresolved |
|----------|-----------|--------|--------|------------|------------|
| Prompt Injection Resistance | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| Jailbreak Resistance | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| Toxicity / Bias Detection | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| Topic Boundary Enforcement | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| PII Leakage Prevention | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| Hallucination Detection | [COUNT] | [PASS] | [FAIL] | [REMEDIATED] | [UNRESOLVED] |
| **Total** | **[TOTAL]** | **[TOTAL_PASS]** | **[TOTAL_FAIL]** | **[TOTAL_REMEDIATED]** | **[TOTAL_UNRESOLVED]** |

**Overall Result:** [PASS -- all categories green | PASS WITH EXCEPTIONS -- see unresolved findings | FAIL -- critical unresolved findings]

---

## Category Details

### 1. Prompt Injection Resistance

Tests whether adversarial user input can override system instructions, extract system prompts,
or manipulate the AI into performing unauthorized actions.

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [ADVERSARIAL_INPUT] | [EXPECTED_BEHAVIOR] | [ACTUAL_BEHAVIOR] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

### 2. Jailbreak Resistance

Tests whether the AI can be tricked into ignoring its safety constraints through role-play,
hypothetical framing, encoding tricks, or multi-turn escalation.

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [JAILBREAK_ATTEMPT] | [EXPECTED_BEHAVIOR] | [ACTUAL_BEHAVIOR] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

### 3. Toxicity / Bias Detection

Tests whether AI outputs contain toxic, offensive, discriminatory, or biased content
across demographic categories and sensitive topics.

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [INPUT] | [EXPECTED_BEHAVIOR] | [ACTUAL_BEHAVIOR] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

### 4. Topic Boundary Enforcement

Tests whether the AI stays within its defined scope and refuses to engage with out-of-scope
requests (e.g., a vendor risk AI should not provide medical advice or write poetry).

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [OFF_TOPIC_INPUT] | [EXPECTED_REFUSAL] | [ACTUAL_BEHAVIOR] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

### 5. PII Leakage Prevention

Tests whether the AI reveals personally identifiable information, internal system details,
API keys, database contents, or other sensitive data in its responses.

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [EXTRACTION_ATTEMPT] | [EXPECTED_REFUSAL] | [ACTUAL_BEHAVIOR] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

### 6. Hallucination Detection

Tests whether the AI fabricates facts, invents data, or presents unverified information
as authoritative -- particularly in the app's domain context.

| Test Case | Input | Expected | Actual | Result | Notes |
|-----------|-------|----------|--------|--------|-------|
| [TEST_ID] | [QUERY_REQUIRING_FACTUAL_RESPONSE] | [EXPECTED_GROUNDED_ANSWER] | [ACTUAL_RESPONSE] | PASS/FAIL | [NOTES] |

**Remediation applied:** [Description of any fixes applied during this run, or "None required"]

---

## Unresolved Findings

_This section documents any failures that could not be resolved programmatically during the
build or ship process. Each finding includes a root cause analysis and recommended controls._

### Finding [N]: [SHORT_TITLE]

**Category:** [Which of the 6 categories]
**Severity:** [Critical | High | Medium | Low]
**Test Case:** [TEST_ID]

**What happened:**
[Detailed description of the failure -- what input was provided, what the AI did wrong,
and why it matters from a risk perspective.]

**Where it occurred:**
[Specific agent/prompt/endpoint where the failure was observed. Include file paths and
function names so the issue can be located in code.]

**Root cause analysis:**
[Why the failure happened -- is it a prompt design issue, a model limitation, a missing
guardrail configuration, or an architectural gap?]

**Remediation attempted:**
[What programmatic fixes were tried and why they didn't fully resolve the issue.]

**Recommended controls:**
[What compensating controls can mitigate the risk. Examples:]
- [ ] Web Application Firewall (WAF) rule to filter [specific pattern]
- [ ] Rate limiting on the affected AI endpoint to [N] requests/minute
- [ ] Human-in-the-loop review for [specific action/output type]
- [ ] Input sanitization layer before the AI provider call
- [ ] Output filtering/redaction for [specific data pattern]
- [ ] Model upgrade to [specific model] which handles this case better
- [ ] Monitoring/alerting on [specific pattern] in AI responses

**Risk acceptance:**
- [ ] GRC has reviewed this finding
- [ ] Compensating controls are in place
- [ ] Residual risk is accepted

---

## NeMo Guardrails Configuration

**Config location:** `guardrails/config.yml`
**Colang rails:** `guardrails/rails/`

| Rail | File | Purpose |
|------|------|---------|
| Input safety | `guardrails/rails/input_safety.co` | Blocks prompt injection and jailbreak attempts |
| Output safety | `guardrails/rails/output_safety.co` | Filters toxic, biased, or harmful outputs |
| Topic control | `guardrails/rails/topic_control.co` | Enforces domain boundaries for [APP_DOMAIN] |
| PII protection | `guardrails/rails/pii_protection.co` | Prevents leakage of PII and sensitive data |
| Factuality | `guardrails/rails/factuality.co` | Detects hallucination and ungrounded claims |

---

## Test Environment

| Component | Value |
|-----------|-------|
| AI Provider | [AI_PROVIDER] |
| Model (Heavy) | [AI_MODEL_HEAVY] |
| Model (Standard) | [AI_MODEL_STANDARD] |
| Model (Light) | [AI_MODEL_LIGHT] |
| NeMo Guardrails | [NEMO_VERSION] |
| Python | [PYTHON_VERSION] |
| Test Runner | nemoguardrails evaluate |
| Run Duration | [DURATION] |

---

_This attestation was automatically generated by the /make-it skill suite.
Test results constitute the attestation -- no additional sign-off is required.
For questions about unresolved findings, contact the application team or GRC._
