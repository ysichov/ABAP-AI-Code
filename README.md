# ABAP AI Code

<img width="607" height="605" alt="ABAP AI Code main window" src="https://github.com/user-attachments/assets/69eef42b-99f9-43c2-b0df-2f58e92afbcd" />

**An agentic AI coding assistant that runs *inside* the SAP system.**
Written in ABAP with an HTML UI, it reads, explains, reviews and — with the optional
[write add-on](https://github.com/ysichov/ABAP-AI-CODE-TOOLS) — creates, changes and
deletes ABAP repository objects. No code export, no laptop toolchain, no ADT required.

Demos: [Z_ABAP_AI_CODE2 walkthrough](https://www.loom.com/share/00e46d9a3cc343778c86ef7f68e3407e) ·
[Combobulating](https://www.loom.com/share/75eb12e3a8394fe8a932c5573a8127f9)

---

## Table of contents

- [1. Why this exists — comparison with Claude Code / Codex](#1-why-this-exists--comparison-with-claude-code--codex)
  - [1.1 Side-by-side](#11-side-by-side)
  - [1.2 When to use which](#12-when-to-use-which)
- [2. What you get](#2-what-you-get)
- [3. Repository layout and the plugin pattern](#3-repository-layout-and-the-plugin-pattern)
- [4. Installation](#4-installation)
- [5. Configuration](#5-configuration)
  - [5.1 Providers (ZAICODE_PROVIDER)](#51-providers-zaicode_provider)
  - [5.2 API keys (Z_ABAP_AI_KEYS)](#52-api-keys-z_abap_ai_keys)
  - [5.3 Prompt / schema folder](#53-prompt--schema-folder)
- [6. First run](#6-first-run)
  - [6.1 Selection screen](#61-selection-screen)
  - [6.2 The three-pane window](#62-the-three-pane-window)
- [7. Tool catalog](#7-tool-catalog)
- [8. Writing your own tool](#8-writing-your-own-tool)
- [9. Logs and observability](#9-logs-and-observability)
- [10. Security model](#10-security-model)
- [11. Known limitations](#11-known-limitations)
- [12. Legacy AGENTS flow](#12-legacy-agents-flow)
- [13. Links, TODO, license](#13-links-todo-license)

---

## 1. Why this exists — comparison with Claude Code / Codex

Claude Code, Codex CLI and friends are excellent — *if your code is on a laptop, in Git,
and you are allowed to send it to a vendor from there*. In a lot of SAP shops none of
those three is true: the code lives only in the system, ADT/abapGit may not be installed,
and exporting sources to a developer machine is a compliance conversation nobody wants to
have.

**ABAP AI Code is that class of tool, re-implemented where the ABAP code actually is.**
You start a report in SAP GUI, type a question in your own language, and an agentic loop
(LLM → tool call → ABAP execution → result → LLM → …) works on live repository objects.

### 1.1 Side-by-side

| | **Claude Code / Codex CLI** | **ABAP AI Code** |
|---|---|---|
| Where it runs | Your laptop / a container | Inside the SAP system, SAP GUI report `Z_ABAP_AI_CODE2` |
| What it sees | Files in a Git working copy | Live repository objects (`READ REPORT`, `SEO_*`, TADIR) — always the current version |
| How it changes code | Writes files; you commit | Writes via standard SAP APIs (`RPY_*`, `SEO_*`), with syntax check, transport entry (`RS_CORR_INSERT`) and activation |
| Reviewing a change | `git diff` in a terminal | Built-in HTML diff with **per-hunk approve / decline**, decline notes and an AI discussion thread per hunk |
| Prerequisites | Node.js, Git, code exported to disk | An SAP system. Nothing else — no ADT, no Eclipse, no Git working copy |
| Auth / secrets | Vendor account or API key on the laptop | API key **AES-256 encrypted per SAP user** in `ZAICODE_APIKEY`, unlocked by a password that is never stored |
| Model choice | Vendor's own models | 8 preconfigured providers (Anthropic, OpenAI, Mistral, Gemini, Groq, Cerebras, OpenRouter, NVIDIA); model list pulled **live** from `/v1/models` |
| Extending it | MCP servers, hooks — all outside SAP | ABAP plugin classes implementing `ZIF_AI_TOOL`, discovered automatically; they run *in* the system with full ABAP API access |
| Write access | Always on | **Opt-in**: the base package is read-only; write tools ship as a [separate package](https://github.com/ysichov/ABAP-AI-CODE-TOOLS) you install only where changes are intended |
| ABAP awareness | Generic code model | ABAP-native: class/method-level reads, structure tree, McCabe + Halstead metrics, breakpoints, "run this program" |
| Data leaving the system | The whole working tree is reachable | Only what a tool explicitly sends: one object's source, one method, one diff |

### 1.2 When to use which

- **Use Claude Code / Codex** when your ABAP is already mirrored to Git and your policy
  allows a cloud agent to read that repository. The tooling around it is richer.
- **Use ABAP AI Code** when the code must not leave the system, when developers work in
  SAP GUI, when there is no abapGit mirror, or when you want AI assistance bound to SAP
  authorizations, transports and user identity.
- They are not exclusive. Nothing here prevents you from keeping an abapGit mirror and
  running both.

---

## 2. What you get

Concrete capabilities, from a user's point of view:

**Ask about code in plain language.** "What does `ZCL_X` do?", "Where is the bug in
`Z_REPORT`?", "Make me a table of the methods and what they do." Answers come back in
*your* language — the answer language follows the question language.

**Read at the right granularity.** A whole class, a single method (`ZCL_X=>METHOD`), a
program, several objects in one call (comma-separated), or everything matching a pattern
(`ZCL_AITOOL_*`). Over-broad requests ask you for confirmation instead of quietly reading
half the system.

**Get a real code review.** `review_sap_code` runs a dedicated reviewer prompt
(~15 KB of ABAP-specific review rules) against the live source and returns findings — not
a generic "looks fine to me".

**See the object, not just the text.** Answers that resolve to one object open in a real
ABAP editor pane with syntax highlighting, a structure tree (sections / attributes /
methods, or events / forms / modules), breakpoints you can set, and a "Run" button that
starts the program via its selection screen.

**Measure it.** One click gives McCabe cyclomatic complexity and full Halstead metrics
(η1/η2, volume, difficulty, effort, estimated bugs) per method and per class.

**Approve changes hunk by hunk.** When the write add-on is installed, a change never lands
silently: you get a diff, you approve or decline each hunk, you can leave a note or argue
with the AI about a specific hunk, and only then is it saved, transported and activated.

**Keep the receipts.** Every LLM request, response, thinking block, tool call and tool
result is written to a per-session log folder, plus a per-question token table and a
Claude-Code-compatible `session.jsonl`.

**Bring your own model.** Switch provider and model on the selection screen; the model
dropdown is filled from the provider's live `/v1/models`, so a new model is available the
day it ships. Anthropic extended thinking is supported with a configurable budget.

---

## 3. Repository layout and the plugin pattern

The platform is split into **two abapGit repositories** along a single line: *can it change
your code?*

| Repository | Package contents | Install it when |
|---|---|---|
| **ABAP-AI-Code** (this repo) | Engine, agentic runner, UI, diff/review cluster, metrics, crypto, key management, and the **read-only** tools (`read_sap_object`, `review_sap_code`, `show_code_example`) | Always — it is the base |
| **[ABAP-AI-CODE-TOOLS](https://github.com/ysichov/ABAP-AI-CODE-TOOLS)** | The **write** tools (`create_sap_object`, `modify_sap_object`, `delete_sap_object`) and `ZCL_CODE_OBJECT_SAVER`, which performs the actual write / delete / activate | Only on systems where AI-assisted code changes are intended |

This split is possible because **every tool is a plugin**:

```
Layer 1  <tool_name>.json   OpenAI function definition — the contract the LLM sees
Layer 2  <tool_name>.md     prompt fragment — behaviour rules for that tool
Layer 3  ZCL_AITOOL_<X>     ABAP class implementing ZIF_AI_TOOL — does the work
```

`ZCL_AI_TOOL_FACTORY` discovers implementers at runtime by querying `SEOMETAREL` for
classes that implement `ZIF_AI_TOOL` or inherit from `ZCL_AITOOL_BASE`. Both the tools
JSON array *and* the tool section of the system prompt are assembled from that same
registry, so:

- **installing** a package adds its tools to the LLM's toolset and to the prompt — no core
  code is touched;
- **not installing** it means the LLM is never told the capability exists, so it cannot
  attempt it and then fail;
- the base has **no compile-time dependency** on the write package: the runner and the UI
  call the saver purely by dynamic name (`CALL METHOD ('ZCL_CODE_OBJECT_SAVER')=>…`), and
  write paths fail gracefully with "read-only platform" when it is absent.

Registration is **fail-closed**: a tool whose `.json` or `.md` companion file is missing
from the prompt folder is *not* registered, and a message names the missing file. A
forgotten file surfaces as an explicit warning instead of a tool that silently misbehaves.

Design rationale and the full envelope specification: [FABLE_NEW_ARCHITECTURE.md](FABLE_NEW_ARCHITECTURE.md).

---

## 4. Installation

**Prerequisites**

- [abapGit](https://github.com/abapGit/abapGit) — to pull the repositories into the system.
- An API key for at least one supported provider.
- HTTPS connectivity from the SAP system to the provider, configured in **SM59**. The
  setup is described step by step in
  [this SAP Community post](https://community.sap.com/t5/abap-blog-posts/abap-code-reviewer/ba-p/14406080).

> **Note:** [AVE / ABAP Code Reviewer](https://github.com/ysichov/AVE) is **no longer a
> required dependency**. The diff/review cluster it used to provide now lives in this
> repository (`ZCL_CODE_ACR_*`, `ZCL_CODE_POPUP_DIFF`). Install AVE only if you want it as
> a standalone tool.

**Steps**

1. abapGit → *Online* → clone `https://github.com/ysichov/ABAP-AI-Code` into a Z package.
   Pull and activate.
2. *(Optional, write access)* clone `https://github.com/ysichov/ABAP-AI-CODE-TOOLS` into a
   second package. abapGit does not resolve dependencies, so **the base must be installed
   first**.
3. Copy the [`TOOLS`](TOOLS) folder of this repository to the machine that runs SAP GUI —
   e.g. `C:\soft\GITHUB\ABAP-AI-CODE\TOOLS`. These `.json` / `.md` files are read from the
   frontend at runtime; they are deliberately *not* abapGit objects, so prompts can be
   edited in a text editor without a transport.
4. If you installed the write add-on, copy its companion files (`create_sap_object.*`,
   `modify_sap_object.*`, `delete_sap_object.*`) into the **same** folder.
5. Run `Z_ABAP_AI_CODE2` once and either point `p_tools` at your folder and save a variant,
   or change the default in the program's `INITIALIZATION` block.

---

## 5. Configuration

### 5.1 Providers (ZAICODE_PROVIDER)

Providers are pure customizing — table `ZAICODE_PROVIDER`, maintainable in SM30/SE16. On
first run of `Z_ABAP_AI_KEYS` it is seeded with:

| Provider | Base URL | Wire format |
|---|---|---|
| `ANTHROPIC` | `https://api.anthropic.com/v1` | Anthropic (`ANTHROPIC` flag set) |
| `OPENAI` | `https://api.openai.com/v1` | OpenAI (`CACHEKEY` flag set) |
| `MISTRAL` | `https://api.mistral.ai/v1` | OpenAI-compatible |
| `GEMINI` | `https://generativelanguage.googleapis.com/v1beta/openai` | OpenAI-compatible |
| `GROQ` | `https://api.groq.com/openai/v1` | OpenAI-compatible |
| `CEREBRAS` | `https://api.cerebras.ai/v1` | OpenAI-compatible |
| `OPENROUTER` | `https://openrouter.ai/api/v1` | OpenAI-compatible |
| `NVIDIA` | `https://integrate.api.nvidia.com/v1` | OpenAI-compatible |

Three fields drive behaviour: `URL` (base endpoint), `ANTHROPIC` (speak the Anthropic wire
format instead of OpenAI), `CACHEKEY` (provider accepts OpenAI's `prompt_cache_key`).
**Adding any other OpenAI-compatible provider is one table row** — no code change.

### 5.2 API keys (Z_ABAP_AI_KEYS)

Run `Z_ABAP_AI_KEYS` to store a key:

- **Provider / Name** — several named keys per provider are supported (e.g. `DEFAULT`, `TEAM`).
- **Key** — the provider API key.
- **Password (twice)** — minimum 10 characters. This password is *never stored anywhere*.

The key is AES-256 encrypted into `ZAICODE_APIKEY`, with the AES key derived from the
password **and** `sy-uname`. See [Security model](#10-security-model).

### 5.3 Prompt / schema folder

`p_tools` on the selection screen points at the frontend folder holding
`<tool_name>.json` and `<tool_name>.md`. It also holds two files the runner reads directly:

- `tool_runner.md` — the orchestrator's own system prompt (routing rules: read before
  modify, delete-vs-modify, read-only vs write, answer in the user's language…). Per-tool
  fragments are appended to it by the factory.
- `delete_misuse_redirect.md` — the template used to bounce a `delete_sap_object` call back
  to `modify_sap_object` when the user only asked to remove *part* of an object.

Edit any of these in a text editor and the change takes effect on the next run. This is the
main tuning surface of the whole system.

---

## 6. First run

### 6.1 Selection screen

`Z_ABAP_AI_CODE2` opens with only the **password** visible. Enter it and press Enter — that
unlocks the rest of the screen. The staged reveal is deliberate: without the password
nothing can be decrypted, so nothing else is worth showing.

| Field | Meaning |
|---|---|
| `p_pwd` | Password for your stored key. Masked. Mandatory |
| `p_prov` | Provider. Only providers **you** have a key for are listed; a single-key user is snapped straight to theirs |
| `p_name` | Which of your named keys to use (auto-selected when you have exactly one) |
| `p_model` | Model. Filled live from the provider's `/v1/models`, refreshed only when provider / key / password changes. Defaults to a `haiku` model when available |
| `p_tools` | Frontend folder with the `.json` / `.md` tool files |
| `p_temp` | Temperature (also changeable at runtime from the toolbar) |
| `p_maxt` / `p_nomax` | Max output tokens, or no limit |
| `p_think` / `p_thbud` | Anthropic extended thinking and its token budget (hidden for other providers) |
| `p_log` | Folder for session logs |
| `p_wipe` | Clear the password from memory right after the key is decrypted. Leave on in PROD; switch off on a dev box to avoid retyping |

### 6.2 The three-pane window

- **Left — question.** A text editor for your prompt, and the toolbar: **Ask**,
  **History** (all messages of the session), **Temp** (change temperature live),
  **New session** (clear the conversation).
- **Middle — progress + structure.** A live step log: each LLM call and each tool call with
  its label, elapsed seconds and token counts (in / out / cached). Below it, the structure
  tree of the object currently open; double-click a node to jump to it in the editor.
- **Right — answer + code.** Either the rendered HTML answer, or a real ABAP editor showing
  the object. In editor mode the toolbar gains **Back** (return to the list), **Metrics**
  (McCabe + Halstead) and, for a program, **Run**. Breakpoints can be set directly.

When a tool produces a change, this pane switches to a **diff**: each hunk carries approve /
decline buttons, a note field and an AI thread so you can question a specific hunk before
deciding. Nothing is written until you approve.

Under the hood, `run()` is a bounded agentic loop — up to **8 iterations** of
*LLM → tool calls → execute → feed results back*, ending when the model answers with no
tool calls. Identical idempotent calls (the same read or review twice) are served from a
per-question cache instead of being re-executed.

---

## 7. Tool catalog

Read-only tools, shipped in **this** repository:

| Tool | Class | What it does |
|---|---|---|
| `read_sap_object` | `ZCL_AITOOL_READ` | Reads `PROG` / `CLAS` / `METH` / `FUNC` sources. Accepts `ZCL_X=>METHOD`, comma-separated lists and `ZCL_*` wildcards. Asks for confirmation above 10 objects; reports "not found" as a hard error instead of letting the model hallucinate |
| `review_sap_code` | `ZCL_AITOOL_REVIEW` | Reads the object itself and runs it through the reviewer prompt. Also the tool used for "find the bug / explain what's wrong" — diagnosis without modification |
| `show_code_example` | `ZCL_AITOOL_EXAMPLE` | Generates an ABAP example for a topic. Display only — never saved, never reviewed |

Write tools, shipped in **[ABAP-AI-CODE-TOOLS](https://github.com/ysichov/ABAP-AI-CODE-TOOLS)**:

| Tool | Class | What it does |
|---|---|---|
| `create_sap_object` | `ZCL_AITOOL_CREATE` | Creates a program or class that does not exist yet |
| `modify_sap_object` | `ZCL_AITOOL_MODIFY` | Changes an existing object — including removing a method, a FORM or comments |
| `delete_sap_object` | `ZCL_AITOOL_DELETE` | Deletes a **whole** object. Guarded: a request to remove part of an object is redirected to `modify_sap_object` |

All three route through `ZCL_CODE_OBJECT_SAVER`, which does the syntax check, the transport
entry and the activation.

---

## 8. Writing your own tool

Four steps, no core changes:

1. **Schema** — `TOOLS/my_tool.json`, a standard OpenAI function definition:

   ```json
   {
     "type": "function",
     "function": {
       "name": "my_tool",
       "description": "What it does and when the model should reach for it.",
       "parameters": {
         "type": "object",
         "properties": { "object_name": { "type": "string", "description": "…" } },
         "required": ["object_name"]
       }
     }
   }
   ```

2. **Prompt fragment** — `TOOLS/my_tool.md`, the behavioural rules appended to the system
   prompt when (and only when) this tool is installed.

3. **ABAP class** — inherit from `ZCL_AITOOL_BASE` and redefine two methods:

   ```abap
   CLASS zcl_aitool_mine DEFINITION PUBLIC INHERITING FROM zcl_aitool_base CREATE PUBLIC.
     PUBLIC SECTION.
       CONSTANTS c_tool_name TYPE string VALUE 'my_tool'.
       METHODS zif_ai_tool~get_tool_name REDEFINITION.
       METHODS zif_ai_tool~execute       REDEFINITION.
   ENDCLASS.
   ```

   `execute` receives the raw JSON arguments; `get_json_attribute( )` from the base pulls
   out a flat attribute. Fill `rs_result`: `xml_payload` (what goes back to the model),
   `error_text` on failure, and — for a tool that changes code — `save_required`,
   `object_type`, `object_name`, `original_source`, `final_source`, so the runner triggers
   the diff / approve / save flow.

4. **Activate.** The factory finds the class on the next run. Nothing to register.

Two conventions worth remembering:

- **Tool name = schema file name = md file name.** `c_tool_name` is the single binding
  point between all three layers.
- **Never call the LLM client directly.** Use `mo_context->ask( )`. It routes the sub-call
  through the runner, so it appears in the progress panel, is logged and is counted in the
  token totals. `mo_llm->ask( )` bypasses all of that and makes the tool invisible.

To disable a tool without deleting it, redefine `zif_ai_tool~is_active` to return
`abap_false`.

---

## 9. Logs and observability

With `p_log` set, each session gets its own folder `<log_path>/<date>_<time>/` containing,
per step:

| Suffix | Content |
|---|---|
| `Q` | The raw request sent to the provider (JSON) and the assembled prompt (TXT) |
| `LLM` | The raw response, plus a readable Markdown rendering |
| `THINK` | The extended-thinking block, when enabled |
| `TOOL` | Tool call arguments and results |
| `A` | The final answer |
| `SUBQ` / `SUBLLM` | Requests / responses of tool sub-agent calls |

Plus two aggregates:

- `_tokens.md` — one row per question: input / output / cached tokens.
- `claude_compatible/session.jsonl` — the same session as **Claude-Code-style JSONL**, one
  JSON object per line, so a Claude session reader ingests it directly.

The middle pane shows the same information live while the loop runs.

---

## 10. Security model

**API keys.** Stored AES-256 encrypted in `ZAICODE_APIKEY`. The AES key is derived from the
password *and* `sy-uname`:

- the password is never persisted — not in the database, not in the source. Someone reading
  the table or this repository cannot decrypt anything;
- the username is embedded in the plaintext and verified on decrypt, so a copied row cannot
  be replayed under another user;
- format **v2** (current) uses a random per-record salt and a random IV with stronger key
  stretching. Legacy v1 rows still decrypt; re-saving a key upgrades it.

**Password handling in the UI.** The cached model-list state stores a per-session salted
SHA-256 token of the password, never the password itself, so neither a debugger nor a dump
reveals it. With `p_wipe` on, the password is cleared from memory as soon as the key is
decrypted — the blast radius of a debug session shrinks to one key rather than the master
password.

**Write access.** Read-only by default. The write package is a separate installation
decision, and even where it *is* installed nothing is saved without an explicit per-hunk
approval, a syntax check and a normal transport entry.

**What leaves the system.** Only what a tool explicitly sends to the provider: the source
of the object being read, reviewed or changed, plus your prompt. There is no background
indexing and no repository-wide upload.

---

## 11. Known limitations

Stated plainly, so nothing surprises you:

- Navigation and the structure tree use **plain text search, not real ABAP parsing** — good
  enough to jump around, not a substitute for ADT.
- The agentic loop is capped at **8 iterations** per question; very large multi-object tasks
  need to be split.
- Prompt / schema files live on the **frontend**, so each developer needs a local copy (this
  is also what makes them editable without a transport).
- The UI is SAP GUI + `CL_GUI_HTML_VIEWER`; it is a desktop-SAP-GUI tool, not a Fiori app.
- There is no MCP ecosystem — extensions are ABAP classes.
- Answer quality depends heavily on the `.md` prompt files. They are meant to be tuned.
- `tool_runner.md` mentions a `web_search` tool that has **no implementation** in this
  repository; treat that line as aspirational until a plugin provides it.
- The write add-on ships `delete_sap_object.json` but **no `delete_sap_object.md`** — under
  the fail-closed rule that means `ZCL_AITOOL_DELETE` refuses to register until the prompt
  fragment is added.

---

## 12. Legacy AGENTS flow

The original implementation used string proto-tags (`{AGENT:CODE_SEARCH PROG Z_TEST}`) and
a chain of specialised agents, driven from the [`AGENTS`](AGENTS) folder
(`Object_detector.md`, `task_orchestrator.md`, `class_processor.md`, `code_review.md`,
`final.md`, …).

It still runs, in parallel with the new flow: copy the `AGENTS` folder locally and point the
legacy program's path at it. New work should use `Z_ABAP_AI_CODE2` and the `TOOLS` folder —
the reasons are laid out in [FABLE_NEW_ARCHITECTURE.md](FABLE_NEW_ARCHITECTURE.md).

---

## 13. Links, TODO, license

- **Write add-on:** https://github.com/ysichov/ABAP-AI-CODE-TOOLS
- **Architecture design doc:** [FABLE_NEW_ARCHITECTURE.md](FABLE_NEW_ARCHITECTURE.md)
- **Roadmap:** [TODO.md](TODO.md)
- **SM59 / connectivity setup:** [SAP Community — ABAP Code Reviewer](https://community.sap.com/t5/abap-blog-posts/abap-code-reviewer/ba-p/14406080)
- **Standalone code reviewer (optional):** https://github.com/ysichov/AVE
- **License:** [MIT](LICENSE)

<img width="830" height="275" alt="ABAP AI Code diff review" src="https://github.com/user-attachments/assets/6ca7cc24-a0f3-4f1d-908a-c7543e8dea0a" />
