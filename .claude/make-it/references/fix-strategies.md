# Fix Strategies Reference

## Purpose

This document maps security finding categories to specific automated fix strategies for the
`/fix-it` skill. Each strategy includes the detection pattern, the fix procedure, the
verification method, and the risk level.

## Classification Rules

Every finding from a `/nemo-it` attestation is classified using these rules:

| Classification | Criteria |
|---------------|----------|
| **AUTO** | Fix is mechanical, deterministic, and cannot change application behavior. No human judgment needed. |
| **SEMI-AUTO** | Fix is well-defined but touches application logic. Show the diff, get implicit approval (user can object). |
| **MANUAL** | Fix requires understanding business logic, architectural decisions, or has multiple valid approaches. |
| **SKIP** | Finding is informational, accepted risk, or N/A. |

---

## Strategy 1: Dependency Upgrades

### Detection Patterns
- npm audit findings with fix version available
- pip-audit findings with fix version available
- Trivy findings for packages with patched versions
- Any `DEP-*` finding ID in the attestation

### Fix Procedures

**1a. npm patch/minor upgrade (AUTO)**
```bash
npm audit fix
# Verify specific package version
npm ls [package]
```

**1b. npm major upgrade (SEMI-AUTO)**
```bash
npm install [package]@latest
# Show breaking changes from CHANGELOG
# Run full test suite
```

**1c. pip upgrade (AUTO if patch/minor, SEMI-AUTO if major)**
```bash
pip install [package]==[fixed_version]
# Update requirements.txt with new version
```

### Verification
- Run `npm audit` / `pip-audit` again to confirm CVE is resolved
- Run full test suite
- If Next.js was upgraded: `npm run build` must succeed

### Risk Level
- Patch/minor: LOW (auto)
- Major: MEDIUM (semi-auto, needs test verification)

### Special Cases

**Next.js upgrades:** Always SEMI-AUTO. Next.js major versions frequently have breaking
changes (middleware API, routing, server components). Run `npm run build` AND verify
key pages render.

**jsPDF/html2pdf.js:** If the app generates PDFs, verify PDF generation still works after
upgrade. If no PDF tests exist, mark as SEMI-AUTO.

**cryptography (Python):** Usually safe to upgrade within the same major. Verify JWT
signing/verification still works.

---

## Strategy 2: SSL/TLS Fixes

### Detection Patterns
- `verify=False` in httpx or requests calls
- Bandit finding: "Call to httpx/requests with verify=False"
- Semgrep TLS-related findings

### Fix Procedures

**2a. Remove verify=False (AUTO)**
```python
# Before:
async with httpx.AsyncClient(timeout=10.0, verify=False) as client:
# After:
async with httpx.AsyncClient(timeout=10.0) as client:
```

**2b. Make verify configurable via env var (SEMI-AUTO)**
Use when verify=False might be intentional (e.g., internal services with self-signed certs):
```python
import os
SSL_VERIFY = os.getenv("SSL_VERIFY", "true").lower() != "false"
async with httpx.AsyncClient(timeout=10.0, verify=SSL_VERIFY) as client:
```
Add `SSL_VERIFY=true` to `.env.example`.

### Verification
- Syntax check the modified file
- If tests exist for the HTTP call, run them

### Risk Level: LOW

---

## Strategy 3: Request Timeout Fixes

### Detection Patterns
- `requests.get/post/put/delete/patch()` without `timeout=` parameter
- Bandit finding: "Call to requests without timeout"

### Fix Procedure (AUTO)

```python
# Before:
response = requests.get(url)
response = requests.post(url, json=data)

# After:
response = requests.get(url, timeout=30)
response = requests.post(url, json=data, timeout=30)
```

Use `timeout=30` as default. If the call is to a known-slow service (AI provider, large
file download), use `timeout=120`.

### Verification
- Syntax check
- Run related tests if they exist

### Risk Level: LOW

---

## Strategy 4: SQL Injection Fixes

### Detection Patterns
- `sqlalchemy.text()` with f-strings or `.format()`
- Semgrep: "sqlalchemy.text passes the constructed SQL statement"
- Bandit: "Possible SQL injection vector through string-based query construction"
- `f"SELECT ... {variable}"` patterns

### Fix Procedure (SEMI-AUTO)

**4a. sqlalchemy.text with f-string -> bindparams:**
```python
# Before:
result = db.execute(text(f"SELECT * FROM repos WHERE org_id = {org_id}"))

# After:
result = db.execute(text("SELECT * FROM repos WHERE org_id = :org_id"), {"org_id": org_id})
```

**4b. sqlalchemy.text with .format() -> bindparams:**
```python
# Before:
query = "DELETE FROM {} WHERE org_id = :org_id".format(table_name)
result = db.execute(text(query), {"org_id": org_id})

# After (table names cannot be parameterized, validate against allowlist):
ALLOWED_TABLES = {"repositories", "scan_results", "findings"}
if table_name not in ALLOWED_TABLES:
    raise ValueError(f"Invalid table name: {table_name}")
query = f"DELETE FROM {table_name} WHERE org_id = :org_id"
result = db.execute(text(query), {"org_id": org_id})
```

**Important:** Table names and column names cannot be SQL parameters. They must be
validated against an allowlist. Only values can be parameterized.

### Verification
- Syntax check
- If the script has a dry-run mode, test it
- Run the project test suite

### Risk Level: MEDIUM (must preserve query behavior)

---

## Strategy 5: Weak Cryptography Fixes

### Detection Patterns
- `hashlib.md5()` used for security purposes
- `hashlib.sha1()` used for security purposes
- Semgrep/Bandit: "Use of weak MD5/SHA1 hash"

### Fix Procedure (SEMI-AUTO)

**5a. MD5 used for security -> SHA-256:**
```python
# Before:
import hashlib
hash_value = hashlib.md5(data.encode()).hexdigest()

# After:
import hashlib
hash_value = hashlib.sha256(data.encode()).hexdigest()
```

**5b. MD5 used for non-security (checksums, cache keys) -> mark safe:**
```python
# Before:
hash_value = hashlib.md5(data.encode()).hexdigest()

# After:
hash_value = hashlib.md5(data.encode(), usedforsecurity=False).hexdigest()
```

Determine which case applies by reading the surrounding code context.

### Verification
- If the hash is stored (DB, file), existing data will not match new hashes.
  Flag this as a migration concern.

### Risk Level: MEDIUM (may require data migration)

---

## Strategy 6: HTML Injection / XSS Fixes

### Detection Patterns
- Semgrep: "user input flowing into a manually constructed HTML string"
- `dangerouslySetInnerHTML` with AI/user content
- `innerHTML =` with dynamic content
- `f"<html>...{user_input}..."` patterns

### Fix Procedure (SEMI-AUTO)

**6a. Python HTML construction -> use html.escape:**
```python
# Before:
html_content = f"<div>{user_input}</div>"

# After:
import html
html_content = f"<div>{html.escape(user_input)}</div>"
```

**6b. React dangerouslySetInnerHTML -> sanitize with DOMPurify:**
```tsx
// Before:
<div dangerouslySetInnerHTML={{ __html: aiOutput }} />

// After:
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(aiOutput) }} />
```

**6c. If the HTML is intentional (markdown rendering) -> use allowlisted sanitizer:**
Preserve the rendering but add sanitization.

### Verification
- Syntax check
- Visual inspection if possible (does the output still look right?)

### Risk Level: MEDIUM

---

## Strategy 7: Pickle Deserialization Fixes

### Detection Patterns
- `pickle.load()`, `pickle.loads()`
- Semgrep/Bandit: "Avoid using pickle"

### Fix Procedure (SEMI-AUTO)

```python
# Before:
import pickle
with open(cache_file, 'rb') as f:
    data = pickle.load(f)

# After:
import json
with open(cache_file, 'r') as f:
    data = json.load(f)
```

Also update the write side:
```python
# Before:
with open(cache_file, 'wb') as f:
    pickle.dump(data, f)

# After:
with open(cache_file, 'w') as f:
    json.dump(data, f)
```

**Important:** If the pickled data contains Python objects that are not JSON-serializable
(datetime, set, custom classes), this fix requires a custom serializer. Mark as MANUAL.

### Verification
- Check that the data being serialized is JSON-compatible
- If cache files exist, they will need to be regenerated

### Risk Level: MEDIUM

---

## Strategy 8: AI Safety Integration

### Detection Patterns
- /nemo-it findings about AI agents/modules not using safety controls
- Files that import AI provider SDKs but not ai_safety modules
- LLM calls without sanitize/validate/mask pipeline

### Fix Procedure (SEMI-AUTO)

**8a. Add safety imports to an AI agent file:**
```python
# Add at top of file:
from src.services.ai_safety import (
    sanitize_prompt_input,
    validate_agent_output,
    mask_pii,
    unmask_pii,
    sanitize_ai_error,
)
```

**8b. Wrap an LLM call with the safety pipeline:**
```python
# Before:
response = client.messages.create(
    model=model,
    system=system_prompt,
    messages=[{"role": "user", "content": user_content}],
    max_tokens=4096,
)
result = response.content[0].text

# After:
sanitized_content = sanitize_prompt_input(user_content)
masked_content, pii_mappings = mask_pii(sanitized_content)
try:
    response = client.messages.create(
        model=model,
        system=system_prompt,
        messages=[{"role": "user", "content": masked_content}],
        max_tokens=4096,
    )
    result = response.content[0].text
    validation = validate_agent_output(result)
    result = validation["sanitized_text"]
    result = unmask_pii(result, pii_mappings)
except Exception as e:
    safe_error = sanitize_ai_error(e)
    raise RuntimeError(safe_error["message"]) from None
```

**8c. Route through existing LLM provider base class:**
If the project has a provider abstraction (like `llm_provider.py`), prefer routing
through it rather than wrapping individual calls. The base class already prepends the
safety preamble.

### Verification
- Syntax check
- Run guardrails/tests/ to verify safety modules still work
- If the file has its own tests, run them

### Risk Level: MEDIUM-HIGH (must understand each file's LLM usage pattern)

### When to classify as MANUAL
- File has complex multi-turn conversation management
- File uses streaming responses
- File has custom error handling that conflicts with safety wrappers
- File uses multiple LLM providers with different call signatures

---

## Strategy 9: Rate Limiting

### Detection Patterns
- /nemo-it findings about missing rate limiting on AI endpoints
- AI-facing routes without rate limit middleware

### Fix Procedure (SEMI-AUTO)

**9a. FastAPI with slowapi:**
```python
# Add to requirements.txt:
# slowapi

# In the router file:
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@router.post("/ai-chat")
@limiter.limit(f"{os.getenv('AI_RATE_LIMIT_REQUESTS_PER_MINUTE', '30')}/minute")
async def send_message(request: Request, ...):
    ...
```

**9b. Express with express-rate-limit:**
```javascript
const rateLimit = require('express-rate-limit');
const aiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: parseInt(process.env.AI_RATE_LIMIT_REQUESTS_PER_MINUTE || '30'),
  message: { error: 'Too many AI requests. Please try again later.' }
});
router.use('/ai', aiLimiter);
```

### Verification
- Syntax check
- Verify the rate limiter import resolves (package installed)
- Ideally, send rapid requests to verify 429 response

### Risk Level: MEDIUM

---

## Strategy 10: Configuration Fixes

### Detection Patterns
- Terraform misconfigurations (TLS version, ECR mutability, VPC public IP)
- File permission issues (chmod too permissive)
- Binding to 0.0.0.0

### Fix Procedures

**10a. Terraform TLS version (AUTO):**
```hcl
# Before:
ssl_policy = "ELBSecurityPolicy-2016-08"
# After:
ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"
```

**10b. Terraform ECR immutability (AUTO):**
```hcl
image_tag_mutability = "IMMUTABLE"
```

**10c. Terraform VPC public IP (AUTO):**
```hcl
map_public_ip_on_launch = false
```

**10d. File permissions (AUTO):**
```python
# Before:
os.chmod(temp_dir, 0o755)
# After:
os.chmod(temp_dir, 0o700)
```

**10e. Binding to 0.0.0.0 (SEMI-AUTO):**
```python
# Before:
uvicorn.run(app, host="0.0.0.0", port=8000)
# After:
uvicorn.run(app, host=os.getenv("BIND_HOST", "127.0.0.1"), port=8000)
```
Add `BIND_HOST=0.0.0.0` to `.env.example` (Docker needs 0.0.0.0, local dev needs 127.0.0.1).

### Risk Level: LOW (config) to MEDIUM (bind address)

---

## Strategy 11: Temp File Fixes

### Detection Patterns
- Bandit: "Probable insecure usage of temp file/directory"
- `tempfile.mktemp()` (deprecated, race condition)
- Manual temp file creation with predictable names

### Fix Procedure (SEMI-AUTO)

```python
# Before:
import tempfile
tmp_path = tempfile.mktemp()
with open(tmp_path, 'w') as f:
    f.write(data)

# After:
import tempfile
fd, tmp_path = tempfile.mkstemp()
try:
    with os.fdopen(fd, 'w') as f:
        f.write(data)
finally:
    os.unlink(tmp_path)
```

### Risk Level: LOW

---

## Strategy 12: Hardcoded Secrets

### Detection Patterns
- Semgrep/Bandit: hardcoded password, API key, secret
- `password = "actual_value"` patterns
- AWS access keys (AKIA...) in source files

### Fix Procedure (SEMI-AUTO)

```python
# Before:
DB_PASSWORD = "my_secret_password"

# After:
DB_PASSWORD = os.getenv("DB_PASSWORD")
if not DB_PASSWORD:
    raise ValueError("DB_PASSWORD environment variable is required")
```

Add placeholder to `.env.example`:
```
DB_PASSWORD=change_this_to_a_secure_value
```

### Verification
- Ensure the env var is set in .env (not committed)
- Ensure .env.example has the placeholder
- Verify the app can start with the env var set

### Risk Level: MEDIUM

---

## Decision Tree

When classifying a finding, follow this tree:

```
Is it a dependency CVE?
  Yes -> Is a fix version available?
    Yes -> Is it a major version bump?
      Yes -> SEMI-AUTO (Strategy 1b/1c)
      No  -> AUTO (Strategy 1a/1c)
    No  -> MANUAL (no automated fix possible)
  No -> Continue

Is it a code pattern with a mechanical fix?
  Yes -> Does the fix change application behavior?
    No  -> AUTO (Strategies 2-3, 10)
    Yes -> Does it require understanding business logic?
      No  -> SEMI-AUTO (Strategies 4-7, 9, 11, 12)
      Yes -> MANUAL
  No -> Continue

Is it an AI safety integration gap?
  Yes -> Can I identify all LLM call sites in the file?
    Yes -> Is the calling pattern standard (single call, sync/async)?
      Yes -> SEMI-AUTO (Strategy 8)
      No  -> MANUAL (streaming, multi-turn, custom patterns)
    No  -> MANUAL
  No -> Continue

Is it informational or accepted risk?
  Yes -> SKIP
  No  -> MANUAL (unknown finding type)
```

---

## Fix Verification Matrix

After each fix category, run these checks:

| Fix Category | Syntax Check | Unit Tests | Build | Full Test Suite |
|-------------|-------------|-----------|-------|----------------|
| Dependencies | - | - | YES | YES |
| SSL/TLS | YES | If exist | - | - |
| Timeouts | YES | If exist | - | - |
| SQL Injection | YES | If exist | - | YES |
| Crypto | YES | If exist | - | - |
| HTML/XSS | YES | If exist | YES | - |
| Pickle | YES | If exist | - | - |
| AI Safety | YES | guardrails/ | - | YES |
| Rate Limiting | YES | - | - | - |
| Config | YES | - | - | - |
| Temp Files | YES | If exist | - | - |
| Secrets | YES | - | YES | YES |
