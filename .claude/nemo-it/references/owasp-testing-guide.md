# OWASP Testing Guide v4 -- Automated Test Strategy Reference

## Purpose

This document maps all 11 OWASP Testing Guide v4 categories to specific automated test strategies for the `/nemo-it` skill. Every test listed here is designed to be non-destructive. Tests that could cause application breakage, buffer overflow, or denial of service are marked **DETECT-ONLY** and include passive detection methods that report susceptibility without exploitation.

## Global Safety Constraints

The following constraints apply to ALL test categories:

- **No Denial of Service**: No flood testing, resource exhaustion, or high-concurrency abuse.
- **No Buffer Overflow**: No oversized payload injection intended to crash processes.
- **No Destructive Tests**: No data deletion, corruption, or state mutation in production environments.
- **No Credential Brute Forcing**: Brute force susceptibility is detected by analyzing lockout behavior and response patterns, never by executing large-scale attempts.
- **Rate Limiting**: All automated scans must respect application rate limits. OWASP ZAP scans use the "Safe" scan policy.
- **Scope Isolation**: Tests target only explicitly authorized domains and endpoints.

## Tool Abbreviations

| Abbreviation | Tool |
|---|---|
| ZAP | OWASP ZAP (passive + active safe scan policies) |
| pytest | Python pytest with requests/httpx |
| Playwright | Playwright browser automation |
| semgrep | Semgrep static analysis |
| Bandit | Bandit Python static analysis |
| ESLint-sec | ESLint with eslint-plugin-security |
| SQLMap-passive | SQLMap in detection-only mode (--risk=1 --level=1 --batch --technique=B --stop) |
| Trivy | Trivy container/dependency scanner |
| npm-audit | npm audit |
| pip-audit | pip-audit |
| custom | Custom script (Bash/Python) |

---

## 1. OTG-INFO: Information Gathering

### What It Tests

Determines what information the application inadvertently discloses to unauthenticated users. This includes server technology, software versions, internal paths, backup files, development artifacts, and metadata that an attacker could use for reconnaissance.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| INFO-01 | Server banner disclosure | pytest | Send HEAD/GET to root and inspect `Server`, `X-Powered-By`, `X-AspNet-Version` response headers. | YES | Read-only HTTP request. |
| INFO-02 | Technology fingerprinting | ZAP | Run ZAP passive scan; review Technology tab for detected frameworks, languages, and server software. | YES | Passive analysis of normal responses. |
| INFO-03 | robots.txt enumeration | pytest | GET `/robots.txt`, parse Disallow entries, catalog hidden paths. | YES | Standard HTTP request to a public file. |
| INFO-04 | Sitemap.xml analysis | pytest | GET `/sitemap.xml` and `/sitemap_index.xml`, extract all listed URLs, flag internal/admin paths. | YES | Public file retrieval. |
| INFO-05 | Error page information leakage | pytest | Request deliberately non-existent paths (e.g., `/nonexistent-abc123`) and analyze response body for stack traces, framework names, internal IPs. | YES | Only triggers 404 handler, non-destructive. |
| INFO-06 | Directory enumeration (common paths) | ZAP | Use ZAP forced-browse with a small, curated wordlist (top 100 common dirs). Rate-limited to 2 req/sec. | YES | Low-volume, curated list only. Do NOT use large wordlists that could cause load. |
| INFO-07 | HTTP method enumeration | pytest | Send OPTIONS request to key endpoints; log allowed methods. | YES | Single request per endpoint. |
| INFO-08 | Meta tag and HTML comment analysis | Playwright | Load key pages in headless browser, extract `<meta>` tags and HTML comments for version info, TODO notes, internal references. | YES | Normal page load. |

### Safe Testing Constraints

- Do NOT perform aggressive directory brute-forcing with large wordlists (10,000+ entries).
- Do NOT spider the entire application recursively without depth limits; cap at depth 3.
- Do NOT attempt to access backup files by appending extensions (.bak, .old) at scale; limit to a curated list of 20 common patterns.

---

## 2. OTG-CONFIG: Configuration and Deployment Management

### What It Tests

Identifies insecure server and application configuration: missing security headers, weak TLS settings, exposed administrative interfaces, CORS misconfigurations, and unnecessary HTTP methods enabled.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| CONFIG-01 | Security headers audit | pytest | Check responses for HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy headers. | YES | Read-only header inspection. |
| CONFIG-02 | CORS misconfiguration | pytest | Send requests with `Origin: https://evil.example.com` and check if `Access-Control-Allow-Origin` reflects it or uses wildcard `*`. | YES | Single crafted request per endpoint. |
| CONFIG-03 | TLS configuration analysis | custom | Use `testssl.sh` or `sslyze` to evaluate TLS versions, cipher suites, certificate chain, HSTS preload status. | YES | Outbound TLS handshake analysis only. |
| CONFIG-04 | Default credentials detection | pytest | Check for known default login pages (`/admin`, `/login`, `/wp-admin`, `/console`) and attempt ONE login with the most common default credential pair per platform. | YES | Single attempt per interface; no brute force. |
| CONFIG-05 | Unnecessary HTTP methods | pytest | Send TRACE, PUT, DELETE, PATCH to key endpoints and check if they return success or method-not-allowed. | YES | Individual requests; non-destructive verbs tested against safe paths. |
| CONFIG-06 | Admin interface exposure | pytest | Probe for common admin paths (`/admin`, `/administrator`, `/manage`, `/console`, `/dashboard`) and check HTTP status codes. | YES | Standard GET requests. |
| CONFIG-07 | Cookie security attributes | pytest | Authenticate (if credentials provided) and inspect Set-Cookie headers for Secure, HttpOnly, SameSite, Path, Domain attributes. | YES | Header inspection only. |
| CONFIG-08 | Content-Security-Policy analysis | custom | Parse CSP header, flag `unsafe-inline`, `unsafe-eval`, wildcard sources, missing directives. Report a risk score. | YES | Static analysis of header value. |

### Safe Testing Constraints

- Do NOT attempt more than one default credential pair per discovered login interface.
- Do NOT send PUT or DELETE with actual payloads; use empty bodies against non-critical paths.
- Do NOT modify any server configuration.

---

## 3. OTG-IDENT: Identity Management

### What It Tests

Evaluates whether the application leaks information about valid user accounts, has weak account provisioning processes, or allows user registration abuse.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| IDENT-01 | Username enumeration via login | pytest | Submit login with a known-invalid username and a known-valid username (if available); compare response text, status code, timing, and headers for differences. | YES | Two requests total; no brute force. |
| IDENT-02 | Username enumeration via registration | pytest | Attempt to register with a likely-existing username; check if error message reveals existence. | YES | Single registration attempt; do not complete. |
| IDENT-03 | Username enumeration via password reset | pytest | Submit password reset for known-valid and known-invalid emails; compare responses for differential behavior. | YES | Two requests total. |
| IDENT-04 | Account provisioning review | semgrep | Scan source code for user creation flows lacking email verification, approval workflows, or role assignment validation. | YES | Static analysis. |
| IDENT-05 | User role definition analysis | semgrep | Search codebase for hardcoded role names, role assignment logic, and missing role validation on creation endpoints. | YES | Static analysis. |
| IDENT-06 | Account enumeration via API | pytest | Query user-related API endpoints (e.g., `/api/users/{id}`) with sequential IDs (1-10) and check for information disclosure. | YES | Small, bounded request set. |
| IDENT-07 | Registration rate limiting | pytest | Submit 5 registration requests in quick succession and check if rate limiting engages. | DETECT-ONLY | Stops at 5 requests. If no rate limiting detected, report susceptibility. Do NOT send more. |
| IDENT-08 | Predictable user ID detection | pytest | Create or observe 2-3 user IDs and check for sequential or predictable patterns. | YES | Observational only. |

### Safe Testing Constraints

- Do NOT enumerate large lists of usernames or email addresses.
- Do NOT complete account registrations unless using designated test accounts.
- Limit all enumeration probes to fewer than 10 requests per vector.

---

## 4. OTG-AUTHN: Authentication

### What It Tests

Assesses the strength of authentication mechanisms including password policies, brute force protections, session fixation vulnerabilities, multi-factor authentication implementation, and authentication bypass possibilities.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| AUTHN-01 | Brute force protection detection | pytest | Submit 5 failed login attempts for a test account; check if account lockout, CAPTCHA, or progressive delay engages. | DETECT-ONLY | Stops at 5 attempts. Reports whether protection exists. Do NOT execute actual brute force. |
| AUTHN-02 | Password policy validation | pytest | Attempt registration/password-change with weak passwords (e.g., "123456", "password", "a") and verify rejection. | YES | Tests policy enforcement, not exploitation. |
| AUTHN-03 | Credential transport over TLS | pytest | Inspect login form action URL and verify it uses HTTPS; check for mixed content on login pages. | YES | Observational. |
| AUTHN-04 | Default credentials check | pytest | Attempt login with one default credential pair per known platform (admin/admin, admin/password). | YES | Single attempt per platform; non-brute-force. |
| AUTHN-05 | Session fixation detection | pytest | Obtain session token before login, authenticate, check if token changes post-authentication. | YES | Normal login flow with token comparison. |
| AUTHN-06 | Authentication bypass via direct request | pytest | Access authenticated-only endpoints without a session token; verify 401/403 response. | YES | Standard unauthorized request. |
| AUTHN-07 | MFA implementation review | Playwright | Walk through MFA enrollment flow (if test account available); verify MFA cannot be skipped by directly requesting post-MFA URLs. | YES | Normal navigation flow. |
| AUTHN-08 | Password stored in source/config | semgrep, Bandit | Scan codebase for hardcoded passwords, API keys, and credential strings. | YES | Static analysis only. |

### Safe Testing Constraints

- Do NOT execute brute force attacks. Limit failed login attempts to 5 per account.
- Do NOT lock out real user accounts. Use only designated test accounts.
- Do NOT attempt credential stuffing with leaked password databases.

### Passive Detection for Brute Force Susceptibility

To detect brute force susceptibility without exploiting it:
1. Send 3 failed login attempts and measure response times. If times are constant (no progressive delay), flag as susceptible.
2. Check login page source for CAPTCHA elements. Absence indicates susceptibility.
3. Check response headers for rate-limiting indicators (`X-RateLimit-*`, `Retry-After`). Absence indicates susceptibility.
4. After 3 failed attempts, check if account is still accessible. If no lockout, flag as susceptible.

---

## 5. OTG-AUTHZ: Authorization

### What It Tests

Verifies that access controls are properly enforced: users cannot access resources belonging to other users (horizontal privilege escalation), regular users cannot access admin functions (vertical privilege escalation), and direct object references are properly validated.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| AUTHZ-01 | Horizontal privilege escalation (IDOR) | pytest | Authenticate as User A, request resources belonging to User B by manipulating resource IDs. Verify 403 response. | YES | Read-only access attempt; no modification. |
| AUTHZ-02 | Vertical privilege escalation | pytest | Authenticate as low-privilege user, request admin-only endpoints. Verify 403 response. | YES | Read-only access attempt. |
| AUTHZ-03 | Path traversal detection | pytest | Send requests with `../` sequences in path parameters (e.g., `../../etc/passwd`). Check if response contains file contents. | YES | Payload is in URL path; read-only. |
| AUTHZ-04 | Forced browsing to admin pages | pytest | Request known admin URLs (`/admin/users`, `/admin/config`, `/api/admin/*`) without admin session. Verify denial. | YES | Standard GET requests. |
| AUTHZ-05 | Missing function-level access control | pytest | Identify API endpoints from JavaScript/source, call each with low-privilege and no-auth tokens, compare responses. | YES | Read-only API calls. |
| AUTHZ-06 | IDOR in API parameters | pytest | Modify numeric/UUID IDs in API calls (e.g., change `user_id=1` to `user_id=2`) while authenticated as user 1. | YES | GET requests only; no data modification. |
| AUTHZ-07 | Path traversal in file operations | semgrep | Scan source for file read/write operations using user-supplied input without path sanitization. | YES | Static analysis. |
| AUTHZ-08 | Role-based access control consistency | pytest | Map all endpoints, test each with every available role (admin, user, guest). Produce an access matrix. | YES | Read-only requests across role set. |

### Safe Testing Constraints

- Do NOT modify or delete any resources during authorization testing.
- Use only GET requests for IDOR and privilege escalation tests unless explicitly authorized for write testing.
- Do NOT traverse beyond well-known safe test strings; never attempt to read actual system files in production.

---

## 6. OTG-SESS: Session Management

### What It Tests

Evaluates how the application creates, maintains, and destroys user sessions. Tests cover session token randomness, cookie security attributes, timeout enforcement, fixation vulnerabilities, and cross-site request forgery protections.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| SESS-01 | Session token entropy analysis | custom | Collect 10 session tokens, analyze with `ent` or custom entropy calculator. Flag tokens with less than 64 bits of entropy. | YES | Normal login flow repeated. |
| SESS-02 | Cookie Secure attribute | pytest | Inspect Set-Cookie headers for `Secure` flag on all session-related cookies. | YES | Header inspection. |
| SESS-03 | Cookie HttpOnly attribute | pytest | Inspect Set-Cookie headers for `HttpOnly` flag. Verify via Playwright that `document.cookie` does not expose session tokens. | YES | Read-only inspection. |
| SESS-04 | Cookie SameSite attribute | pytest | Inspect Set-Cookie headers for `SameSite=Strict` or `SameSite=Lax`. | YES | Header inspection. |
| SESS-05 | Session timeout enforcement | pytest | Authenticate, wait for configured timeout period (or simulate with server-side check), then attempt to use the session. | YES | Normal session lifecycle. |
| SESS-06 | Session fixation | pytest | Set a known session token via cookie before authentication, authenticate, verify the token is regenerated. | YES | Standard login flow with token tracking. |
| SESS-07 | CSRF token presence | Playwright | Load forms that perform state-changing operations; verify CSRF tokens exist in hidden fields or headers. | YES | Page inspection only. |
| SESS-08 | Session invalidation on logout | pytest | Authenticate, capture session token, logout, attempt to reuse the token. Verify 401 response. | YES | Normal logout flow. |

### Safe Testing Constraints

- Do NOT attempt to hijack real user sessions.
- Do NOT inject session tokens into other users' browsers.
- Token collection for entropy analysis must use only the test account's own sessions.

---

## 7. OTG-INPVAL: Input Validation

### What It Tests

Identifies injection vulnerabilities including cross-site scripting (XSS), SQL injection, command injection, header injection, and file upload validation weaknesses. Tests use safe payloads that detect vulnerability without causing harm.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| INPVAL-01 | Reflected XSS detection | ZAP | ZAP active scan with XSS payloads using safe scan policy. Payloads use `alert(1)` style probes, not destructive scripts. | YES | Standard ZAP XSS detection; non-destructive payloads. |
| INPVAL-02 | Stored XSS detection | Playwright | Submit benign XSS probe strings (`<script>alert('xss-test-nemo')</script>`) into input fields, then check if they render unescaped on output pages. | DETECT-ONLY | Uses identifiable marker string. If stored and rendered, report susceptibility. Clean up test data if possible. |
| INPVAL-03 | DOM-based XSS detection | semgrep, ESLint-sec | Scan JavaScript source for `innerHTML`, `document.write`, `eval()`, `setTimeout(string)`, and other dangerous sinks receiving user-controlled sources. | YES | Static analysis. |
| INPVAL-04 | SQL injection (passive) | SQLMap-passive | Run SQLMap with `--risk=1 --level=1 --batch --technique=B --tamper=space2comment` in detection-only mode. Do NOT use `--os-shell` or `--dump`. | DETECT-ONLY | Detection only. Reports injectable parameters without extracting data. |
| INPVAL-05 | Command injection detection | semgrep, Bandit | Scan source for `os.system()`, `subprocess` with shell=True, `exec()`, backtick execution, and similar patterns with user input. | YES | Static analysis. |
| INPVAL-06 | HTTP header injection | pytest | Send requests with CRLF sequences (`%0d%0a`) in header values and parameters. Check if injected headers appear in response. | YES | Single crafted request per endpoint. |
| INPVAL-07 | HTTP parameter pollution | pytest | Send duplicate parameters (e.g., `?id=1&id=2`) and analyze how the application handles them. | YES | Normal HTTP requests with duplicate params. |
| INPVAL-08 | File upload validation | pytest | Upload files with manipulated extensions (e.g., `test.php.jpg`), manipulated MIME types, and oversized files (just above limit). Verify rejection. | YES | Tests validation logic; uploaded files are benign. |

### Safe Testing Constraints

- Do NOT use SQLMap with `--os-shell`, `--os-cmd`, `--dump`, `--dump-all`, or `--risk=3`.
- Do NOT submit XSS payloads that exfiltrate data or modify application state (no `fetch()` to external domains).
- Do NOT upload actual malware or exploit files.
- Do NOT send payloads larger than 10KB to avoid triggering WAF blocks or causing load.

### Passive SQL Injection Detection

To detect SQL injection susceptibility without exploiting:
1. Submit a single quote (`'`) in parameters and look for SQL error messages in responses.
2. Submit `1 AND 1=1` vs `1 AND 1=2` and compare response lengths for boolean-based detection.
3. Use SQLMap `--batch --technique=B --stop` to identify injectable params and immediately stop.
4. Check source code with semgrep for string concatenation in SQL queries.

---

## 8. OTG-ERR: Error Handling

### What It Tests

Determines whether the application exposes sensitive information through error messages, stack traces, debug output, or inconsistent error handling that could aid an attacker in understanding internal architecture.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| ERR-01 | Stack trace disclosure | pytest | Send malformed requests (invalid JSON, wrong content type, oversized headers) and check responses for stack traces, file paths, line numbers. | YES | Malformed but small requests; triggers error handling. |
| ERR-02 | Verbose error messages | pytest | Trigger various HTTP errors (400, 401, 403, 404, 405, 500) and inspect response bodies for internal details. | YES | Standard error-triggering requests. |
| ERR-03 | Database error disclosure | pytest | Submit invalid data types to parameters expecting numbers/dates and check for SQL or ORM error messages. | YES | Single malformed request per parameter. |
| ERR-04 | Debug mode detection | pytest | Check for debug indicators: Django debug page, Express stack traces, Spring Boot actuator, PHP `display_errors`. | YES | Standard GET requests to known debug paths. |
| ERR-05 | Error code consistency | pytest | Map all error scenarios and verify consistent error response format (no mix of HTML errors and JSON errors on API endpoints). | YES | Observational analysis. |
| ERR-06 | Exception handling in source | semgrep, Bandit | Scan for empty catch blocks, overly broad exception handling, and error messages that include variable contents. | YES | Static analysis. |
| ERR-07 | Custom error page verification | Playwright | Request non-existent URLs and verify custom error pages are returned (not framework defaults). | YES | Standard 404 request. |
| ERR-08 | Information leakage in HTTP 500 | pytest | Send edge-case inputs (empty body to POST endpoints, null bytes, extremely long parameter names) and inspect 500 responses. | YES | Small, targeted requests. Do NOT send oversized bodies. |

### Safe Testing Constraints

- Do NOT send requests designed to crash the application (no buffer overflow payloads, no billion-laughs XML).
- Keep malformed payloads small (under 1KB).
- Do NOT repeatedly trigger 500 errors in rapid succession (max 5 per endpoint).

---

## 9. OTG-CRYPST: Cryptography

### What It Tests

Evaluates the strength of cryptographic implementations including TLS configuration, cipher suite selection, certificate validity, token randomness, JWT security, and proper use of cryptographic algorithms.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| CRYPST-01 | TLS version support | custom | Use `sslyze` or `testssl.sh` to enumerate supported TLS versions. Flag SSLv3, TLS 1.0, TLS 1.1. | YES | TLS handshake probes only. |
| CRYPST-02 | Cipher suite strength | custom | Enumerate accepted cipher suites. Flag NULL, EXPORT, RC4, DES, 3DES, and suites without forward secrecy. | YES | TLS handshake analysis. |
| CRYPST-03 | Certificate validation | custom | Check certificate chain completeness, expiration dates, key size (min 2048-bit RSA or 256-bit ECC), and CA trust. | YES | Certificate inspection. |
| CRYPST-04 | Weak algorithm detection in source | semgrep, Bandit | Scan source for use of MD5, SHA1 (for security purposes), DES, RC4, ECB mode, and hardcoded IVs/keys. | YES | Static analysis. |
| CRYPST-05 | JWT validation weaknesses | pytest | Send JWTs with `alg: none`, `alg: HS256` (when RS256 expected), and expired tokens. Check if accepted. | YES | Single crafted request per test case. |
| CRYPST-06 | Token entropy analysis | custom | Collect 20 tokens (session, CSRF, reset) and measure Shannon entropy. Flag if below 3.5 bits/char. | YES | Token collection via normal flows. |
| CRYPST-07 | Key management in source | semgrep, Bandit | Scan for hardcoded cryptographic keys, private keys in repositories, and insecure key derivation functions. | YES | Static analysis. |
| CRYPST-08 | HSTS and certificate pinning | pytest | Check for `Strict-Transport-Security` header with adequate `max-age` (min 31536000). Check for `Public-Key-Pins` or `Expect-CT`. | YES | Header inspection. |

### Safe Testing Constraints

- Do NOT attempt to downgrade active user TLS connections.
- Do NOT perform padding oracle attacks (these can cause service disruption).
- TLS testing tools must connect to the target only; do NOT MITM proxy other users' traffic.

---

## 10. OTG-BUSLOGIC: Business Logic

### What It Tests

Identifies flaws in application business logic that could allow workflow bypass, data validation circumvention, feature misuse, or race conditions. These are application-specific vulnerabilities that automated scanners often miss.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| BUSLOGIC-01 | Workflow step bypass | Playwright | Attempt to skip steps in multi-step processes (e.g., jump from step 1 to step 3 directly via URL manipulation). | YES | Normal navigation; no data modification. |
| BUSLOGIC-02 | Data validation bypass | pytest | Submit data that passes client-side validation but violates server-side rules (e.g., negative quantities, future dates, special characters in numeric fields). | YES | Tests server-side validation; uses non-destructive test data. |
| BUSLOGIC-03 | Rate limiting verification | pytest | Send 10 rapid requests to sensitive endpoints (password reset, login, API) and check for rate limiting response (429). | DETECT-ONLY | Stops at 10 requests. If no rate limiting detected, reports susceptibility without continuing. |
| BUSLOGIC-04 | Feature misuse detection | pytest | Test for unintended feature use: self-referral, duplicate submissions, coupon reuse. Use test accounts only. | YES | Controlled test with designated test data. |
| BUSLOGIC-05 | Race condition susceptibility | custom | Analyze source code for time-of-check-to-time-of-use (TOCTOU) patterns, non-atomic operations on shared resources, and missing database transaction isolation. | DETECT-ONLY | Static analysis and code review only. Do NOT execute concurrent requests to trigger race conditions. |
| BUSLOGIC-06 | Numeric limit bypass | pytest | Submit boundary values (0, -1, MAX_INT, 0.001) to numeric fields and check for improper handling. | YES | Single request per boundary value. |
| BUSLOGIC-07 | File size/type limit bypass | pytest | Upload files at exactly the size limit, slightly over, and with mismatched MIME types. Check enforcement. | YES | Benign test files only. |
| BUSLOGIC-08 | Process timing analysis | pytest | Measure response times for valid vs. invalid inputs to detect timing side channels in authentication or authorization decisions. | YES | Normal requests with timing measurement. |

### Safe Testing Constraints

- Do NOT send high-concurrency requests to trigger race conditions in production.
- Do NOT submit financial transactions or orders, even with test data, unless in a confirmed sandbox.
- Do NOT exploit discovered logic flaws; report them.

### Passive Race Condition Detection

To detect race condition susceptibility without exploiting:
1. **Source code analysis**: Search for non-atomic read-modify-write patterns, especially on balances, counters, and inventory.
2. **Database analysis**: Check for missing `SELECT ... FOR UPDATE`, missing transaction isolation levels, and optimistic locking without retry logic.
3. **Architecture review**: Identify stateful operations without mutex/locking mechanisms.
4. Report findings with reproduction steps but do NOT execute concurrent exploitation.

---

## 11. OTG-CLIENT: Client-Side

### What It Tests

Evaluates client-side security including DOM-based XSS, JavaScript injection vectors, HTML/CSS injection, open redirects, client-side resource manipulation, CORS misuse, and WebSocket security.

### Test Cases

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| CLIENT-01 | DOM-based XSS via source analysis | semgrep, ESLint-sec | Identify JavaScript sinks (`innerHTML`, `outerHTML`, `document.write`, `eval`, `Function()`, `setTimeout/setInterval` with strings) that receive data from sources (`location.hash`, `location.search`, `document.referrer`, `postMessage`). | YES | Static analysis. |
| CLIENT-02 | DOM-based XSS via dynamic testing | Playwright | Navigate to pages with URL fragment/query payloads (e.g., `#<img src=x onerror=alert(1)>`) and check if DOM is modified unsafely. | YES | Headless browser; payload does not persist. |
| CLIENT-03 | JavaScript injection via postMessage | Playwright | Inspect `window.addEventListener('message', ...)` handlers for missing origin validation. Send test postMessage from same page context. | YES | In-browser analysis; no cross-origin abuse. |
| CLIENT-04 | HTML injection detection | pytest | Submit HTML tags (`<h1>test</h1>`, `<img src=x>`) in input fields and check if they render in response without encoding. | YES | Benign HTML tags only. |
| CLIENT-05 | CSS injection detection | pytest | Submit CSS payloads (`color:red}*{background:url(//test)`) in input fields and check for injection in style contexts. | YES | Non-exfiltrating CSS only. |
| CLIENT-06 | Client-side URL redirect (open redirect) | pytest | Submit redirect parameters with external URLs (`?redirect=https://evil.example.com`) and check if application redirects without validation. | YES | Checks redirect behavior via response headers (301/302 Location); does not follow redirect. |
| CLIENT-07 | Client-side resource manipulation | Playwright | Analyze JavaScript for dynamic resource loading based on user-controlled input (`src`, `href`, `action` attributes set from URL params). | YES | Static analysis of page JavaScript. |
| CLIENT-08 | CORS client-side analysis | Playwright | Check JavaScript for `XMLHttpRequest` or `fetch` calls to third-party origins, and whether responses are validated. | YES | Source code inspection in browser. |
| CLIENT-09 | WebSocket security | Playwright | Connect to WebSocket endpoints (if present), verify `wss://` usage, check for authentication on WS handshake, inspect for origin validation. | YES | Single connection with observation. |
| CLIENT-10 | Third-party script inventory | Playwright | Catalog all externally loaded scripts, check for Subresource Integrity (SRI) attributes, and flag scripts loaded over HTTP. | YES | Page load analysis. |

### Safe Testing Constraints

- Do NOT inject scripts that exfiltrate data to external domains.
- Do NOT modify other users' DOM or session state.
- Do NOT follow open redirects to actual malicious domains; only verify the redirect response header.
- WebSocket testing must use only the test account's session.

---

## Dependency Scanning (Cross-Category)

In addition to the 11 OWASP categories, the following dependency scans support multiple categories:

| Test ID | Test Name | Tool | Method | Safe? | Notes |
|---|---|---|---|---|---|
| DEP-01 | Node.js dependency vulnerabilities | npm-audit | Run `npm audit` and report HIGH/CRITICAL findings. | YES | Read-only analysis of package-lock.json. |
| DEP-02 | Python dependency vulnerabilities | pip-audit | Run `pip-audit` against requirements.txt or virtual environment. | YES | Read-only analysis. |
| DEP-03 | Container image vulnerabilities | Trivy | Run `trivy image` against application container images. | YES | Read-only image scan. |
| DEP-04 | License compliance | Trivy | Run `trivy fs --security-checks license` to identify problematic licenses. | YES | Filesystem analysis. |
| DEP-05 | Outdated dependency detection | npm-audit, pip-audit | List dependencies with known EOL or significantly outdated versions. | YES | Version comparison only. |

---

## Execution Order

Recommended execution sequence to maximize safety and efficiency:

1. **Static Analysis First**: semgrep, Bandit, ESLint-sec (zero risk, no network traffic)
2. **Dependency Scanning**: npm-audit, pip-audit, Trivy (zero risk to application)
3. **Passive Network Tests**: TLS analysis, header inspection, cookie analysis
4. **Active Safe Tests**: ZAP passive scan, authenticated endpoint testing
5. **DETECT-ONLY Tests**: Brute force detection, rate limit detection, race condition analysis
6. **Input Validation Tests**: XSS probes, SQL injection detection (lowest risk payloads)

---

## Reporting

Each test produces a finding with:

- **Test ID**: From the tables above
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Status**: PASS / FAIL / DETECT-ONLY (susceptibility found)
- **Evidence**: Response snippets, headers, or source code references
- **Remediation**: Specific fix recommendation
- **OWASP Reference**: Link to the relevant OWASP Testing Guide section

---

## References

- OWASP Testing Guide v4: https://owasp.org/www-project-web-security-testing-guide/v42/
- OWASP Testing Checklist: https://owasp.org/www-project-web-security-testing-guide/v42/6-Appendix/
- ZAP Scan Policies: https://www.zaproxy.org/docs/desktop/ui/dialogs/scanpolicy/
- SQLMap Usage: https://sqlmap.org/
- Semgrep Rules: https://semgrep.dev/r
- testssl.sh: https://testssl.sh/
