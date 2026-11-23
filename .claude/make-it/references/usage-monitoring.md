# Claude Code's Usage Reporting: a Guide for Administrators

How an organization switches on Claude Code's own usage reporting (OpenTelemetry) for everyone, what
it sends and what it doesn't, and what it can and can't tell you about make-it.

**make-it itself sends nothing.** There is no telemetry script in make-it, no usage record and no
new destination. The reporting below is a feature of Claude Code that your organization switches
on, and it goes only to a collector your organization runs.

**How this guide was checked.** Every statement about Claude Code was checked against Claude
Code's documentation on 22 November 2026: [Monitoring](https://code.claude.com/docs/en/monitoring-usage),
[Deploy managed settings](https://code.claude.com/docs/en/managed-settings),
[Server-managed settings](https://code.claude.com/docs/en/server-managed-settings),
[Settings](https://code.claude.com/docs/en/settings) and the pages they link. A statement the
documentation doesn't cover says "not checked against the documentation". Where a feature needs a
recent Claude Code, the version is named. Nothing here was switched on to write it.

## 1. Switching it on

Put this in managed settings. Replace `<collector-host>` and `<ingest-token>` with your own.

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://<collector-host>:4318",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer <ingest-token>",
    "OTEL_METRICS_INCLUDE_REPOSITORY": "true",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_LOG_USER_PROMPTS": "0",
    "OTEL_LOG_ASSISTANT_RESPONSES": "0",
    "OTEL_LOG_TOOL_DETAILS": "0",
    "OTEL_LOG_TOOL_CONTENT": "0"
  }
}
```

What each part does:

- `CLAUDE_CODE_ENABLE_TELEMETRY` turns the reporting on. The two `..._EXPORTER` lines send
  metrics (counts, cost, tokens) and events (one record per prompt, tool run or API call).
- Protocol: `grpc`, `http/protobuf` or `http/json`. Use the one your collector listens on. For a
  gRPC collector, set `grpc` and its gRPC address.
- `OTEL_EXPORTER_OTLP_HEADERS` carries the collector token. Section 7 says how to treat it.
- `OTEL_METRICS_INCLUDE_REPOSITORY` adds the repository's identity (`vcs.*`, taken from its
  `origin` remote) to every metric and event. Needs Claude Code v2.1.269 or later.
- `OTEL_METRICS_INCLUDE_VERSION` adds the Claude Code version (`app.version`).
- The four content flags are set to `"0"`. Each is off by default, and the documentation lists `1`
  as the value that turns it on. Setting them in managed settings means nobody can turn them on
  from their own settings or shell: a managed value wins over the same variable in a person's
  files or exported in their shell. The documentation names two exceptions: variables Claude
  Desktop sets itself when it starts a session, and anyone with administrator rights on the machine,
  who can edit the managed source. The documentation says `0` keeps replies redacted
  (`OTEL_LOG_ASSISTANT_RESPONSES`); that `0` reads as off for the other three is not checked
  against the documentation.
- `OTEL_LOG_RAW_API_BODIES` stays unset. It sends whole conversations.

Managed settings also lock where the data goes. When managed settings set the endpoint, protocol
or headers, Claude Code removes conflicting per-signal endpoints a person sets, so nobody can
point one signal at another collector (Claude Code v2.1.217 or later). The exporter lines follow
ordinary precedence, so set them in managed settings too, as above.

A repository's own `.claude/settings.json` can't turn the reporting on, change where it goes, or
capture content: Claude Code ignores those variables there.

## 2. Check the file before rollout

A managed settings file, MDM plist or registry value that isn't a JSON object stops Claude Code
from starting, on every machine it reaches, even when another managed source is valid. An entry
that is valid JSON but wrong for the schema is dropped with a warning instead. So check the file
before it goes anywhere.

make-it ships a small script that checks the file and renders the two forms MDM tools need. It
reads one file, writes two, changes nothing on the computer and sends nothing:

```bash
python3 -I "$HOME/.claude/make-it/scripts/render-managed-settings.py" managed-settings.json --out ./rendered
```

It refuses, naming the key and never the value:

- a file that isn't well-formed JSON, isn't an object, gives a key twice, or holds `null`;
- a placeholder left unfilled, such as `<collector-host>`;
- a content flag switched on (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES`,
  `OTEL_LOG_TOOL_DETAILS` or `OTEL_LOG_TOOL_CONTENT` other than `"0"`, or
  `OTEL_LOG_RAW_API_BODIES` set at all), unless you pass `--allow-content-flags`.

It writes `com.anthropic.claudecode.plist` and `ClaudeCode-Settings.reg`, readable by their
owner only, because they hold the token. On a Mac, `plutil -lint` the plist before you upload it.
The script does not check that each key is a real Claude Code setting: `claude doctor` on a test
machine does that (section 3).

## 3. Delivering it, and confirming it arrived

Pick the route that matches how you already manage machines. The keys are the same in each.

| Route | Where it goes |
|---|---|
| MDM profile (macOS) | The `com.anthropic.claudecode` managed preferences domain. Top-level keys as in the JSON, nested settings as dictionaries. The rendered plist is that payload. |
| Windows registry | The JSON as a `REG_SZ` value named `Settings` under `HKLM\SOFTWARE\Policies\ClaudeCode`. The rendered `.reg` file sets it. |
| File | `managed-settings.json` in `/Library/Application Support/ClaudeCode/` (macOS), `/etc/claude-code/` (Linux and WSL) or `C:\Program Files\ClaudeCode\` (Windows). A drop-in such as `managed-settings.d/10-telemetry.json` keeps this part separate from the rest of your policy. |

MDM and registry policies are read at startup and checked every 30 minutes. Files are read at
startup and reloaded when they change.

When several managed sources reach one machine, Claude Code by default uses the highest-ranked one
and ignores the rest: server-managed settings, then MDM or registry, then files.

Server-managed settings (the claude.ai admin console) can carry the same `env` block. They reach
only people signed in to your Team or Enterprise organization, never a third-party provider
(section 6), and a server-managed `env` variable or hook waits for each person to accept an
approval dialog.

**Confirm it on one test machine before the fleet:**

1. Run `/status` in Claude Code. The `Setting sources` line shows `Enterprise managed settings`
   with the route in brackets: `(plist)`, `(HKLM)`, `(file)`, `(drop-ins)` or `(remote)`. If a
   `Skipped sources` line names yours, a higher-ranked source won.
2. Run `claude doctor`. It lists every entry Claude Code dropped, with its source and field.
3. In your collector, look for the `claude_code.session.count` metric, which arrives when a
   session starts, or a `claude_code.user_prompt` event after one prompt.

If nothing arrives, start Claude Code with `claude --debug-file <path>` and look for
`[3P telemetry]` errors in that file.

## 4. What is sent and what is not

By default, Claude Code does not send what people type, Claude's replies, the commands Claude runs,
the contents of files, or tool inputs such as file paths. What it does send goes to the collector
you configure, not to Anthropic.

| Sent (with the settings in section 1) | Not sent |
|---|---|
| Who: `user.email` when signed in with a Claude account, account and organization IDs, an anonymous install ID (`user.id`), a session ID | The text of prompts: only their length |
| The repository: URL, owner and name (`vcs.*`) | Claude's replies: only their length |
| Counts: sessions, lines added and removed, commits and pull requests Claude Code made, active time, accepted and rejected edits with the file's language | Bash commands, file paths, URLs and other tool inputs |
| Cost in US dollars and tokens, by model | File contents, code and tool output |
| Per tool run: the tool's name, success, duration, and input and output sizes | Whole API requests and responses |
| The skill, agent and plugin active for each request, with some names replaced (section 5) | The machine's name and ID (they are sent only if you turn on `OTEL_RESOURCE_INCLUDE_HOST`, section 6) |
| Plugins loaded at startup, MCP connections, logins and logouts, permission-mode changes, which managed source applied | Full error messages from failed tools |
| Claude Code version, operating system, CPU type, terminal type | |
| In Claude Desktop, the workspace folders a person picked (`workspace.host_paths`) | |

Claude Code also sends Anthropic its own operational telemetry, separately from this. The
[data usage](https://code.claude.com/docs/en/data-usage#telemetry-services) page describes it, and
the [managed settings](https://code.claude.com/docs/en/managed-settings#turn-telemetry-off-for-your-organization)
page shows how to turn it off.

## 5. What it tells you about make-it

**Activity in the repositories make-it built.** Every metric and event carries the repository's
`vcs.*` identity. Join that with a list of the repositories make-it built (section 11) and you
have cost, tokens, sessions, commits and pull requests per make-it repository, and the same for
repositories that use Claude Code without make-it.

**Who has make-it, when it is installed as a plugin.** A `plugin_loaded` event is sent once per
enabled plugin at the start of every session. For a plugin outside Anthropic's official
marketplace its name is replaced with `third-party`, but it carries a `plugin_id_hash`: a fixed
hash of the plugin's name and marketplace, the same on every machine. Calibrate it once (below),
then count sessions by hash without collecting any names.

This applies only when people get make-it as a plugin, such as the `make-it-desktop` plugin for
Claude Desktop or a plugin your organization packages. make-it's standard installer copies its
skills into `~/.claude/commands/`. That is not a plugin, so it sends no `plugin_loaded` event
(not checked against the documentation: it follows from the event being sent per plugin).

**Which skill ran.** The skill event does not tell you which make-it skill ran. For skills a
person adds themselves, `skill_activated` reports `custom_skill`, and for plugins outside the
official marketplace the name is replaced too. The only setting that names them,
`OTEL_LOG_TOOL_DETAILS`, also sends every Bash command, file path and tool input, so don't use it
to count skills.

One thing to know: the documentation says the cost and token counters, and the `api_request`
event, carry the active skill's name as it is for "user-defined" skills, and replace it with
`third-party` only for third-party plugin skills. If that holds for make-it's commands, those
counters already show cost and tokens per make-it skill, by person. Not checked against a running
make-it install. Tell your people about it either way (section 10).

The dependable per-skill count is make-it's own ledger in each repository (section 11).

### Calibrating `plugin_id_hash`, once

Do this one time, in one shell, on your own machine, before the managed policy reaches it (a
managed value replaces the same variable from your shell, so on a managed machine these settings
would be overridden). The console exporter prints to that terminal instead of sending to a
collector (where it prints is not checked against the documentation).

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=none OTEL_LOGS_EXPORTER=console OTEL_LOG_TOOL_DETAILS=1 claude
```

The variables apply to that one command only. When Claude Code opens, type `/exit` straight away
and run nothing. The shell will print one `claude_code.plugin_loaded` event for each enabled
plugin, with `plugin.name`, `marketplace.name` and `plugin_id_hash`, plus your own `user.email`
and account IDs. Write down the hash next to make-it's name. Anything you did in that session
would also print the commands and file paths it touched, which is why you quit first. That is the
only place this guide uses `OTEL_LOG_TOOL_DETAILS`: one shell, one time. Exactly how the console
exporter lays out its output is not checked against the documentation.

## 6. Third-party providers

On Amazon Bedrock, Google Cloud's Agent Platform or Microsoft Foundry, Claude Code skips
server-managed settings, and its events carry no `user.email`: only the anonymous `user.id` and
the `session.id`.

So on those providers, deliver the settings by MDM, registry or file (section 3), and add an
identity yourself. Two ways:

1. **Name the person.** Add `OTEL_RESOURCE_ATTRIBUTES` to the `env` block, for example
   `"OTEL_RESOURCE_ATTRIBUTES": "enduser.id=<the person's email>"`. The documentation suggests
   setting it per person through the managed settings or a launch wrapper. Most MDM tools can fill
   a per-user variable into a profile; that is a feature of your MDM tool, not checked against
   Claude Code's documentation, so check your tool's own documentation. The value can't contain
   spaces, commas, semicolons, double quotes or backslashes.
2. **Name the machine, and join it with your device inventory.** Set
   `"OTEL_RESOURCE_INCLUDE_HOST": "1"` (Claude Code v2.1.326 or later). Metrics, events and traces
   then carry `host.name` and `host.id` (the operating system's machine ID, not hashed) in the
   resource block. A host name often contains a person's name and the machine ID is a lasting
   identifier, and Claude Code shows people no notice, so tell them (section 10). Leave
   `console` out of the exporter lines, or these attributes don't reach your other exporters.

The same is true of a direct API key: no Claude account, so only `user.id` and `session.id`. The
exception is a self-hosted Claude apps gateway: sessions signed in to it carry the person's
identity from your identity provider, and the gateway can deliver managed settings.

## 7. The token and the collector's certificate

**The token can be read on every managed machine.** `env` values are plain text in the settings
file, and Claude Code has to be able to read the file as the person running it (a file the
operating system won't let them read is skipped). So treat the token as known to everyone:

- Make it an ingest-only token: it can send to the collector and do nothing else.
- Rotate it on a schedule, and whenever a machine leaves your control.
- For tokens that change often, the `otelHeadersHelper` setting runs a command of yours to make
  the headers, by default every 29 minutes (HTTP protocols only).
- The stronger tier is mTLS: a client certificate on each machine, so one machine can be cut off
  without touching the others. For `http/protobuf` and `http/json`, set `CLAUDE_CODE_CLIENT_CERT`
  and `CLAUDE_CODE_CLIENT_KEY`; for `grpc`, `OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE` and
  `OTEL_EXPORTER_OTLP_CLIENT_KEY`.

Claude Code doesn't pass `OTEL_*` variables to the commands it runs, so the token is not handed to
Bash commands, hooks or MCP servers.

**A collector certificate from an internal CA.** Claude Code trusts the operating system's
certificate store by default (the native installer always; an npm install needs Node 22.15 or
later). If your internal CA is not there, point `NODE_EXTRA_CA_CERTS` at it for the HTTP
protocols, or set `OTEL_EXPORTER_OTLP_CERTIFICATE` for `grpc`. Restart Claude Code after a
certificate changes: the exporters keep the one they loaded first. Whether the terminal reads
`NODE_EXTRA_CA_CERTS` from the managed `env` block is not checked against the documentation (it
says Claude Desktop sessions do); if in doubt, set it in the machine's environment.

## 8. The seal's Stop hook in the same file

The hook that keeps make-it's seal current ([`watermark.md`](watermark.md) section 4) can go in
the same managed settings file, next to the `env` block. Managed hooks can't be removed or
switched off from a person's own settings.

```json
{
  "env": { "CLAUDE_CODE_ENABLE_TELEMETRY": "1" },
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
                     "command": "python3 -I \"$HOME/.claude/make-it/scripts/watermark.py\" hook",
                     "timeout": 10 } ] }
    ]
  }
}
```

Shortened here: keep the whole `env` block from section 1. The render script checks the combined
file the same way.

## 9. Is it worth it?

The reporting gives you cost and activity: what is spent, by whom, on which repositories, and how
much Claude Code did (sessions, lines, commits, pull requests, active time).

Tracking alone does not prove value. Proving value, like time saved, needs a before-and-after
measurement.

Pick the outcome first (for example time from ticket to merged change, or defects found after
release), measure it before the rollout, and measure it again after. The reporting tells you what
it cost to get there. The documentation links an
[ROI measurement guide](https://github.com/anthropics/claude-code-monitoring-guide) with ready-made
setups.

## 10. A notice for your people

Tell people this is on. The documentation says Claude Code shows them no notice when you add the
machine's name and ID, and it describes no notice for the rest. Publish something like this, and
fill in the placeholders:

> **What we record when you use Claude Code**
>
> `<organization>` has switched on Claude Code's own usage reporting on company computers. This
> reporting goes only to our own collector at `<collector-host>`.
>
> It records: that you used Claude Code, when and for how long; your work email or another identity
> we add; which repository you worked in; the model, the tokens used and what they cost; counts of
> lines changed, commits and pull requests made; the names of tools, skills and plugins in use (some
> names are replaced); and your Claude Code version and operating system.
>
> It does not record what you type, Claude's replies, your code or files, or the commands Claude runs.
>
> make-it itself sends nothing.
>
> We use this to see cost and adoption, not to read your work. Questions: `<contact>`.

If you turn on `OTEL_RESOURCE_INCLUDE_HOST`, add "the name and ID of your computer" to the list.

## 11. Counting adoption across your repositories

*To come.* make-it's adoption scan, `.claude/make-it/scripts/adoption-scan.py`, is described here
once it ships. Per-skill counts come from make-it's ledger in each repository, not from the usage
reporting.
