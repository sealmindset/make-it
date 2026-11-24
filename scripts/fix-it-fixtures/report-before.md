# Security attestation -- first scan

> A stand-in for a /nemo-it report, for /fix-it's tests (scripts/test-fix-it-true-results.sh). Eight findings, every check ran.

## Summary Dashboard

### Category Breakdown

| #  | Suite | Category | ID | Status | Findings | Highest Severity |
|----|-------|----------|----|--------|----------|------------------|
| 1 | Dependency & Container Security | npm audit | DEP-NPM | FAIL | 1 | see below |
| 2 | Dependency & Container Security | pip-audit | DEP-PIP | FAIL | 1 | see below |
| 3 | Dependency & Container Security | Trivy Container Scan | DEP-TRIVY | FAIL | 2 | see below |
| 4 | Static Analysis | Semgrep | SAST-SEMGREP | FAIL | 2 | see below |
| 5 | Static Analysis | Bandit / ESLint Security | SAST-LINT | FAIL | 1 | see below |
| 6 | OWASP Testing Guide | Authorization | OTG-AUTHZ | FAIL | 1 | see below |

## Findings

##### DEP-NPM-001: Remote code execution in the web framework (next)

- **Severity:** CRITICAL
- **Remediation type:** PROGRAMMATIC_FIX

##### DEP-PIP-001: Known flaw in the HTTP library (requests)

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### DEP-TRIVY-001: Known flaw in the base image (openssl)

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### DEP-TRIVY-002: Known flaw in the base image (zlib)

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### SAST-SEMGREP-001: SQL built from user input in the search route

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### SAST-SEMGREP-002: Unsafe loading of saved data (pickle)

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### OTG-AUTHZ-001: Any signed-in user can open another user's invoice

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX

##### SAST-LINT-001: Certificate checking switched off (verify=False)

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX
