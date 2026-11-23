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
    "OTEL_LOG_TOOL_CONTENT": "0",
    "OTEL_LOG_RAW_API_BODIES": "0"
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
- The five content flags are set to `"0"`. Each is off by default; the documentation names `0` as
  an off value for each of them. Setting them in managed settings stops people turning them on in
  their own settings files or shell: a managed value wins over the same variable there. Left
  unset, a person could turn one on in their shell or user settings, and the content would go to
  your collector. `OTEL_LOG_RAW_API_BODIES` matters most: it sends whole conversations.
- The limits of that lock, as the documentation gives them:
  - When the Claude Desktop app or a self-hosted environment runner starts a session, the launch
    environment it builds wins over settings files, and Desktop lets people save their own
    variables in it.
  - Server-managed settings alone are not enough. The documentation's security table: "User
    configures a third-party model provider: Server-managed settings are bypassed. This includes
    setting `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_MANTLE`, `CLAUDE_CODE_USE_VERTEX`,
    `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_USE_ANTHROPIC_AWS`, or a non-default
    `ANTHROPIC_BASE_URL`." Deliver the block by MDM, registry or file too.
  - The telemetry variables travel as one unit across managed sources: if a higher source sets
    any of them, every one from lower sources is dropped, content-flag locks included. Keep the
    whole block, content flags included, in one managed source.
  - Anyone with administrator rights on the machine can edit the managed source itself.

Managed settings also lock where the data goes (Claude Code v2.1.217 or later). A managed endpoint
or token removes the per-signal endpoints a person sets, so nobody can point one signal at another
collector; a managed protocol removes the per-signal protocols. The exporter lines follow ordinary
precedence, so set them in managed settings too, as above.

A repository's own `.claude/settings.json` can't turn the reporting on, change where it goes, or
capture content: Claude Code ignores those variables there (v2.1.282 or later). It can still
switch a signal off with an exporter line set to `none`, unless managed settings set that line.

## 2. Check the file before rollout

A managed settings file, MDM plist or HKLM registry value that isn't a JSON object stops Claude
Code from starting, on every machine it reaches, even when another managed source is valid. An
entry that is valid JSON but wrong for the schema is usually dropped with a warning instead (a few
keys fail closed). So check the file
before it goes anywhere.

make-it ships a small script that checks the file and renders the two forms MDM tools need. It
reads one file, writes two, changes nothing on the computer and sends nothing:

```bash
python3 -I "$HOME/.claude/make-it/scripts/render-managed-settings.py" managed-settings.json --out ./rendered
```

It refuses, naming the key and never the value:

- a file that isn't well-formed JSON, isn't an object, gives a key twice, or holds `null`;
- a placeholder left unfilled: anything in angle brackets, such as `<collector-host>` or
  `<the person's email>` (so a value that holds `<` and later `>` is refused too);
- a content flag switched on (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES`,
  `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT` or `OTEL_LOG_RAW_API_BODIES` present with any
  value but `"0"`, including `""` and `"false"`), unless you pass `--allow-content-flags`;
- an `--out` folder, or a file it would write, that is a symlink.

It writes `com.anthropic.claudecode.plist` and `ClaudeCode-Settings.reg` as new files readable by
their owner only, because they hold the token (an old file of the same name is replaced, not
reused). On a Mac, `plutil -lint` the plist before you upload it.
Neither the script nor `claude doctor` catches a misspelled variable name inside `env`:
`claude doctor` lists entries that fail the settings schema, and `env` accepts any name (an
inference from the schema, not checked against the documentation). Compare the names with
section 1 by eye.

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
and ignores the rest: server-managed settings, then MDM or registry, then files. The `env` block is
the exception (v2.1.223 or later): it merges per variable, so a lower source can still add a
variable such as `OTEL_RESOURCE_ATTRIBUTES`. The telemetry variables (`OTEL_EXPORTER_OTLP_*`,
`OTEL_LOG_*`, `OTEL_LOGS_EXPORTER`) travel as one unit from the highest source that sets any of
them, so an endpoint from one source never pairs with a token from another.

Server-managed settings (the claude.ai admin console) can carry the same `env` block. They reach
only sessions signed in to your claude.ai organization. They never reach a third-party provider
(section 6), a session with a non-default `ANTHROPIC_BASE_URL`, or a Claude Console API key.
In an interactive session, a server-managed `OTEL_EXPORTER_OTLP_ENDPOINT`, like a hook, waits
until the person accepts an approval dialog that names it.

**Confirm it on one test machine before the fleet:**

1. Run `/status` in Claude Code. The `Setting sources` line shows `Enterprise managed settings`
   with the route in brackets: `(plist)`, `(HKLM)`, `(file)`, `(drop-ins)` or `(remote)`. If a
   `Skipped sources` line names yours, a higher-ranked source won (that line needs v2.1.242 or
   later).
2. Run `claude doctor`. It lists each invalid entry Claude Code dropped, with its source and
   field.
3. In your collector, look for the `claude_code.session.count` metric, which arrives when a
   session starts, or a `claude_code.user_prompt` event after one prompt.

If nothing arrives, start Claude Code with `claude --debug-file <path>` and look for
`[3P telemetry]` errors in that file.

## 4. What is sent and what is not

By default, Claude Code does not send what people type, Claude's replies, the commands Claude runs,
the contents of files, or tool inputs such as file paths. What it does send goes to the collector
you configure, not to Anthropic.

Sent by default, with the settings in section 1. "Observed" means observed with the console
exporter on Claude Code v2.1.330, with every content flag off; everything else is from the
documentation.

| What | Where it comes from |
|---|---|
| Who: `user.email` (when signed in with a Claude account), `user.account_uuid`, `user.account_id`, `organization.id`, an anonymous install ID (`user.id`), `session.id` | every record |
| `anthropic.plan` (the Claude plan), `anthropic.provider`, `anthropic.custom_base_url` | every record; observed, not in the documentation |
| The repository: URL, owner and name (`vcs.*`) | every record (`OTEL_METRICS_INCLUDE_REPOSITORY`) |
| Claude Code version, operating system and version, CPU type, terminal type | every record and the resource block |
| In Claude Desktop, the workspace folders a person picked (`workspace.host_paths`) | events |
| Sessions, lines added and removed, commits and pull requests Claude Code made, active time, accepted and rejected edits with the file's language | metrics |
| Cost in US dollars and tokens, by model, with the effort level, fast mode and the subsystem that made the request (`query_source`) | `cost.usage`, `token.usage`, `api_request` |
| The skill, agent, plugin and MCP server and tool behind each request. Skills a person installs themselves are named as they are; third-party plugin skills read `third-party`; built-in, claude.ai-proxied and official-registry MCP names are named, others read `custom` | `cost.usage`, `token.usage`, `api_request`, `api_error`, `api_refusal` |
| A prompt's length and its `prompt.id`; a reply's length; the command used, collapsed to `custom` for commands a person adds | `user_prompt`, `assistant_response` |
| Each tool decision: the tool's name, allowed or refused, by what (settings, a hook, the person, the permission mode, the auto-mode classifier) | `tool_decision` |
| Each tool run: the tool's name, success, duration, error type, input and output sizes | `tool_result` |
| Error messages from failed requests, and when retries ran out | `api_error`, `api_retries_exhausted` |
| When Claude declined a request (whether it carried a reason category, not the category itself) | `api_refusal` |
| `@`-mentions in a prompt: their type and whether they resolved | `at_mention` |
| Hooks: each configured hook's event, type and source at start-up; per run, the hook name with its matcher, counts and output sizes | `hook_registered`, `hook_execution_start`, `hook_execution_complete` |
| Plugins enabled at start-up, plugin installs, MCP connections, logins and logouts, permission-mode changes | `plugin_loaded`, `plugin_installed`, `mcp_server_connection`, `auth`, `permission_mode_changed` |
| Compaction (with an error message if it failed), finished subagents (type, tokens, tool count, duration, model), Claude Code's internal error names | `compaction`, `subagent_completed`, `internal_error` |
| Which managed source applied (and a policy helper's path, if you use one); clean-up runs of old transcripts (counts only) | `managed_settings_resolved`, `retention_sweep` |
| A person's answer to a session quality survey, when they give one | `feedback_survey` |

Not sent with the settings in section 1:

| Not sent | How it would be |
|---|---|
| The text of prompts (observed: `<REDACTED>` with its length) and of Claude's replies | `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES` |
| Bash commands, file paths, URLs, search patterns and other tool inputs; full tool error messages; hook matchers at start-up | `OTEL_LOG_TOOL_DETAILS` |
| File contents, code and tool output | `OTEL_LOG_TOOL_CONTENT` (with tracing), `OTEL_LOG_RAW_API_BODIES` |
| Whole API requests and responses | `OTEL_LOG_RAW_API_BODIES` |
| The machine's name and ID (observed: absent) | `OTEL_RESOURCE_INCLUDE_HOST` (section 6) |

The documentation also lists a `safety_event` (why a tool call was refused, which rule, sandbox
refusals). It says Claude Code v2.1.312 and later no longer send it.

Claude Code also sends Anthropic its own operational telemetry, separately from this. The
[data usage](https://code.claude.com/docs/en/data-usage#telemetry-services) page describes it, and
the [managed settings](https://code.claude.com/docs/en/managed-settings#turn-telemetry-off-for-your-organization)
page shows how to turn its usage metrics off (`DISABLE_TELEMETRY`); error reports have their own
switch, `DISABLE_ERROR_REPORTING`. Turning usage metrics off also stops the analytics dashboard
and feature-flag fetching for those people.

## 5. What it tells you about make-it

**Which make-it skill ran.** Which make-it skill ran, and what it cost, is sent by default. The
cost and token counters and the `api_request` event carry the name of the skill active for each
request, and for skills a person installs themselves the name is sent as it is (the documentation:
"Built-in, bundled, user-defined, and official-marketplace plugin skill names appear verbatim").
make-it's standard installer copies its skills into `~/.claude/commands/`, so a make-it command
such as `/resume-it` arrives as `skill.name: "resume-it"`, with the person's identity, the model,
the tokens and the cost. This was observed with the console exporter on Claude Code v2.1.330, with
every content flag off: a make-it command's real name was on every cost and token point and on
both `api_request` events.

The `skill_activated` event does not name it: it reports `custom_skill`. (Observed the same run:
`skill.source: "userSettings"`, and the prompt event's `command_name` was `custom`.) For a make-it
plugin from outside the official marketplace, such as the `make-it-desktop` plugin, the counters
show `third-party` instead.

A skill name is not proof of make-it: anyone's own command with the same name looks the same. Read
it as a count of commands by that name. You don't need `OTEL_LOG_TOOL_DETAILS` for any of this;
leave it off.

**Who has make-it switched on.** Three partial answers:

- **The skill names on the cost counters**: a person shows up once they run a make-it command, and
  a name can collide with someone's own command.
- **`plugin_id_hash`**, for plugin installs only. A `plugin_loaded` event is sent once per enabled
  plugin at the start of every session. For a plugin outside Anthropic's official marketplace the
  name reads `third-party`, but it carries a `plugin_id_hash`: a fixed hash of the plugin's name
  and marketplace, the same for the same plugin from the same marketplace on every machine.
  Calibrate it once (below). A plugin synced from claude.ai is hashed with the marketplace name
  claude.ai reports, or `synced`, so calibrate on a machine that gets make-it the way your people
  do (before v2.1.246 the synced hash was computed differently). The standard install is not a
  plugin: in the v2.1.330 run, 15 `plugin_loaded` events arrived and none was make-it.
- **The repositories**: which ones carry make-it's records (section 11).

**Activity in the repositories make-it built.** Every metric and event carries the repository's
`vcs.*` identity. Join that with the list of repositories that carry make-it's records and you have
cost, tokens, sessions, commits and pull requests per make-it repository, and the same for
repositories that use Claude Code without make-it.

### Calibrating `plugin_id_hash`, once

Only if people get make-it as a plugin. Do this one time, in one shell, on your own machine, before
the managed policy reaches it (a managed value replaces the same variable from your shell, so on a
managed machine these settings would be overridden). It sends nothing to a collector: in `-p` mode
the console exporter writes every record to standard output (observed on v2.1.330), which this
command puts in a file:

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=none OTEL_LOGS_EXPORTER=console OTEL_LOG_TOOL_DETAILS=1 OTEL_LOG_USER_PROMPTS=0 claude -p "Reply with OK and nothing else." > plugin-hashes.txt
```

The variables apply to that one command only. It makes one small request and runs no tools. The
file will hold one `claude_code.plugin_loaded` record for each enabled plugin, with `plugin.name`,
`marketplace.name` and `plugin_id_hash`, plus your own `user.email`, account IDs and plan. Write
down the hash next to make-it's name, then delete the file. A prompt that ran tools would also
print its commands and file paths, which is why the prompt asks for nothing. That is the only place
this guide uses `OTEL_LOG_TOOL_DETAILS`: one shell, one time. The interactive form (`claude`, then
`/exit`) is not checked.

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
  without touching the others. For `grpc`, set `OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE` and
  `OTEL_EXPORTER_OTLP_CLIENT_KEY`. For `http/protobuf` and `http/json`, set
  `CLAUDE_CODE_CLIENT_CERT` and `CLAUDE_CODE_CLIENT_KEY`; these are Claude Code's general mTLS
  settings, so the same certificate is also presented on its other connections. Restart Claude
  Code after rotating the client certificate: the exporters keep the one they loaded first.

Claude Code doesn't pass `OTEL_*` variables to the commands it runs, so the token is not handed to
Bash commands, hooks or MCP servers.

**A collector certificate from an internal CA.** Claude Code trusts the operating system's
certificate store by default (the native installer always; an npm install needs Node 22.15 or
later). That the OTLP HTTP exporters use it too is inferred from that general statement, not
stated for them. If your internal CA is not there, point `NODE_EXTRA_CA_CERTS` at it for the HTTP
protocols, or set `OTEL_EXPORTER_OTLP_CERTIFICATE` for `grpc`. The documentation treats
`NODE_EXTRA_CA_CERTS` as a variable managed settings can deliver in `env`.

**Cowork is separate.** The OpenTelemetry form under Monitoring in the admin console's data and
privacy settings applies to Cowork sessions only; neither the terminal nor the Desktop app's Code
tab exports to a collector set there. These managed settings cover the terminal and the Code tab.

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
it cost to get there. Cost per make-it command is visible too (section 5); that is still cost and
activity, not value. The documentation links an
[ROI measurement guide](https://github.com/anthropics/claude-code-monitoring-guide) with ready-made
setups.

## 10. A notice for your people

Tell people this is on. The documentation says Claude Code shows them no notice when you add the
machine's name and ID, and it describes no notice for the rest. Publish something like this, and
fill in the placeholders. The notice is the summary; the table under it is the full list to link
to.

> **What we record when you use Claude Code**
>
> `<organization>` has switched on Claude Code's own usage reporting on company computers. This
> reporting goes only to our own collector at `<collector-host>`, and only `<who can see it>` can
> read it.
>
> It records: that you used Claude Code, when and for how long; your work email, your account and
> organization IDs, your Claude plan, or another identity we add; which repository you worked in;
> the model, the tokens used and what they cost, including the name of each make-it command or
> other skill you run, such as `/resume-it`, with its cost; the names of tools Claude used and
> whether each was allowed or refused, and by what; the names of some connected services whose
> results Claude used; which plugins you have enabled; when Claude declined a request; counts of
> lines changed, commits and pull requests; error messages from failed requests; in Claude
> Desktop, the folders you opened; and your Claude Code version, operating system and terminal.
>
> It does not record what you type, Claude's replies, your code or files, or the commands Claude runs.
> Nor does it record the paths of the files Claude reads or edits. We have set Claude Code so that
> this content stays off.
>
> make-it adds no reporting of its own, but its commands run inside Claude Code, so the name of each make-it command you run is recorded with its cost.
>
> We use this to see cost and adoption, not to read your work. The full list:
> `<link to the table>`. Questions: `<contact>`.

If you turn on `OTEL_RESOURCE_INCLUDE_HOST`, add "the name and ID of your computer" to it.

**The full list** (the rows of section 4, in plain words; "observed" means observed with the
console exporter on Claude Code v2.1.330, with every content flag off):

| Recorded about you | Source |
|---|---|
| That you used Claude Code, each session, and your active time | `session.count`, `active_time.total` |
| Your work email, account and organization IDs, an install ID and a session ID | standard attributes |
| Your Claude plan | `anthropic.plan`: observed, not in the documentation |
| An identity we add, if we add one | `OTEL_RESOURCE_ATTRIBUTES` (section 6) |
| The repository you worked in | `vcs.*` |
| The model, the tokens, the cost, and the make-it command or other skill behind each request (observed: the command's real name) | `cost.usage`, `token.usage`, `api_request` |
| Each tool Claude used, whether it was allowed or refused, and by what | `tool_decision`, `tool_result` |
| The names of built-in, claude.ai and official-registry connected services whose results Claude used | `mcp_server.name`, `mcp_tool.name` |
| The plugins you have enabled (names outside the official marketplace replaced) | `plugin_loaded` |
| When Claude declined a request | `api_refusal` |
| Lines changed, commits and pull requests Claude Code made | metrics |
| Error messages from failed requests | `api_error`, `api_retries_exhausted`, `compaction` |
| In Claude Desktop, the folders you opened | `workspace.host_paths` |
| Your Claude Code version, operating system and terminal | resource block, `terminal.type` |
| Hooks that ran, subagents that finished, `@`-mentions, logins, permission-mode changes, survey answers | the events in section 4 |

## 11. Counting adoption across your repositories

Per-skill counts come from both: for make-it's standard install, the usage reporting shows who ran
which command (a plugin from outside the official marketplace shows `third-party`), when, and what
it cost; the ledger in each repository shows which sealing steps changed which app.
Use the reporting for cost and activity per command and per person. Use the ledger for what make-it
actually did to each app: it is committed in the repository, so it covers every machine and every
provider, and it can't collide with someone's own command of the same name.

make-it's adoption scan, which counts the repositories that carry make-it's records and reads
their ledgers, ships separately. See the scan's own reference once it is installed.
