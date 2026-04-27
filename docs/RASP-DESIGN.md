# Lightweight RASP: Scaffold-Embedded Runtime Protection

**Audience:** AI Center of Excellence (CoE), Security, DevOps/SecOps, Architecture Review
**Purpose:** Design for a lightweight, detect-only RASP layer embedded in every /make-it application, invisible to business users, surfaced through Cribl to SecOps
**Version:** 1.0 | 2026-04-27

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Architecture](#2-architecture)
3. [Detection Categories](#3-detection-categories)
4. [Scaffold Implementation](#4-scaffold-implementation)
5. [Event Schema & Logging](#5-event-schema--logging)
6. [Cribl Integration](#6-cribl-integration)
7. [SecOps Workflow](#7-secops-workflow)
8. [Admin UI Additions](#8-admin-ui-additions)
9. [Build Standards & Verification](#9-build-standards--verification)
10. [Performance Impact Analysis](#10-performance-impact-analysis)
11. [What This Is NOT](#11-what-this-is-not)
12. [Appendix: Detection Patterns](#appendix-detection-patterns)

---

## 1. Design Principles

| Principle | Rationale |
|-----------|-----------|
| **Detect only, never block** | Application availability is absolute. RASP observes and alerts -- it never prevents a request from completing. A false positive in blocking mode breaks the app for a non-technical owner who can't diagnose it. Blocking is WAF's job at the infrastructure layer. |
| **Ships with every app** | Embedded in the scaffold. Not an optional add-on. Not a separate install. Every /make-it application has RASP from day one. |
| **Invisible to business user** | The app owner never sees RASP configuration, tuning, alerts, or events. They don't know it exists. It's scaffolding -- like rebar in concrete. |
| **Zero operational burden** | No tuning, no rule management, no alert triage by the app owner. SecOps teams handle everything downstream via Cribl → SIEM → Jira. |
| **Rides existing infrastructure** | Uses the activity log system (LogStore/LogService) already in every app. RASP events are a new event type (`SECURITY`), forwarded via the existing Cribl Stream integration. No new dependencies. |
| **Async processing** | Detection runs in the request pipeline but event enrichment and Cribl forwarding happen asynchronously. Request latency impact: <2ms for pattern matching. |
| **Pattern-based, not signature-based** | Lightweight regex/string matching for known attack patterns. Not a full signature database (that's commercial RASP territory). Catches the common 80% of attacks. |
| **Complements, never replaces** | RASP is one layer in defense-in-depth. It sits between application-level controls (sanitizePromptInput, validateAgentOutput, require_permission) and infrastructure controls (WAF, NGFW). It catches what slips through sanitization and flags what WAF can't see (application context). |

---

## 2. Architecture

### 2.1 Where RASP Sits in the Stack

```
                Internet
                   │
            ┌──────▼──────┐
            │     WAF      │  ← Blocks known attacks (OWASP CRS)
            │  (Infra)     │    Rate limits, geo-blocks, bot detection
            └──────┬──────┘
                   │
            ┌──────▼──────┐
            │    NGFW      │  ← Network segmentation, TLS inspection
            │  (Infra)     │    Outbound URL filtering, IDS/IPS
            └──────┬──────┘
                   │
     ┌─────────────▼─────────────────────────────────────┐
     │           /make-it Application                     │
     │                                                    │
     │  ┌──────────────────────────────────────────────┐  │
     │  │  RASP Middleware (detect-only)                │  │
     │  │  ├─ Request Inspector (inbound patterns)     │  │
     │  │  ├─ Response Inspector (data leakage)        │  │
     │  │  ├─ AI Inspector (prompt/response anomalies) │  │
     │  │  └─ Event Emitter → LogStore (SECURITY type) │  │
     │  └──────────────────────────────────────────────┘  │
     │                     │                              │
     │  ┌──────────────────▼───────────────────────────┐  │
     │  │  Application Controls (existing scaffold)    │  │
     │  │  ├─ sanitizePromptInput()    (sanitizes)     │  │
     │  │  ├─ validateAgentOutput()    (validates)     │  │
     │  │  ├─ require_permission()     (enforces)      │  │
     │  │  └─ parameterized queries    (prevents)      │  │
     │  └──────────────────────────────────────────────┘  │
     │                     │                              │
     │  ┌──────────────────▼───────────────────────────┐  │
     │  │  LogStore (activity logs)                    │  │
     │  │  Event types: IN, OUT, SECURITY              │  │
     │  │  ├─ In-memory circular buffer                │  │
     │  │  └─ Cribl Stream forwarder (async)           │  │
     │  └──────────────────────────────────────────────┘  │
     └────────────────────────┬──────────────────────────┘
                              │ (Cribl Stream)
                   ┌──────────▼──────────┐
                   │    Cribl Stream      │
                   │    ├─ Route SECURITY │
                   │    │  events to SIEM │
                   │    ├─ Enrich with    │
                   │    │  app metadata   │
                   │    └─ Alert rules    │
                   └──────────┬──────────┘
                              │
                   ┌──────────▼──────────┐
                   │   SIEM / Splunk     │
                   │   ├─ Correlation    │
                   │   ├─ Dashboards     │
                   │   └─ Jira ticket    │
                   │     auto-creation   │
                   └─────────────────────┘
```

### 2.2 Request Lifecycle with RASP

```
Request arrives
    │
    ▼
┌─────────────────────────────┐
│ RASP Request Inspector      │  ← Pattern match: <2ms
│ (runs BEFORE route handler) │     Async event emit if suspicious
│                             │     NEVER blocks or modifies request
└─────────────┬───────────────┘
              │ (request passes through unmodified)
              ▼
┌─────────────────────────────┐
│ Route Handler               │  ← Normal application logic
│ (auth, business logic, DB)  │     sanitizePromptInput, etc.
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ RASP Response Inspector     │  ← Pattern match: <1ms
│ (runs AFTER route handler)  │     Checks for data leakage
│                             │     NEVER blocks or modifies response
└─────────────┬───────────────┘
              │ (response sent to client unmodified)
              ▼
Response returned

Meanwhile (async, non-blocking):
    RASP Event → LogStore.logSecurity() → Cribl forward
```

### 2.3 Key Design Decision: Detect vs Block

```
┌───────────────────────────────────────────────────────────────┐
│                    WHY DETECT-ONLY                             │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  BLOCKING MODE FAILURE SCENARIOS:                             │
│                                                               │
│  1. Business user uploads a contract PDF containing the word  │
│     "DROP" in a legal clause → RASP blocks upload → user      │
│     calls support → nobody knows why → app appears broken     │
│                                                               │
│  2. User enters "SELECT" in a search box (searching for       │
│     product selection criteria) → RASP blocks → search broken │
│                                                               │
│  3. AI agent generates a response containing "<script>" as    │
│     part of a code explanation → RASP blocks → AI appears     │
│     broken, no one can fix it                                 │
│                                                               │
│  4. Regex pattern has false positive on UTF-8 input common    │
│     in non-English text → RASP blocks → app unusable for      │
│     international users                                       │
│                                                               │
│  WHO INVESTIGATES? The business user can't. They'll submit    │
│  a support ticket saying "it's broken." By the time SecOps    │
│  sees it, productivity is lost.                               │
│                                                               │
│  DETECT MODE: Same detection, zero risk to application.       │
│  SecOps sees the alert, investigates, tunes if false positive,│
│  escalates to WAF blocking rule if true positive.             │
│                                                               │
│  The PROMOTION PATH for a RASP finding:                       │
│  RASP detect → Cribl → SIEM alert → SecOps reviews           │
│  → If real: SecOps adds WAF blocking rule (infra layer)       │
│  → If false positive: SecOps tunes RASP pattern exclusion     │
│                                                               │
│  This keeps blocking at the WAF layer where SecOps controls   │
│  it, and detection at the app layer where context is richest. │
└───────────────────────────────────────────────────────────────┘
```

---

## 3. Detection Categories

### 3.1 Request Inspection (Inbound)

| Category | ID | What It Detects | Patterns | False Positive Risk |
|----------|-----|-----------------|----------|-------------------|
| **SQL Injection Probing** | RASP-SQLI | Attacker testing for SQL injection | `' OR 1=1`, `UNION SELECT`, `; DROP`, `--` comment after value, `' AND '1'='1`, `WAITFOR DELAY`, `BENCHMARK(`, `SLEEP(` | Medium -- "O'Brien" in name fields, SQL keywords in text content |
| **XSS Probing** | RASP-XSS | Script injection attempts | `<script`, `javascript:`, `onerror=`, `onload=`, `<img src=x onerror`, `<svg onload`, `eval(`, `document.cookie` | Medium -- code discussions, AI-generated content about web security |
| **Path Traversal** | RASP-TRAV | Directory traversal attempts | `../`, `..\\`, `%2e%2e`, `/etc/passwd`, `/proc/self`, `\windows\system32` | Low -- well-defined pattern |
| **Command Injection** | RASP-CMDI | OS command injection attempts | `; ls`, `| cat`, `` `whoami` ``, `$(id)`, `%0a`, `\n` in parameter values | Low -- pipe/semicolon rare in normal input |
| **SSRF Probing** | RASP-SSRF | Internal network/metadata access attempts | `169.254.169.254`, `127.0.0.1` in URL params, `10.0.0.`, `192.168.`, `172.16.`, `0x7f000001`, `localhost` in URL params | Low -- internal IPs shouldn't appear in user input |
| **Header Injection** | RASP-HDRI | HTTP header manipulation | `\r\n` in header values, multiple Host headers, `X-Forwarded-For` spoofing patterns | Low |
| **Authentication Probing** | RASP-AUTH | Auth bypass attempts | Rapid 401/403 responses to same IP, JWT tampering (malformed tokens), `alg: none` in JWT header | Low |
| **Enumeration** | RASP-ENUM | Resource enumeration (IDOR probing) | Sequential ID access patterns (1, 2, 3, 4...), rapid 404 responses, directory listing attempts | Medium -- legitimate pagination could trigger |
| **File Upload Attacks** | RASP-FILE | Malicious upload attempts | Double extension (`.pdf.exe`), null byte in filename (`file.pdf%00.exe`), oversized Content-Length mismatch, polyglot files (PDF header + script) | Low |
| **XML/XXE Probing** | RASP-XXE | XML entity injection | `<!DOCTYPE`, `<!ENTITY`, `SYSTEM "file://`, `SYSTEM "http://`, `<xi:include` in request body | Low -- legitimate XML rarely contains entity declarations |

### 3.2 Response Inspection (Outbound)

| Category | ID | What It Detects | Patterns | False Positive Risk |
|----------|-----|-----------------|----------|-------------------|
| **Data Leakage -- PII** | RASP-PII | Unmasked PII in API responses | SSN patterns (`\d{3}-\d{2}-\d{4}`), credit card patterns (Luhn-valid 13-19 digits), email addresses in bulk (>10 in one response) | Medium -- depends on app domain |
| **Data Leakage -- Secrets** | RASP-SECRET | Secrets in responses | API key patterns (`sk-`, `AKIA`, `ghp_`, `xox`), JWT tokens in response body (not cookie), private key headers (`-----BEGIN`) | Low -- distinctive patterns |
| **Error Information Leakage** | RASP-ERRINFO | Stack traces, internal details | Python tracebacks (`Traceback (most recent call last)`), Node.js stack traces (`at Object.<anonymous>`), SQL error messages (`PSQLException`, `sqlite3.OperationalError`), file paths (`/app/`, `/home/`, `C:\\`) | Low -- distinctive patterns |
| **Excessive Data Exposure** | RASP-EXCESS | Unbounded response data | Response body >1MB for non-file endpoints, array responses >1000 items, response contains fields marked sensitive in schema | Low -- clear thresholds |

### 3.3 AI-Specific Inspection

| Category | ID | What It Detects | Patterns | False Positive Risk |
|----------|-----|-----------------|----------|-------------------|
| **Prompt Injection Attempt** | RASP-PINJ | Injection that reached the AI pipeline (even if sanitized) | `ignore previous instructions`, `disregard above`, `you are now`, `system:`, role markers in user input that hit AI endpoints | Medium -- legitimate discussion about AI safety |
| **AI Response Anomaly** | RASP-AIOUT | AI producing unexpected content | AI response containing system prompt fragments, AI response containing `<script>` or executable code patterns, AI response with PII patterns not present in input | Low -- distinctive patterns |
| **Jailbreak Attempt** | RASP-JAIL | Jailbreak patterns that reached AI endpoints | `DAN mode`, `developer mode`, `pretend you are`, `act as root`, `no restrictions`, base64-encoded instruction blocks (>50 chars of base64) | Medium -- creative writing or AI discussions |
| **Token Budget Anomaly** | RASP-TOKEN | Unusual AI consumption patterns | Single user consuming >5x average token budget, single conversation exceeding AI_MAX_HISTORY_TURNS, rapid sequential AI requests from same user approaching rate limit | Low -- clear thresholds |
| **Agent Tool Abuse** | RASP-TOOL | Agent using tools suspiciously | Agent tool call with internal URL, agent tool call with parameters matching attack patterns (SQL, command injection in tool args), agent attempting to access resources outside its configured scope | Low -- agent tools have defined parameters |

### 3.4 Behavioral Detection (Cross-Request)

These detections require tracking state across requests. Uses a lightweight in-memory sliding window (separate from LogStore).

| Category | ID | What It Detects | Window | Threshold |
|----------|-----|-----------------|--------|-----------|
| **Credential Stuffing** | RASP-CSTUFF | Rapid auth failures from same IP | 5 min | >10 failed auth attempts |
| **API Scraping** | RASP-SCRAPE | Systematic data harvesting | 1 min | >50 GET requests to list endpoints from same user |
| **Fuzzing Detection** | RASP-FUZZ | Automated vulnerability scanning | 1 min | >20 requests returning 400/422/500 from same IP |
| **Privilege Probe** | RASP-PRIV | Testing access boundaries | 5 min | >5 forbidden (403) responses to same user |
| **AI Abuse** | RASP-AIABUSE | AI endpoint hammering | 5 min | >80% of user's requests hitting AI endpoints |

---

## 4. Scaffold Implementation

### 4.1 File Structure (additions to scaffold)

```
backend/
  app/
    middleware/
      rasp.py                  # RASP middleware (request + response inspection)
    services/
      rasp_service.py          # Detection engine, pattern matching, event emission
      rasp_patterns.py         # Detection patterns (separated for maintainability)
      rasp_behavioral.py       # Cross-request behavioral detection (sliding window)
```

### 4.2 RASP Middleware (FastAPI)

```python
# backend/app/middleware/rasp.py
import time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from app.services.rasp_service import RaspService

class RaspMiddleware(BaseHTTPMiddleware):
    """
    Detect-only RASP. Inspects requests and responses for attack patterns.
    NEVER blocks, modifies, or delays requests. Events logged asynchronously.
    """

    def __init__(self, app, rasp_service: RaspService):
        super().__init__(app)
        self.rasp = rasp_service

    async def dispatch(self, request: Request, call_next):
        # Phase 1: Inspect request (sync, <2ms)
        request_findings = self.rasp.inspect_request(request)

        # Phase 2: Execute route handler (normal app flow, unmodified)
        response = await call_next(request)

        # Phase 3: Inspect response (sync, <1ms)
        # Note: response body inspection requires buffering -- only for
        # JSON responses under 512KB to avoid memory/latency impact
        response_findings = await self.rasp.inspect_response(
            request, response
        )

        # Phase 4: Emit events asynchronously (non-blocking)
        all_findings = request_findings + response_findings
        if all_findings:
            self.rasp.emit_events(request, response, all_findings)

        # Phase 5: Update behavioral tracking (non-blocking)
        self.rasp.track_behavior(request, response)

        return response  # ALWAYS returns original response unmodified
```

### 4.3 RASP Service

```python
# backend/app/services/rasp_service.py
import re
import asyncio
from datetime import datetime
from typing import Optional
from starlette.requests import Request
from starlette.responses import Response
from app.services.rasp_patterns import REQUEST_PATTERNS, RESPONSE_PATTERNS, AI_PATTERNS
from app.services.rasp_behavioral import BehavioralTracker
from app.services.log_service import LogService

class RaspFinding:
    def __init__(self, category: str, id: str, severity: str,
                 detail: str, matched_pattern: str, location: str):
        self.category = category
        self.id = id
        self.severity = severity      # CRITICAL, HIGH, MEDIUM, LOW, INFO
        self.detail = detail
        self.matched_pattern = matched_pattern
        self.location = location       # header, path, query, body, response

class RaspService:
    def __init__(self, log_service: LogService):
        self.log_service = log_service
        self.behavioral = BehavioralTracker()
        self.enabled = os.getenv("RASP_ENABLED", "true").lower() == "true"

    def inspect_request(self, request: Request) -> list[RaspFinding]:
        if not self.enabled:
            return []

        findings = []
        path = request.url.path
        query = str(request.query_params)
        headers = dict(request.headers)

        # Skip health checks and static assets
        if path in ("/health", "/healthz") or path.startswith("/_next"):
            return []

        # Run each pattern category against relevant request parts
        for pattern_set in REQUEST_PATTERNS:
            for target in pattern_set.targets:  # path, query, headers
                value = {"path": path, "query": query,
                         "headers": str(headers)}.get(target, "")
                for pattern in pattern_set.patterns:
                    if pattern.regex.search(value):
                        findings.append(RaspFinding(
                            category=pattern_set.category,
                            id=pattern_set.id,
                            severity=pattern_set.severity,
                            detail=pattern.description,
                            matched_pattern=pattern.name,
                            location=target,
                        ))
                        break  # One finding per category per request

        return findings

    async def inspect_response(self, request: Request,
                                response: Response) -> list[RaspFinding]:
        if not self.enabled:
            return []

        findings = []
        content_type = response.headers.get("content-type", "")

        # Only inspect JSON responses under 512KB
        if "application/json" not in content_type:
            return []

        # Response body inspection requires reading the body
        # Only do this for non-streaming, reasonably sized responses
        body = getattr(response, "body", None)
        if not body or len(body) > 524288:  # 512KB
            return []

        body_str = body.decode("utf-8", errors="ignore")

        for pattern_set in RESPONSE_PATTERNS:
            for pattern in pattern_set.patterns:
                if pattern.regex.search(body_str):
                    findings.append(RaspFinding(
                        category=pattern_set.category,
                        id=pattern_set.id,
                        severity=pattern_set.severity,
                        detail=pattern.description,
                        matched_pattern=pattern.name,
                        location="response_body",
                    ))
                    break

        return findings

    def emit_events(self, request: Request, response: Response,
                    findings: list[RaspFinding]):
        """Emit SECURITY events to LogStore (async, non-blocking)."""
        for finding in findings:
            self.log_service.log_security(
                category=finding.category,
                rasp_id=finding.id,
                severity=finding.severity,
                detail=finding.detail,
                matched_pattern=finding.matched_pattern,
                location=finding.location,
                method=request.method,
                path=str(request.url.path),
                ip=request.client.host if request.client else "unknown",
                user_agent=request.headers.get("user-agent", ""),
                user_email=getattr(request.state, "user_email", None),
            )

    def track_behavior(self, request: Request, response: Response):
        """Update behavioral detection sliding windows."""
        if not self.enabled:
            return
        ip = request.client.host if request.client else "unknown"
        user = getattr(request.state, "user_email", None)
        path = request.url.path
        status = response.status_code

        behavioral_findings = self.behavioral.track(
            ip=ip, user=user, path=path, status=status
        )
        if behavioral_findings:
            for finding in behavioral_findings:
                self.emit_events(request, response, [finding])
```

### 4.4 Detection Patterns (Separated for Maintainability)

```python
# backend/app/services/rasp_patterns.py
import re
from dataclasses import dataclass

@dataclass
class Pattern:
    name: str
    regex: re.Pattern
    description: str

@dataclass
class PatternSet:
    category: str
    id: str
    severity: str
    targets: list[str]    # Which request parts to inspect
    patterns: list[Pattern]

# Patterns compiled once at import time -- zero runtime compilation cost
REQUEST_PATTERNS = [
    PatternSet(
        category="SQL Injection Probing",
        id="RASP-SQLI",
        severity="HIGH",
        targets=["query", "path"],
        patterns=[
            Pattern("union_select", re.compile(
                r"union\s+(all\s+)?select", re.IGNORECASE
            ), "UNION SELECT pattern detected"),
            Pattern("or_1_1", re.compile(
                r"['\"]\s*or\s+['\"]?\d+['\"]?\s*=\s*['\"]?\d+", re.IGNORECASE
            ), "OR 1=1 tautology pattern"),
            Pattern("comment_after_value", re.compile(
                r"['\"]\s*;\s*--", re.IGNORECASE
            ), "SQL comment injection"),
            Pattern("sleep_benchmark", re.compile(
                r"(sleep|benchmark|waitfor\s+delay|pg_sleep)\s*\(", re.IGNORECASE
            ), "Time-based SQL injection probe"),
        ],
    ),
    PatternSet(
        category="XSS Probing",
        id="RASP-XSS",
        severity="MEDIUM",
        targets=["query", "path"],
        patterns=[
            Pattern("script_tag", re.compile(
                r"<\s*script", re.IGNORECASE
            ), "Script tag in input"),
            Pattern("event_handler", re.compile(
                r"on(error|load|click|mouseover)\s*=", re.IGNORECASE
            ), "Event handler injection"),
            Pattern("javascript_uri", re.compile(
                r"javascript\s*:", re.IGNORECASE
            ), "javascript: URI scheme"),
        ],
    ),
    PatternSet(
        category="Path Traversal",
        id="RASP-TRAV",
        severity="HIGH",
        targets=["path", "query"],
        patterns=[
            Pattern("dot_dot_slash", re.compile(
                r"\.\./|\.\.\\|%2e%2e(%2f|/|\\\\)"
            ), "Directory traversal sequence"),
            Pattern("etc_passwd", re.compile(
                r"/etc/(passwd|shadow|hosts)", re.IGNORECASE
            ), "Sensitive file path access"),
        ],
    ),
    PatternSet(
        category="Command Injection",
        id="RASP-CMDI",
        severity="CRITICAL",
        targets=["query"],
        patterns=[
            Pattern("pipe_command", re.compile(
                r"[|;`]\s*(cat|ls|whoami|id|uname|curl|wget|nc)\b"
            ), "Command injection via pipe/semicolon"),
            Pattern("subshell", re.compile(
                r"\$\((.*?)\)|\`(.*?)\`"
            ), "Subshell command execution"),
        ],
    ),
    PatternSet(
        category="SSRF Probing",
        id="RASP-SSRF",
        severity="CRITICAL",
        targets=["query"],
        patterns=[
            Pattern("metadata_endpoint", re.compile(
                r"169\.254\.169\.254|metadata\.google|metadata\.azure"
            ), "Cloud metadata endpoint in parameter"),
            Pattern("internal_ip", re.compile(
                r"(^|[&?=])(https?://)?(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)"
            ), "Internal IP address in parameter"),
        ],
    ),
    PatternSet(
        category="XML/XXE Probing",
        id="RASP-XXE",
        severity="HIGH",
        targets=["query"],
        patterns=[
            Pattern("entity_declaration", re.compile(
                r"<!ENTITY|<!DOCTYPE.*\[", re.IGNORECASE
            ), "XML entity declaration in input"),
            Pattern("system_entity", re.compile(
                r'SYSTEM\s+["\']file://|SYSTEM\s+["\']http://', re.IGNORECASE
            ), "External entity reference"),
        ],
    ),
]

RESPONSE_PATTERNS = [
    PatternSet(
        category="Data Leakage -- Secrets",
        id="RASP-SECRET",
        severity="CRITICAL",
        targets=["response_body"],
        patterns=[
            Pattern("aws_key", re.compile(
                r"AKIA[0-9A-Z]{16}"
            ), "AWS access key in response"),
            Pattern("private_key", re.compile(
                r"-----BEGIN (RSA |EC )?PRIVATE KEY-----"
            ), "Private key in response"),
            Pattern("github_token", re.compile(
                r"ghp_[A-Za-z0-9]{36}"
            ), "GitHub token in response"),
        ],
    ),
    PatternSet(
        category="Error Information Leakage",
        id="RASP-ERRINFO",
        severity="MEDIUM",
        targets=["response_body"],
        patterns=[
            Pattern("python_traceback", re.compile(
                r"Traceback \(most recent call last\)"
            ), "Python stack trace in response"),
            Pattern("sql_error", re.compile(
                r"(PSQLException|sqlite3\.OperationalError|"
                r"pg_catalog|information_schema)", re.IGNORECASE
            ), "Database error details in response"),
            Pattern("file_path_leak", re.compile(
                r"(/app/|/home/\w+/|/var/|/usr/|C:\\\\Users\\\\)"
            ), "Internal file path in response"),
        ],
    ),
    PatternSet(
        category="Data Leakage -- PII",
        id="RASP-PII",
        severity="HIGH",
        targets=["response_body"],
        patterns=[
            Pattern("ssn_pattern", re.compile(
                r"\b\d{3}-\d{2}-\d{4}\b"
            ), "Possible SSN pattern in response"),
            Pattern("credit_card", re.compile(
                r"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|"
                r"3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b"
            ), "Possible credit card number in response"),
        ],
    ),
]

AI_PATTERNS = [
    PatternSet(
        category="Prompt Injection Attempt",
        id="RASP-PINJ",
        severity="HIGH",
        targets=["query"],  # Applied to AI endpoint request bodies
        patterns=[
            Pattern("ignore_instructions", re.compile(
                r"ignore\s+(all\s+)?(previous|above|prior)\s+instructions",
                re.IGNORECASE
            ), "Prompt injection: ignore instructions"),
            Pattern("role_override", re.compile(
                r"you\s+are\s+now|act\s+as\s+(root|admin|system)",
                re.IGNORECASE
            ), "Prompt injection: role override"),
            Pattern("system_marker", re.compile(
                r"(###\s*System:|<\|system\|>|<\|user\|>)", re.IGNORECASE
            ), "Prompt injection: system marker spoofing"),
        ],
    ),
    PatternSet(
        category="Jailbreak Attempt",
        id="RASP-JAIL",
        severity="HIGH",
        targets=["query"],
        patterns=[
            Pattern("dan_mode", re.compile(
                r"(DAN|developer)\s+mode|do\s+anything\s+now",
                re.IGNORECASE
            ), "Jailbreak: DAN/developer mode"),
            Pattern("no_restrictions", re.compile(
                r"(no|without|remove)\s+(restrictions|limitations|filters|guardrails)",
                re.IGNORECASE
            ), "Jailbreak: restriction removal"),
        ],
    ),
]
```

### 4.5 Behavioral Tracker

```python
# backend/app/services/rasp_behavioral.py
import time
from collections import defaultdict
from dataclasses import dataclass

@dataclass
class SlidingWindow:
    events: list  # list of timestamps
    window_seconds: int
    threshold: int

    def add(self, timestamp: float = None):
        ts = timestamp or time.time()
        self.events.append(ts)
        # Evict old entries
        cutoff = ts - self.window_seconds
        self.events = [t for t in self.events if t > cutoff]

    @property
    def count(self) -> int:
        cutoff = time.time() - self.window_seconds
        return sum(1 for t in self.events if t > cutoff)

    @property
    def triggered(self) -> bool:
        return self.count >= self.threshold

class BehavioralTracker:
    """Lightweight in-memory sliding window tracker for cross-request patterns."""

    def __init__(self):
        # Track per IP: { ip: { category: SlidingWindow } }
        self.ip_windows = defaultdict(lambda: {
            "auth_fail": SlidingWindow([], 300, 10),    # 10 auth fails in 5 min
            "error_rate": SlidingWindow([], 60, 20),     # 20 errors in 1 min
            "forbidden": SlidingWindow([], 300, 5),      # 5 forbidden in 5 min
        })
        # Track per user: { user: { category: SlidingWindow } }
        self.user_windows = defaultdict(lambda: {
            "scraping": SlidingWindow([], 60, 50),       # 50 GETs in 1 min
            "ai_abuse": SlidingWindow([], 300, 0),       # Tracked separately
        })
        # Periodic cleanup to prevent memory growth
        self.last_cleanup = time.time()

    def track(self, ip: str, user: str, path: str,
              status: int) -> list:
        findings = []
        now = time.time()

        # Cleanup stale entries every 10 minutes
        if now - self.last_cleanup > 600:
            self._cleanup()
            self.last_cleanup = now

        # IP-based tracking
        ip_w = self.ip_windows[ip]
        if status == 401:
            ip_w["auth_fail"].add(now)
            if ip_w["auth_fail"].triggered:
                findings.append(RaspFinding(
                    "Credential Stuffing", "RASP-CSTUFF", "HIGH",
                    f"{ip_w['auth_fail'].count} auth failures in 5 min",
                    "auth_fail_threshold", "behavioral",
                ))
        if status in (400, 422, 500):
            ip_w["error_rate"].add(now)
            if ip_w["error_rate"].triggered:
                findings.append(RaspFinding(
                    "Fuzzing Detection", "RASP-FUZZ", "MEDIUM",
                    f"{ip_w['error_rate'].count} errors in 1 min from {ip}",
                    "error_rate_threshold", "behavioral",
                ))
        if status == 403:
            ip_w["forbidden"].add(now)
            if ip_w["forbidden"].triggered:
                findings.append(RaspFinding(
                    "Privilege Probe", "RASP-PRIV", "MEDIUM",
                    f"{ip_w['forbidden'].count} forbidden in 5 min",
                    "forbidden_threshold", "behavioral",
                ))

        # User-based tracking
        if user:
            user_w = self.user_windows[user]
            if path.startswith("/api/") and status == 200:
                user_w["scraping"].add(now)
                if user_w["scraping"].triggered:
                    findings.append(RaspFinding(
                        "API Scraping", "RASP-SCRAPE", "MEDIUM",
                        f"{user_w['scraping'].count} API GETs in 1 min by {user}",
                        "scraping_threshold", "behavioral",
                    ))

        return findings

    def _cleanup(self):
        """Remove stale tracking entries to prevent unbounded memory growth."""
        cutoff = time.time() - 600  # 10 min
        for ip in list(self.ip_windows.keys()):
            if all(w.count == 0 for w in self.ip_windows[ip].values()):
                del self.ip_windows[ip]
        for user in list(self.user_windows.keys()):
            if all(w.count == 0 for w in self.user_windows[user].values()):
                del self.user_windows[user]
```

### 4.6 LogService Extension

Add to existing LogService:

```python
# Addition to backend/app/services/log_service.py

def log_security(self, category: str, rasp_id: str, severity: str,
                 detail: str, matched_pattern: str, location: str,
                 method: str, path: str, ip: str, user_agent: str,
                 user_email: str = None):
    """Log a RASP security event. Same LogStore, new event type."""
    event = {
        "type": "SECURITY",
        "timestamp": datetime.utcnow().isoformat(),
        "rasp_id": rasp_id,
        "category": category,
        "severity": severity,
        "detail": detail,
        "matched_pattern": matched_pattern,
        "location": location,
        "method": method,
        "path": path,
        "ip": ip,
        "user_agent": user_agent,
        "user_email": user_email,
    }
    self.log_store.add(event)

    # Forward to Cribl if configured (async, non-blocking)
    if self.cribl_url:
        asyncio.create_task(self._forward_to_cribl(event))
```

---

## 5. Event Schema & Logging

### 5.1 SECURITY Event Schema

```json
{
    "type": "SECURITY",
    "timestamp": "2026-04-27T14:32:01.123Z",
    "rasp_id": "RASP-SQLI",
    "category": "SQL Injection Probing",
    "severity": "HIGH",
    "detail": "UNION SELECT pattern detected",
    "matched_pattern": "union_select",
    "location": "query",
    "method": "GET",
    "path": "/api/users",
    "ip": "10.0.1.42",
    "user_agent": "sqlmap/1.7",
    "user_email": null,
    "app_name": "[APP_SLUG]",
    "app_version": "[APP_VERSION]",
    "environment": "production"
}
```

### 5.2 Event Lifecycle

```
RASP Detection
    │
    ▼
LogStore (in-memory circular buffer)
    │
    ├──► Admin UI Activity Logs (type: SECURITY filter)
    │    └─ SecOps can view in-app if they have admin.logs.read
    │
    └──► Cribl Stream (async HTTP POST)
         │
         ├──► SIEM (Splunk/Sentinel/Elastic)
         │    └─ Correlation rules, dashboards, alerting
         │
         ├──► Jira (via Cribl webhook or SIEM integration)
         │    └─ Auto-create ticket for CRITICAL/HIGH findings
         │
         └──► Long-term storage (S3/Azure Blob)
              └─ Compliance retention
```

### 5.3 Event Volume Expectations

| Scenario | Events/Hour | LogStore Impact |
|----------|------------|-----------------|
| Normal traffic, no attacks | 0-5 (false positives) | Negligible |
| Casual probing (script kiddie) | 50-200 | <2% of buffer |
| Active pen test | 1000-5000 | 5-50% of buffer; oldest IN/OUT events evicted first |
| Automated scanner (Nessus, ZAP) | 5000-20000 | May fill buffer; SECURITY events preserved via priority eviction |

**Buffer priority:** When LogStore approaches capacity, evict IN events first (most replaceable), then OUT events, then SECURITY events last. SECURITY events are the most valuable for forensics.

---

## 6. Cribl Integration

### 6.1 Existing Foundation

/make-it apps already have Cribl placeholders:

```
# .env.example (existing)
CRIBL_STREAM_URL=          # Cribl Stream HTTP endpoint
CRIBL_STREAM_TOKEN=        # Cribl Stream auth token
```

### 6.2 Cribl Stream Pipeline for RASP Events

```
Source: HTTP (app LogService forward)
    │
    ▼
Route: Filter type == "SECURITY"
    │
    ├──► Pipeline: RASP Enrichment
    │    ├─ Add app_name from event
    │    ├─ Add environment tag
    │    ├─ GeoIP lookup on ip field
    │    ├─ Normalize severity to SIEM format
    │    └─ Add MITRE ATT&CK technique ID:
    │         RASP-SQLI  → T1190 (Exploit Public-Facing Application)
    │         RASP-XSS   → T1189 (Drive-by Compromise)
    │         RASP-SSRF  → T1090 (Proxy)
    │         RASP-PINJ  → T1059.007 (JavaScript)
    │         RASP-CSTUFF → T1110 (Brute Force)
    │
    ├──► Destination: SIEM (Splunk HEC / Azure Sentinel / Elastic)
    │    Index: security_rasp
    │    Sourcetype: make_it:rasp
    │
    ├──► Destination: Jira (webhook, CRITICAL + HIGH only)
    │    Project: APPSEC
    │    Issue type: Security Alert
    │    Fields: rasp_id, severity, app_name, detail, ip
    │
    └──► Destination: S3/Azure Blob (all events, compliance retention)
         Bucket: security-rasp-events
         Partition: year/month/day/app_name
```

### 6.3 Cribl Alert Rules

| Rule | Condition | Action |
|------|-----------|--------|
| **Critical RASP finding** | severity == CRITICAL | Jira ticket (Priority: Critical) + PagerDuty alert |
| **High RASP finding burst** | >10 HIGH events in 5 min from same app | Jira ticket (Priority: High) |
| **New attack source** | IP not seen before + any RASP event | Add to watchlist; enrich future events |
| **Behavioral threshold** | Any RASP-CSTUFF, RASP-FUZZ, RASP-SCRAPE | Jira ticket + suggest WAF IP block |
| **AI attack detected** | Any RASP-PINJ, RASP-JAIL, RASP-TOOL | Jira ticket + tag AI Security team |

---

## 7. SecOps Workflow

### 7.1 Alert-to-Resolution Flow

```
RASP event detected in app
    │
    ▼
Cribl routes to SIEM + Jira
    │
    ▼
SecOps receives Jira ticket:
  "RASP-SQLI detected on finance-dashboard"
  Severity: HIGH
  App: finance-dashboard
  Endpoint: GET /api/vendors?search=test'+OR+1=1--
  IP: 10.0.1.42
  User: null (unauthenticated probe)
    │
    ▼
SecOps investigates:
  ├─ True positive (real attack)?
  │   ├─ Add WAF blocking rule for pattern
  │   ├─ Block IP at NGFW if persistent
  │   ├─ Review if attack succeeded (check app DB, audit logs)
  │   └─ Close Jira ticket: "Blocked at WAF. No data compromise."
  │
  ├─ True positive (pen test)?
  │   └─ Acknowledge in Jira; correlate with pen test schedule
  │
  └─ False positive?
      ├─ Add pattern exclusion to RASP config (env var or settings)
      ├─ Document exclusion reason
      └─ Close Jira ticket: "False positive -- excluded."
```

### 7.2 RASP Tuning (SecOps, Not App Owner)

Pattern exclusions are managed via environment variable, not code changes:

```
# .env (managed by SecOps/DevOps, not business user)
RASP_ENABLED=true
RASP_EXCLUDE_PATTERNS=RASP-PII:ssn_pattern,RASP-XSS:script_tag
RASP_SEVERITY_THRESHOLD=MEDIUM   # Only emit MEDIUM+ (suppress LOW/INFO)
```

The app owner never touches these. SecOps configures via deployment pipeline or K8s ConfigMap.

### 7.3 Promotion Path: RASP Detection → WAF Block

```
Day 1: RASP detects RASP-SQLI from IP 203.0.113.42
    │   (detect only -- request completes normally)
    │
Day 1: Cribl → Jira ticket created
    │
Day 1-2: SecOps investigates
    │   Confirms: automated SQL injection scanner
    │
Day 2: SecOps adds WAF rule:
    │   Block requests matching UNION SELECT from untrusted IPs
    │   Block IP 203.0.113.42 at NGFW
    │
Day 3+: WAF blocks future attacks (app never involved)
    │     RASP still detects (defense in depth -- WAF bypass detection)
```

---

## 8. Admin UI Additions

### 8.1 Activity Logs Tab Enhancement

Existing Activity Logs tab gets a new event type filter value:

| Existing Type Filters | New Addition |
|----------------------|-------------|
| IN (inbound requests) | **SECURITY** (RASP events) |
| OUT (outbound calls) | |

### 8.2 SECURITY Event Display in Activity Logs

When filtering by type=SECURITY, the event table shows:

| Column | Content |
|--------|---------|
| Time | Event timestamp |
| Type Badge | `SEC` (red background) |
| RASP ID | `RASP-SQLI`, `RASP-XSS`, etc. |
| Severity | Color-coded: CRITICAL (red), HIGH (orange), MEDIUM (yellow), LOW (blue) |
| Category | "SQL Injection Probing", etc. |
| Path | Request path |
| IP | Source IP |
| User | Email if authenticated, "anon" if not |
| Detail | Pattern description |

### 8.3 Stats Card Addition

Add to existing stats cards row:

```
[Buffer Usage: 45%] [Requests: 12,847] [Outbound: 3,421] [Security Events: 23 ⚠️]
```

Security Events card: shows count of SECURITY events in buffer. Orange if >0, red if any CRITICAL.

### 8.4 No New Admin Pages

RASP does NOT get its own admin page. Events surface through the existing Activity Logs infrastructure. Rationale: business users should not be managing security -- they see the same logs page, just with a new type filter.

---

## 9. Build Standards & Verification

### 9.1 New Build Standards Checks

| Check ID | Tier | Severity | Description |
|----------|------|----------|-------------|
| **RP01** | 1, 5 | FIX | **RASP middleware registered** -- RaspMiddleware is added to FastAPI app middleware stack in main.py |
| **RP02** | 1, 5 | FIX | **RASP patterns file exists** -- `rasp_patterns.py` contains REQUEST_PATTERNS, RESPONSE_PATTERNS, and AI_PATTERNS |
| **RP03** | 1, 5 | FIX | **RASP behavioral tracker exists** -- `rasp_behavioral.py` with sliding window thresholds for credential stuffing, fuzzing, privilege probing |
| **RP04** | 1, 5 | FIX | **LogService.log_security() exists** -- SECURITY event type supported in LogStore |
| **RP05** | 1, 5 | FIX | **RASP environment variables** -- RASP_ENABLED, RASP_EXCLUDE_PATTERNS, RASP_SEVERITY_THRESHOLD in .env.example and docker-compose.yml |
| **RP06** | 1, 5 | FIX | **RASP events in Activity Logs UI** -- SECURITY type filter exists in Activity Logs dropdown; SEC badge renders for security events |
| **RP07** | 1, 5 | BLOCK | **RASP never blocks requests** -- Grep rasp.py for any `raise HTTPException`, `return Response(status_code=4`, or `return Response(status_code=5`. Any match is a violation -- RASP must be detect-only |
| **RP08** | AI | FIX | **AI RASP patterns included** -- AI_PATTERNS list contains RASP-PINJ, RASP-JAIL, RASP-TOOL, RASP-AIOUT, RASP-TOKEN categories |

### 9.2 Build-Verify Tests

| Test | Phase | Validation |
|------|-------|-----------|
| **RASP middleware registered** | Part A (static) | Grep main.py for `RaspMiddleware` |
| **RASP detect-only enforcement** | Part A (static) | Grep rasp.py and rasp_service.py for HTTPException/error returns (must find none) |
| **RASP pattern coverage** | Part A (static) | Verify REQUEST_PATTERNS covers: SQLI, XSS, TRAV, CMDI, SSRF, XXE |
| **RASP event emission** | Part B (live) | Send request with `' OR 1=1--` in query param; verify SECURITY event in /api/admin/logs/events |
| **RASP does not block** | Part B (live) | Send request with SQL injection pattern; verify response is normal (not 403/400) |
| **RASP behavioral tracking** | Part B (live) | Send 25 rapid requests returning 400; verify RASP-FUZZ event appears |
| **Activity Logs UI** | Part B (live) | Verify SECURITY type filter option exists in Activity Logs |

---

## 10. Performance Impact Analysis

### 10.1 Latency Impact

| Component | Operation | Latency | When |
|-----------|-----------|---------|------|
| Request pattern matching | 10-15 regex matches against path + query | **<1ms** | Every request |
| Request body inspection | Regex against POST body (AI endpoints only) | **<2ms** | AI endpoint requests only |
| Response body inspection | Regex against JSON body (<512KB) | **<1ms** | JSON responses only |
| Behavioral tracking | Hash lookup + counter increment | **<0.1ms** | Every request |
| Event emission | LogStore.add() (in-memory append) | **<0.1ms** | Only when finding detected |
| Cribl forwarding | Async HTTP POST (non-blocking) | **0ms on request path** | Background task |
| **Total overhead (normal request)** | | **<2ms** | |
| **Total overhead (AI request)** | | **<3ms** | AI requests already take 1-30s |

### 10.2 Memory Impact

| Component | Memory Usage | Notes |
|-----------|-------------|-------|
| Compiled regex patterns | ~50KB | Fixed at startup; ~40 patterns |
| Behavioral tracker windows | ~1KB per tracked IP/user | Cleaned every 10 min; ~100 active IPs = 100KB |
| SECURITY events in LogStore | Shared with existing buffer | Uses same LOG_BUFFER_SIZE; priority eviction keeps SECURITY events |
| **Total additional memory** | **<1MB typical** | Negligible alongside app memory |

### 10.3 Impact on Application Behavior

| Concern | Answer |
|---------|--------|
| Can RASP cause a request to fail? | **No.** RASP runs in try/except. If RASP itself errors, the exception is swallowed and logged. Request proceeds normally. |
| Can RASP slow down the app? | **Negligibly.** <2ms per request. AI endpoints add <3ms against 1-30s baseline. Not human-perceptible. |
| Can RASP fill the log buffer? | **Managed.** Priority eviction: IN events evicted first, SECURITY events last. Under sustained attack, normal request logs may be evicted, but security events are preserved. |
| Can RASP cause memory issues? | **No.** Behavioral tracker cleans up every 10 min. Compiled patterns are fixed-size. Events use existing LogStore buffer. |
| Can RASP break during Docker build? | **No.** RASP is pure Python with no external dependencies. Regex patterns compiled at import time. |
| What if Cribl is down? | **Nothing breaks.** Cribl forwarding is async with fire-and-forget. Events still logged to in-memory LogStore. Cribl reconnects automatically. |

---

## 11. What This Is NOT

| This Is | This Is NOT |
|---------|-------------|
| Lightweight pattern matching in middleware | A commercial RASP agent (Contrast, Sqreen, Datadog ASM) |
| Detect and alert | Block and prevent |
| ~40 regex patterns covering common attacks | A comprehensive signature database (10,000+ signatures) |
| In-memory behavioral tracking | A machine learning anomaly detection engine |
| Event forwarding to Cribl/SIEM | A standalone security dashboard or SOC tool |
| An early warning system for SecOps | A replacement for WAF, NGFW, or pen testing |
| Scaffold code maintained by /make-it | Agent software maintained by a vendor |

**For organizations wanting commercial-grade RASP:**

Deploy Contrast Security, Datadog ASM, or Dynatrace Application Security at the infrastructure layer. These provide:
- Full signature databases (10,000+ patterns)
- Machine learning anomaly detection
- Automatic virtual patching
- Runtime code flow analysis
- Production-grade dashboards

The scaffold-embedded RASP and commercial RASP can coexist -- scaffold RASP provides application-context-aware detection (it knows about RBAC roles, AI pipelines, domain entities), while commercial RASP provides depth and breadth of signature coverage.

---

## Appendix: Detection Patterns

### Pattern Maintenance

Patterns are maintained in `rasp_patterns.py` within the scaffold. When the scaffold is updated:
- New patterns are added for emerging attack vectors
- False-positive-prone patterns are refined
- /resume-it detects pattern file updates and applies them during catch-up scan

### MITRE ATT&CK Mapping

| RASP ID | MITRE Technique | Tactic |
|---------|----------------|--------|
| RASP-SQLI | T1190 Exploit Public-Facing Application | Initial Access |
| RASP-XSS | T1189 Drive-by Compromise | Initial Access |
| RASP-TRAV | T1083 File and Directory Discovery | Discovery |
| RASP-CMDI | T1059 Command and Scripting Interpreter | Execution |
| RASP-SSRF | T1090 Proxy / T1552 Unsecured Credentials | Defense Evasion / Credential Access |
| RASP-XXE | T1190 Exploit Public-Facing Application | Initial Access |
| RASP-PINJ | T1059.007 JavaScript | Execution |
| RASP-JAIL | T1059.007 JavaScript | Execution |
| RASP-CSTUFF | T1110 Brute Force | Credential Access |
| RASP-SCRAPE | T1530 Data from Cloud Storage Object | Collection |
| RASP-FUZZ | T1595 Active Scanning | Reconnaissance |
| RASP-PRIV | T1068 Exploitation for Privilege Escalation | Privilege Escalation |
| RASP-PII | T1567 Exfiltration Over Web Service | Exfiltration |
| RASP-SECRET | T1552 Unsecured Credentials | Credential Access |
| RASP-ERRINFO | T1082 System Information Discovery | Discovery |

### Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| RASP_ENABLED | true | Enable/disable RASP middleware |
| RASP_EXCLUDE_PATTERNS | (empty) | Comma-separated list of pattern exclusions (format: RASP_ID:pattern_name) |
| RASP_SEVERITY_THRESHOLD | LOW | Minimum severity to emit (LOW, MEDIUM, HIGH, CRITICAL) |
| RASP_BEHAVIORAL_ENABLED | true | Enable/disable cross-request behavioral detection |
| RASP_RESPONSE_INSPECTION | true | Enable/disable response body inspection |
| RASP_MAX_BODY_INSPECT | 524288 | Max response body size to inspect (bytes) |

---

*This RASP design is scaffold-embedded and ships with every /make-it application. Pattern updates flow through scaffold updates. Tuning and alert response is SecOps responsibility via Cribl → SIEM → Jira. The business user never knows it exists.*
