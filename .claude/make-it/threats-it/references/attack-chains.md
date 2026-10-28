# Attack chains

Every attack in the threat gets its own chain. A chain describes **what the attacker does** — behaviour, not product
— so the analysis still works for the next threat that uses the same moves against different software. Each chain
has three parts: a flow diagram, a stage table, and a short "<Org>" line. The report ends the chains section
with **what the chains have in common** (behaviours that recur, and the detection source each needs).

## 1. Flow diagram (required for every chain)

Plain-text, vertical, one box-free line per stage, joined by `│` and `▼`. Under a stage, indented `│` lines carry the
mechanism (the *how*). Use exact property paths, parameter names, file names, ports and IDs from the sources — a
diagram an engineer can hunt from. Put it in a fenced code block (` ```text `) so the PDF keeps the layout.

Rules:
- One stage = one attacker action that leaves (or could leave) a signal. Split a stage when its signal differs.
- Mechanism lines quote the source's exact strings (paths, property names, values). No invented detail; if the
  source does not give the value, say "(not published)".
- Mark the point where a defender's control would break the chain with `← break here: <control>` when known.
- Mark stages that happened before the defender's oldest log with `(predates retention)` in the <Org> table.
- Keep it under ~40 lines; split long chains into phases (initial access / escalation / persistence / impact).

### Reference example: Spring4Shell (CVE-2022-22965)

KEV: "Spring Framework JDK 9+ Remote Code Execution Vulnerability … via data binding" (added 2022-04-04).

```text
Attacker HTTP Request
        │
        ▼
Spring DispatcherServlet
        │
        ▼
WebDataBinder processes request parameters
        │  Spring binds arbitrary parameter names to object properties
        │  via nested property path traversal (e.g., "a.b.c.d")
        ▼
getClass().getModule().getClassLoader()   ← JDK 9+ exposes this path
        │
        ▼
Tomcat's ParallelWebappClassLoader
        │  attacker reaches Tomcat's AccessLogValve via:
        │  class.module.classLoader.resources.context
        │    .parent.pipeline.first.*
        ▼
AccessLogValve properties manipulated:
  - pattern    → JSP webshell payload
  - directory  → webapps/ROOT
  - prefix     → arbitrary filename
  - suffix     → .jsp
  - fileDateFormat → "" (forces immediate write)
        │
        ▼
Webshell written to Tomcat webroot
        │
        ▼
Remote Code Execution via HTTP request to webshell
```

Its stage table (shape every chain follows):

| Stage | Behaviour | ATT&CK | Signal | Telemetry → hunt result | Standing detection |
|---|---|---|---|---|---|
| 1 | Crafted parameters bind through `class.module.classLoader…` | T1190 | Request parameters containing `class.module.classLoader` | Web server / WAF logs → (result) | WAF rule? state |
| 2 | AccessLogValve re-pointed to write a `.jsp` into `webapps/ROOT` | T1505.003 | New `.jsp` file in webroot; access-log config change | File-integrity / endpoint file events → | rule? |
| 3 | Commands issued through the webshell | T1505.003, T1059 | Tomcat process spawning a shell | Endpoint process events → | rule? |

## 2. Stage table (required)

Columns: **Stage | Behaviour | ATT&CK | Signal | <Org>: telemetry → hunt result | Standing detection rule (state)**.
- Behaviour: the attacker action in plain words.
- ATT&CK: IDs verified with `scripts/attack_ids.py` (record the version, e.g. v20.0, in `data/curated/attack-ids.json`).
  Mark the source's own mappings "(brief)"; everything else is this report's mapping and the report says so.
- Signal: what the action leaves behind (log field, file, process, network flow).
- Telemetry → result: which table/log at the organisation holds it, its retention, and what the hunt found
  (0 / n hits / not assessed + why). "Not assessed" must name the missing source.
- Standing detection: rule name and state from `sentinel_coverage.py` (live / partial / blind / disabled / none), plus
  "Defender / MDR native detection not verified" when that is the case.

Under the table: **Exposure** (where the organisation is open to this chain, linking to the exposure section) and
**Gap** (which stage is unwatched and what closes it, with volumes or licences where known).

## 3. Chain patterns seen so far (reuse when a new threat matches)

| Pattern | Typical stages | Key signals |
|---|---|---|
| Vendor app credential abuse (ConnectWise/SkyKick 2026-10) | spray → stolen app credential → client-credential sign-in from new network → Graph recon → app self-grants role → secrets planted on other apps | SP sign-in IP/ASN vs baseline; Graph app-only reads; AuditLogs role/credential events initiated by an app; app-only Graph `addPassword`/`roleAssignments` |
| Update-channel tampering (AOMEI/UNC7017 2026) | vendor update files swapped briefly → unsigned downloader → signed binary side-loads DLL → scheduled task → follow-on C2 → forced NTLM auth via WebDAV | updater spawning unsigned exe; signed binary loading unsigned DLL from own folder; task to user-writable path; outbound SMB/WebDAV auth |
| Internet-facing appliance exploitation (KEV edge devices) | unauth bypass / traversal → command or code exec → root → implant/web shell surviving patch → credential theft / lateral | appliance logs (CommonSecurityLog), management-interface exposure, new admin accounts; vendor compromise checks |
| Public web-app exploitation (Magento, WordPress plugins, Spring4Shell) | injection / binding → file write → web shell → commands | WAF/web logs, new server-side files, web process spawning shells |
| Proxyjacking / residential proxies | old flaws on NAS/NVR/SAP → proxyware → SSH keys → attackers route sign-ins via victims' IPs | many accounts from one consumer-ISP IP; impossible-travel blind spot |
| Malicious file with MOTW bypass / preview-pane exploit | phish → no Zone.Identifier → user opens / preview renders → code | mail telemetry; Office/browser child processes; patch state |

## 4. "What the chains have in common"

Close with 2–4 recurring behaviours, each with the detection source it needs (sign-in logs, endpoint, appliance,
web), and the organisation's state for each (logged? watched? not visible?). This is what makes the report useful
for the next threat, and it is what the leadership briefing's behaviour table summarises.
