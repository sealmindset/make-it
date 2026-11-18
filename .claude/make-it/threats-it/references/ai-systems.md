# The organisation's AI systems as a target

An AI assistant or agent the organisation runs is an identity with standing access that takes instructions
from what it reads. An attacker who can put text where it reads (an email, a shared document, a web page, a
ticket, a pull request) may not need a credential at all: the agent already has one. So AI systems are
inventoried like any other privileged identity, and chained like any other finding.

Runs in every `/threats-it chains` run, and in a threat-feed run when the threat names an AI system, an agent,
a model endpoint, a plugin, a skill or an MCP server.

## 1. Inventory (read-only)

`exposure.py <outdir> <project>/presence-ai.json`, starting from `templates/presence-ai.json` (copy it into the
project and add the organisation's own AI product names). It finds enterprise apps whose name matches, Azure
AI resources by type, and their sign-ins. A name match is a name hint, the weakest rung of the presence
ladder (`tenant-assessment.md`): confirm each from its permissions, resources or sign-ins before reporting it.

One row per AI system:
| Question | Where the answer comes from |
|---|---|
| What is it, and who owns it? | app registration owner, resource tags, the profile |
| What does it run as? | its service principal, a managed identity, or each user's own access |
| What can it read and change? | `exposure.py`: Graph permissions, directory roles, group-held roles; Azure role assignments |
| What does it read that outsiders can write? | its connectors and data sources: mail, shared files, web, tickets, repositories |
| What can it do with nobody approving? | its tools and actions: send, post, write, run, merge, pay |
| Where are its actions logged, and does a rule watch them? | workspace tables, `sentinel_coverage.py` |

What this run cannot see, it says: agents built in a low-code studio (the platform's admin holds the list),
assistants and coding agents on people's machines with their plugins, skills and MCP servers (the endpoint
team), AI features inside third-party services (each service's admin). "Not visible" is not "none".

## 2. Findings to look for

Each goes into the finding-chains inventory (`finding-chains.md`) with its evidence. Most are rated low, or
not rated at all, by the tools that report them.
- An agent identity that can do more than its task needs, above all the takeover permissions `exposure.py` lists.
- An agent that reads content outsiders can write **and** holds private data **and** can send or change
  something. Any two are ordinary; all three is a path with one link.
- A shared or long-lived key for a model endpoint; an AI resource reachable from any network.
- An agent whose actions are not logged, or are logged where no rule looks.
- Plugins, skills, connectors or MCP servers from a publisher nobody vetted, or that update themselves.
- An agent that can approve its own action, or a system that acts on AI output with no check (code merged,
  a ticket closed, a payment released).
- An AI system nobody owns.

## 3. Chains through an AI system

Same format as every chain (`attack-chains.md`): diagram, stage table, "who can do this now", the window. Three
patterns to reuse (`attack-chains.md`, section 3). Map stages to MITRE ATLAS as well as ATT&CK where a technique
is specific to AI: verify each ATLAS id and name on atlas.mitre.org and archive the page; never cite one from memory.

For "Would we be alerted?", the signal is rarely the instruction itself. It is what the agent then does: a read
it has never made, mail to a new outside address, a permission it grants, a burst of calls.

## 4. What this step never does

- It never sends a prompt to the organisation's AI systems, never plants content for one to read, and never
  uses one of them to look around. Each of those is a test: it goes in the test plan, for people, with written
  authorisation (`finding-chains.md`, section 4).
- It never reports a prompt or a payload that would work. It names the weakness and the fix.
- It never calls an AI system vulnerable because of what such systems can do in general. A finding is about this
  system's access, inputs, actions and logging, each in evidence.

## 5. Where it goes

- `technical.md` Part A, S11: the inventory table, the findings, the chains, and what could not be seen.
- `briefing.md`: one table, `AI system | Runs as | Can reach | Reads what outsiders can write? | Acts with nobody
  approving? | Logged and watched?`, and the count of AI systems with all three of: private data, outside
  content, a way to act.
