# Security attestation -- re-scan

> A stand-in for a /nemo-it report, for /fix-it's tests (scripts/test-fix-it-true-results.sh). Trivy was missing this time: it is under "Not run:", its row is NOT RUN and its two findings are simply absent. Four findings are listed, all HIGH.

## Scan Coverage

| Phase | Status | Findings |
|-------|--------|----------|
| Static Analysis (SAST) | Completed | 3 |
| Dependency Scanning | Partial | 0 |

**Tools used:** npm audit 10.8.2, pip-audit 2.7.3, Semgrep 1.70.0, Bandit 1.7.8, ESLint 9.1.0, Playwright 1.44.0

**Not run:**
- Trivy -- not on this computer.

## Summary Dashboard

### Category Breakdown

| #  | Suite | Category | ID | Status | Findings | Highest Severity |
|----|-------|----------|----|--------|----------|------------------|
| 1 | Dependency & Container Security | npm audit | DEP-NPM | PASS | 0 | - |
| 2 | Dependency & Container Security | pip-audit | DEP-PIP | PASS | 0 | - |
| 3 | Dependency & Container Security | Trivy Container Scan | DEP-TRIVY | NOT RUN | 0 | - |
| 4 | Static Analysis | Semgrep | SAST-SEMGREP | FAIL | 2 | see below |
| 5 | Static Analysis | Bandit / ESLint Security | SAST-LINT | FAIL | 1 | see below |
| 6 | OWASP Testing Guide | Authorization | OTG-AUTHZ | FAIL | 1 | see below |

### Severity Distribution

| Severity      | Count | Trend vs. Prior |
|---------------|-------|-----------------|
| Critical | 0 | - |
| High | 4 | - |
| Medium | 0 | - |
| Low | 0 | - |
| Informational | 0 | - |

## Findings

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
