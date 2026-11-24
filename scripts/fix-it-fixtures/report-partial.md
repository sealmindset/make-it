# Security attestation -- re-scan, partly run

> A stand-in for a /nemo-it report, for /fix-it's tests (scripts/test-fix-it-true-results.sh). Bandit did not run, but its row is FAIL because ESLint, the other scanner in that row, found something: a FAIL row does not mean every scanner in it ran. pip-audit's row is NO FINDINGS and pip-audit is not among the tools that produced a result. The npm audit row is missing altogether.

## Scan Coverage

| Phase | Status | Findings |
|-------|--------|----------|
| Static Analysis (SAST) | Partial | 1 |
| Dependency Scanning | Completed | 0 |

**Tools used:** Trivy 0.50.1, Semgrep 1.70.0, ESLint 9.1.0, Playwright 1.44.0

**Not run:**
- Bandit -- not on this computer.

## Summary Dashboard

### Category Breakdown

| #  | Suite | Category | ID | Status | Findings | Highest Severity |
|----|-------|----------|----|--------|----------|------------------|
| 2 | Dependency & Container Security | pip-audit | DEP-PIP | NO FINDINGS | 0 | - |
| 3 | Dependency & Container Security | Trivy Container Scan | DEP-TRIVY | PASS | 0 | - |
| 4 | Static Analysis | Semgrep | SAST-SEMGREP | PASS | 0 | - |
| 5 | Static Analysis | Bandit / ESLint Security | SAST-LINT | FAIL | 1 | see below |
| 6 | OWASP Testing Guide | Authorization | OTG-AUTHZ | PASS | 0 | - |

### Severity Distribution

| Severity      | Count | Trend vs. Prior |
|---------------|-------|-----------------|
| Critical | 0 | - |
| High | 1 | - |
| Medium | 0 | - |
| Low | 0 | - |
| Informational | 0 | - |

## Findings

##### SAST-LINT-001: Use of eval in the settings page

- **Severity:** HIGH
- **Remediation type:** PROGRAMMATIC_FIX
