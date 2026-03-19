# Security Attestation Report — /nemo-it

> **Application:** [APP_NAME]
> **Version:** [APP_VERSION]
> **Generated:** [TIMESTAMP]
> **Attestation Version:** [ATTESTATION_VERSION]
> **Snapshot Path:** `docs/attestations/nemo-it/[YYYY-MM-DD]-v[N].md`
> **Environment:** [TEST_ENVIRONMENT]
> **Assessed By:** [ASSESSOR_NAME_OR_TOOL]
> **AI Features Present:** [YES | NO]

---

## Executive Summary

This report provides a point-in-time security attestation for **[APP_NAME]** version **[APP_VERSION]**, generated on **[TIMESTAMP]**. It is produced by the `/nemo-it` skill and is **purely informational** -- it does not constitute a blocking release gate.

**Overall Risk Posture:** [CRITICAL | HIGH | MODERATE | LOW | MINIMAL]

[EXECUTIVE_SUMMARY_NARRATIVE]

**Key Metrics:**

| Metric                        | Value                |
|-------------------------------|----------------------|
| Total test categories         | [TOTAL_CATEGORIES]   |
| Categories passed             | [CATEGORIES_PASSED]  |
| Categories failed             | [CATEGORIES_FAILED]  |
| Categories N/A                | [CATEGORIES_NA]      |
| Total findings                | [TOTAL_FINDINGS]     |
| Critical findings             | [CRITICAL_COUNT]     |
| High findings                 | [HIGH_COUNT]         |
| Medium findings               | [MEDIUM_COUNT]       |
| Low findings                  | [LOW_COUNT]          |
| Informational findings        | [INFO_COUNT]         |
| Exceptions granted            | [EXCEPTIONS_COUNT]   |

**Intended Audience:** GRC Director, Security Leadership, Engineering Leads, Compliance Officers.

**Disclaimer:** This attestation is a snapshot assessment for risk awareness and compliance monitoring. It does not guarantee the absence of vulnerabilities. Findings should be triaged through standard vulnerability management processes.

---

## Summary Dashboard

### Category Breakdown

| #  | Suite                              | Category                              | ID            | Status         | Findings | Highest Severity |
|----|------------------------------------|---------------------------------------|---------------|----------------|----------|------------------|
| 1  | NeMo Guardrails AI Safety          | Prompt Injection Resistance           | NEMO-PIR      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 2  | NeMo Guardrails AI Safety          | Jailbreak Resistance                  | NEMO-JBR      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 3  | NeMo Guardrails AI Safety          | Toxicity / Bias Detection             | NEMO-TBD      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 4  | NeMo Guardrails AI Safety          | Topic Boundary Enforcement            | NEMO-TBE      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 5  | NeMo Guardrails AI Safety          | PII Leakage Prevention                | NEMO-PII      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 6  | NeMo Guardrails AI Safety          | Hallucination Detection               | NEMO-HAL      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 7  | OWASP Testing Guide                | Information Gathering                 | OTG-INFO      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 8  | OWASP Testing Guide                | Configuration & Deployment Management | OTG-CONFIG    | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 9  | OWASP Testing Guide                | Identity Management                   | OTG-IDENT     | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 10 | OWASP Testing Guide                | Authentication                        | OTG-AUTHN     | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 11 | OWASP Testing Guide                | Authorization                         | OTG-AUTHZ     | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 12 | OWASP Testing Guide                | Session Management                    | OTG-SESS      | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 13 | OWASP Testing Guide                | Input Validation                      | OTG-INPVAL    | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 14 | OWASP Testing Guide                | Error Handling                        | OTG-ERR       | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 15 | OWASP Testing Guide                | Cryptography                          | OTG-CRYPST    | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 16 | OWASP Testing Guide                | Business Logic                        | OTG-BUSLOGIC  | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 17 | OWASP Testing Guide                | Client-Side                           | OTG-CLIENT    | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 18 | Dependency & Container Security    | npm audit                             | DEP-NPM       | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 19 | Dependency & Container Security    | pip-audit                             | DEP-PIP       | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 20 | Dependency & Container Security    | Trivy Container Scan                  | DEP-TRIVY     | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 21 | Static Analysis                    | Semgrep                               | SAST-SEMGREP  | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |
| 22 | Static Analysis                    | Bandit / ESLint Security              | SAST-LINT     | [PASS/FAIL/NA] | [COUNT]  | [SEVERITY]       |

### Severity Distribution

| Severity      | Count          | Trend vs. Prior |
|---------------|----------------|-----------------|
| Critical      | [CRITICAL_COUNT] | [TREND]       |
| High          | [HIGH_COUNT]     | [TREND]       |
| Medium        | [MEDIUM_COUNT]   | [TREND]       |
| Low           | [LOW_COUNT]      | [TREND]       |
| Informational | [INFO_COUNT]     | [TREND]       |

### Test Environment Details

| Property               | Value                          |
|------------------------|--------------------------------|
| Target Environment     | [TEST_ENVIRONMENT]             |
| Target URL / Endpoint  | [TARGET_URL]                   |
| OS / Platform          | [OS_PLATFORM]                  |
| Runtime Version        | [RUNTIME_VERSION]              |
| Container Image        | [CONTAINER_IMAGE]              |
| Container Image Digest | [CONTAINER_IMAGE_DIGEST]       |
| Branch / Commit        | [GIT_BRANCH] / [GIT_COMMIT]   |
| CI Pipeline Run        | [CI_RUN_URL]                   |
| Test Duration          | [TEST_DURATION]                |

---

## Risk Matrix Reference

The following likelihood-by-impact matrix is used to classify all findings in this report.

|                    | **Negligible** | **Minor**  | **Moderate** | **Significant** | **Severe** |
|--------------------|----------------|------------|--------------|-----------------|------------|
| **Almost Certain** | Medium         | High       | High         | Critical        | Critical   |
| **Likely**         | Low            | Medium     | High         | High            | Critical   |
| **Possible**       | Low            | Medium     | Medium       | High            | High       |
| **Unlikely**       | Low            | Low        | Medium       | Medium          | High       |
| **Rare**           | Informational  | Low        | Low          | Medium          | Medium     |

**Definitions:**
- **Likelihood:** How probable is exploitation? (Rare / Unlikely / Possible / Likely / Almost Certain)
- **Impact:** What is the business consequence? (Negligible / Minor / Moderate / Significant / Severe)

---

## Suite 1: NeMo Guardrails AI Safety

> If this application has **no AI features**, all categories in this suite are marked **N/A**.
> AI Features Present: **[YES | NO]**

### 1.1 Prompt Injection Resistance (NEMO-PIR)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-PIR-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Input sanitization layer before LLM invocation]
  - [CONTROL_2 -- e.g., NeMo Guardrails input rail configuration]
  - [CONTROL_3 -- e.g., Rate limiting on AI endpoints]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 1.2 Jailbreak Resistance (NEMO-JBR)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-JBR-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., System prompt hardening]
  - [CONTROL_2 -- e.g., Output validation rail]
  - [CONTROL_3 -- e.g., Multi-turn conversation limits]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 1.3 Toxicity / Bias Detection (NEMO-TBD)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-TBD-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Content moderation output filter]
  - [CONTROL_2 -- e.g., Bias detection model in pipeline]
  - [CONTROL_3 -- e.g., Human review escalation workflow]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 1.4 Topic Boundary Enforcement (NEMO-TBE)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-TBE-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Topic guardrail Colang configuration]
  - [CONTROL_2 -- e.g., Allowed topic whitelist enforcement]
  - [CONTROL_3 -- e.g., Off-topic response redirection]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 1.5 PII Leakage Prevention (NEMO-PII)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-PII-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., PII regex detection in output rail]
  - [CONTROL_2 -- e.g., Data masking middleware]
  - [CONTROL_3 -- e.g., DLP integration at network boundary]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 1.6 Hallucination Detection (NEMO-HAL)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### NEMO-HAL-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Fact-checking output rail with knowledge base]
  - [CONTROL_2 -- e.g., Confidence scoring threshold]
  - [CONTROL_3 -- e.g., Citation enforcement in responses]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

## Suite 2: OWASP Testing Guide

### 2.1 Information Gathering (OTG-INFO)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-INFO-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Suppress server version headers]
  - [CONTROL_2 -- e.g., Custom error pages without stack traces]
  - [CONTROL_3 -- e.g., WAF fingerprint obfuscation rules]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.2 Configuration & Deployment Management (OTG-CONFIG)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-CONFIG-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Enforce security headers via reverse proxy]
  - [CONTROL_2 -- e.g., Disable debug mode in production configuration]
  - [CONTROL_3 -- e.g., Infrastructure-as-code hardening templates]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.3 Identity Management (OTG-IDENT)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-IDENT-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Centralized identity provider integration]
  - [CONTROL_2 -- e.g., Account enumeration prevention]
  - [CONTROL_3 -- e.g., Username policy enforcement]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.4 Authentication (OTG-AUTHN)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-AUTHN-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., MFA enforcement for all accounts]
  - [CONTROL_2 -- e.g., Account lockout after failed attempts]
  - [CONTROL_3 -- e.g., Credential stuffing detection via WAF]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.5 Authorization (OTG-AUTHZ)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-AUTHZ-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., RBAC policy enforcement at API gateway]
  - [CONTROL_2 -- e.g., IDOR protection via indirect references]
  - [CONTROL_3 -- e.g., Privilege escalation monitoring alerts]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.6 Session Management (OTG-SESS)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-SESS-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Secure cookie attributes (HttpOnly, Secure, SameSite)]
  - [CONTROL_2 -- e.g., Session timeout enforcement]
  - [CONTROL_3 -- e.g., Session fixation protection via token rotation]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.7 Input Validation (OTG-INPVAL)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-INPVAL-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Server-side input validation and sanitization]
  - [CONTROL_2 -- e.g., WAF rules for XSS/SQLi/command injection patterns]
  - [CONTROL_3 -- e.g., Parameterized queries for all database access]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.8 Error Handling (OTG-ERR)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-ERR-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Centralized error handling middleware]
  - [CONTROL_2 -- e.g., Generic error responses in production]
  - [CONTROL_3 -- e.g., Error logging to SIEM without client exposure]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.9 Cryptography (OTG-CRYPST)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-CRYPST-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Enforce TLS 1.2+ with strong cipher suites]
  - [CONTROL_2 -- e.g., Key management via HSM or cloud KMS]
  - [CONTROL_3 -- e.g., Certificate pinning for critical endpoints]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.10 Business Logic (OTG-BUSLOGIC)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-BUSLOGIC-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Workflow state machine enforcement]
  - [CONTROL_2 -- e.g., Server-side business rule validation]
  - [CONTROL_3 -- e.g., Anomaly detection on transaction patterns]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 2.11 Client-Side (OTG-CLIENT)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tests Run:** [TEST_COUNT]
- **Tests Passed:** [TESTS_PASSED]
- **Findings:** [FINDING_COUNT]

#### Findings

##### OTG-CLIENT-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH | ENDPOINT | FUNCTION]`
- **How the failure occurred:** [ATTACK_VECTOR_AND_TECHNIQUE]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Content Security Policy (CSP) headers]
  - [CONTROL_2 -- e.g., Subresource Integrity (SRI) for external scripts]
  - [CONTROL_3 -- e.g., DOM-based XSS prevention via trusted types]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

## Suite 3: Dependency & Container Security

### 3.1 npm audit (DEP-NPM)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tool Version:** [NPM_AUDIT_VERSION]
- **Total Dependencies Scanned:** [DEP_COUNT]
- **Findings:** [FINDING_COUNT]

#### Findings

##### DEP-NPM-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION -- e.g., CVE identifier, affected package, vulnerable version range]
- **Where it occurred:** `[PACKAGE_NAME@VERSION]` in `[LOCKFILE_PATH]`
- **How the failure occurred:** [VULNERABILITY_TYPE -- e.g., prototype pollution, ReDoS, path traversal]
- **Root cause analysis:** [ROOT_CAUSE -- e.g., transitive dependency from package X]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Upgrade to patched version]
  - [CONTROL_2 -- e.g., Override resolution in package.json]
  - [CONTROL_3 -- e.g., WAF rule to block exploitation pattern]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 3.2 pip-audit (DEP-PIP)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tool Version:** [PIP_AUDIT_VERSION]
- **Total Dependencies Scanned:** [DEP_COUNT]
- **Findings:** [FINDING_COUNT]

#### Findings

##### DEP-PIP-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION -- e.g., CVE identifier, affected package, vulnerable version range]
- **Where it occurred:** `[PACKAGE_NAME==VERSION]` in `[REQUIREMENTS_PATH]`
- **How the failure occurred:** [VULNERABILITY_TYPE -- e.g., deserialization flaw, SSRF, arbitrary code execution]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Pin to patched version]
  - [CONTROL_2 -- e.g., Network segmentation to limit blast radius]
  - [CONTROL_3 -- e.g., Runtime application self-protection (RASP)]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 3.3 Trivy Container Scan (DEP-TRIVY)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tool Version:** [TRIVY_VERSION]
- **Image Scanned:** [CONTAINER_IMAGE]
- **OS Packages Scanned:** [OS_PKG_COUNT]
- **Language Packages Scanned:** [LANG_PKG_COUNT]
- **Findings:** [FINDING_COUNT]

#### Findings

##### DEP-TRIVY-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **What happened:** [DETAILED_DESCRIPTION -- e.g., CVE identifier, affected OS/language package, fixed version if available]
- **Where it occurred:** `[PACKAGE_NAME]` in `[IMAGE_LAYER]`
- **How the failure occurred:** [VULNERABILITY_TYPE -- e.g., privilege escalation, RCE, information disclosure]
- **Root cause analysis:** [ROOT_CAUSE -- e.g., outdated base image, unpatched OS library]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Rebuild with updated base image]
  - [CONTROL_2 -- e.g., Use distroless or minimal base image]
  - [CONTROL_3 -- e.g., Runtime container security monitoring]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

## Suite 4: Static Analysis

### 4.1 Semgrep (SAST-SEMGREP)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tool Version:** [SEMGREP_VERSION]
- **Rulesets Used:** [RULESET_LIST]
- **Files Scanned:** [FILE_COUNT]
- **Findings:** [FINDING_COUNT]

#### Findings

##### SAST-SEMGREP-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **Rule ID:** [SEMGREP_RULE_ID]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH]:[LINE_NUMBER]` in function `[FUNCTION_NAME]`
- **How the failure occurred:** [CODE_PATTERN_AND_RISK -- e.g., hardcoded secret, unsafe deserialization, SQL concatenation]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Secret scanning in CI/CD pipeline]
  - [CONTROL_2 -- e.g., Code refactoring to use safe API]
  - [CONTROL_3 -- e.g., Pre-commit hook enforcement]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

### 4.2 Bandit / ESLint Security (SAST-LINT)

- **Status:** [PASS / FAIL / NA]
- **Date Tested:** [TEST_DATE]
- **Tool Version:** [BANDIT_OR_ESLINT_VERSION]
- **Plugins / Configs:** [PLUGIN_LIST -- e.g., eslint-plugin-security, bandit default profile]
- **Files Scanned:** [FILE_COUNT]
- **Findings:** [FINDING_COUNT]

#### Findings

##### SAST-LINT-[NNN]: [FINDING_TITLE]

- **Severity:** [CRITICAL / HIGH / MEDIUM / LOW / INFO]
- **Rule ID:** [LINT_RULE_ID]
- **What happened:** [DETAILED_DESCRIPTION]
- **Where it occurred:** `[FILE_PATH]:[LINE_NUMBER]` in function `[FUNCTION_NAME]`
- **How the failure occurred:** [CODE_PATTERN_AND_RISK -- e.g., eval usage, subprocess shell=True, non-literal regex]
- **Root cause analysis:** [ROOT_CAUSE]
- **Risk matrix entry:**
  - Likelihood: [LIKELIHOOD]
  - Impact: [IMPACT]
  - Risk Level: **[RISK_LEVEL]**
- **Compensating controls:**
  - [CONTROL_1 -- e.g., Replace unsafe function with safe alternative]
  - [CONTROL_2 -- e.g., Input validation before dynamic evaluation]
  - [CONTROL_3 -- e.g., Sandbox execution environment]
- **Remediation type:** [PROGRAMMATIC_FIX | TECHNOLOGICAL_CONTROL | PROCESS_CONTROL | ACCEPT_RISK]
- **Evidence:** [LINK_OR_REFERENCE_TO_RAW_OUTPUT]

---

## Exceptions Register

Exceptions document accepted risks where findings will not be remediated within standard SLA timelines.

| Exception ID     | Finding ID          | Severity | Justification                  | Compensating Control           | Expiration Date     | Approved By        |
|------------------|---------------------|----------|--------------------------------|--------------------------------|---------------------|--------------------|
| [EXCEPTION_ID]   | [FINDING_ID]        | [SEV]    | [JUSTIFICATION]                | [COMPENSATING_CONTROL]         | [EXPIRATION_DATE]   | [APPROVER]         |

---

## Historical Comparison

| Metric              | Prior ([PRIOR_DATE]) | Current ([CURRENT_DATE]) | Delta   |
|---------------------|----------------------|--------------------------|---------|
| Total Findings      | [PRIOR_TOTAL]        | [CURRENT_TOTAL]          | [DELTA] |
| Critical            | [PRIOR_CRITICAL]     | [CURRENT_CRITICAL]       | [DELTA] |
| High                | [PRIOR_HIGH]         | [CURRENT_HIGH]           | [DELTA] |
| Medium              | [PRIOR_MEDIUM]       | [CURRENT_MEDIUM]         | [DELTA] |
| Low                 | [PRIOR_LOW]          | [CURRENT_LOW]            | [DELTA] |
| Informational       | [PRIOR_INFO]         | [CURRENT_INFO]           | [DELTA] |
| Open Exceptions     | [PRIOR_EXCEPTIONS]   | [CURRENT_EXCEPTIONS]     | [DELTA] |

---

## Machine-Readable Output (Optional)

If generated, machine-readable artifacts are stored alongside this attestation:

| Format    | File                                                            | Purpose                              |
|-----------|-----------------------------------------------------------------|--------------------------------------|
| JSON      | `docs/attestations/nemo-it/[YYYY-MM-DD]-v[N].json`             | Programmatic consumption, dashboards |
| JUnit XML | `docs/attestations/nemo-it/[YYYY-MM-DD]-v[N]-junit.xml`        | CI/CD integration, test reporting    |

---

## Secure-by-Design Coverage (/make-it Cross-Reference)

This section maps each finding to whether it **would have been prevented** if the application
had been built (or retrofitted) using the `/make-it` skill's guardrails. This helps teams
understand the value of secure-by-design practices vs. post-hoc scanning.

### Prevention Classification

| Classification | Meaning |
|---------------|---------|
| **Prevented by /make-it** | This finding would NOT exist in an app built by /make-it. The guardrail or safety control is built into the framework by default. |
| **Reduced by /make-it** | /make-it includes controls that reduce the severity or likelihood of this finding, but cannot fully eliminate it (e.g., dependency vulnerabilities that emerge after build time). |
| **Not covered by /make-it** | This is a net-new gap that /make-it does not currently address. Consider proposing an enhancement to the /make-it guardrails. |

### Finding Prevention Matrix

| Finding ID | Severity | Category | Prevention Status | /make-it Control |
|-----------|----------|----------|-------------------|-----------------|
| [FINDING_ID] | [SEV] | [CATEGORY] | [PREVENTED / REDUCED / NOT_COVERED] | [GUARDRAIL_REFERENCE or "N/A"] |

### AI Safety Prevention Summary (if AI features present)

| AI Safety Control | /make-it Provides | Status in This App |
|-------------------|-------------------|-------------------|
| Input sanitization (sanitizePromptInput) | Yes -- lib/ai/sanitize.ts, called by BaseAgent | [PRESENT / ABSENT] |
| Delimiter tags (`<user_input>`) | Yes -- all prompts use delimiter pattern | [PRESENT / ABSENT] |
| System prompt hardening (anti-injection) | Yes -- safety block appended to all agent prompts | [PRESENT / ABSENT] |
| Output validation (validateAgentOutput) | Yes -- lib/ai/validate.ts, schema + range checks | [PRESENT / ABSENT] |
| Output encoding (XSS prevention) | Yes -- escaped rendering, no dangerouslySetInnerHTML | [PRESENT / ABSENT] |
| AI rate limiting (per-user) | Yes -- lib/ai/rate-limit.ts middleware on AI routes | [PRESENT / ABSENT] |
| Prompt size validation | Yes -- enforced in BaseAgent before AI call | [PRESENT / ABSENT] |
| PII masking before AI submission | Yes -- lib/ai/pii-masker.ts with pseudonymization | [PRESENT / ABSENT] |
| AI error sanitization | Yes -- lib/ai/errors.ts, generic client messages | [PRESENT / ABSENT] |
| Conversation history limits | Yes -- AI_MAX_HISTORY_TURNS with server-side storage | [PRESENT / ABSENT] |
| NeMo Guardrails test suite | Yes -- 18 tests at build, 60 at ship | [PRESENT / ABSENT] |
| AI safety attestation | Yes -- auto-generated in docs/attestations/ | [PRESENT / ABSENT] |

### Coverage Statistics

| Metric | Count | Percentage |
|--------|-------|-----------|
| Findings prevented by /make-it | [COUNT] | [PCT]% |
| Findings reduced by /make-it | [COUNT] | [PCT]% |
| Findings not covered by /make-it | [COUNT] | [PCT]% |
| Total findings | [TOTAL] | 100% |

> **Interpretation:** If [PCT_PREVENTED]% of findings would have been prevented by /make-it,
> this demonstrates the value of secure-by-design development practices. The remaining
> [PCT_NOT_COVERED]% represent areas where operational controls, dependency management,
> or /make-it enhancements are needed.

---

## Appendix A: Tool Versions and Configuration

| Tool            | Version              | Configuration / Rulesets                  |
|-----------------|----------------------|-------------------------------------------|
| NeMo Guardrails | [NEMO_VERSION]       | [NEMO_CONFIG_PATH]                        |
| OWASP ZAP / Manual | [ZAP_VERSION]     | [ZAP_POLICY]                              |
| npm audit       | [NPM_VERSION]        | [AUDIT_LEVEL]                             |
| pip-audit       | [PIP_AUDIT_VERSION]  | [PIP_AUDIT_FLAGS]                         |
| Trivy           | [TRIVY_VERSION]      | [TRIVY_FLAGS]                             |
| Semgrep         | [SEMGREP_VERSION]    | [SEMGREP_RULESETS]                        |
| Bandit          | [BANDIT_VERSION]     | [BANDIT_PROFILE]                          |
| ESLint          | [ESLINT_VERSION]     | [ESLINT_CONFIG_PATH]                      |

## Appendix B: Glossary

| Term                    | Definition                                                                                          |
|-------------------------|-----------------------------------------------------------------------------------------------------|
| Compensating Control    | An alternative safeguard that reduces risk when the primary control is not feasible                  |
| Programmatic Fix        | A code-level change that directly resolves the vulnerability                                        |
| Technological Control   | An infrastructure or platform-level control (WAF, DLP, RASP) that mitigates the risk               |
| Process Control         | An organizational procedure (review cadence, manual check) that reduces likelihood or impact        |
| Accept Risk             | Formal acknowledgment that the residual risk is within tolerance and no further action is planned    |
| N/A                     | Category is not applicable to this application (e.g., no AI features for NeMo suite)                |

---

*This attestation is informational only and does not constitute a release gate. It is intended to support GRC oversight and continuous risk monitoring. Findings should be triaged through the organization's standard vulnerability management process.*

*Template version: 1.1.0 | Skill: /nemo-it | Added: Secure-by-Design Coverage cross-reference*
