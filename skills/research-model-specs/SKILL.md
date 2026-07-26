---
name: research-model-specs
description: Gather VERIFIED, source-cited specs for a new LLM before seeding it into the NSAI model catalog — exact API model id, context window, max output tokens, and every capability flag (vision / docs / tools / reasoning / image-gen / embeddings). Never guesses; anything not confirmed by an authoritative source is reported as UNVERIFIED, not assumed.
argument-hint: <model name or provider deployment id, e.g. "openai gpt-5.6"> [provider]
allowed-tools: WebSearch, WebFetch, Read, Grep, Glob, AskUserQuestion
---

# Research model specs (no assumptions)

Produce the exact, source-backed values needed to create a row in the NSAI `models` table
for a **new** model. The single rule of this skill: **never invent or infer a value.** Every
field is either backed by an authoritative source (with a link) or explicitly marked
`UNVERIFIED`. A wrong `name` string, context window, or capability flag silently breaks chat,
truncates output, or exposes features the model can't actually do — so accuracy beats
completeness.

The model to research is in `$ARGUMENTS` (e.g. `openai gpt-5.6`). If it's missing or ambiguous,
ask the user for the provider and the exact deployment id with `AskUserQuestion` before searching.

## Source hierarchy (trust order)

Prefer sources in this order. A value is "VERIFIED" only if it comes from tier 1 or 2.

1. **Official provider API docs / model reference** — OpenAI platform docs, Anthropic docs,
   Google AI / Vertex model docs, Mistral docs, etc. This is the ONLY source for the exact
   API model id (`name`), context window, and max output tokens.
2. **Official provider pricing / model-card / release-note pages** — for capability matrices
   (vision, function calling, reasoning) and knowledge cutoff.
3. **Provider changelog / official blog** — acceptable for capability facts, weaker for exact
   numeric limits.
4. ❌ **Third-party aggregators, blogs, Reddit, model-comparison sites** — NOT acceptable as
   the sole source for any field. May be used only to find the official page, never to fill a value.

Cross-check the model id and the two token numbers against **at least the official docs page**.
If two authoritative sources disagree, report both and mark the field `UNVERIFIED — sources conflict`.

## What to find (maps 1:1 to the catalog fields)

The catalog row is defined by `CreateModelDto`
(`apps/nsai/server/src/models/dtos/create-model.dto.ts`) and `ModelEntity`
(`apps/nsai/server/src/database/entities/model.entity.ts`). Read those first so the output
matches the real field names and the valid enum values below.

Research **only** the model-intrinsic facts (the web can answer these):

| Catalog field | What to confirm from the web | Notes |
|---|---|---|
| `name` | The **exact** provider deployment / API id string, verbatim | e.g. `gpt-5.6`, `claude-opus-4-8`. Case- and punctuation-sensitive. This is what `getAiModel` matches on. Get it EXACTLY right. |
| `provider` | Which `EModelProvider` it belongs to | `openai` \| `gemini` \| `mistral` \| `claude` \| `ollama` \| `qwen` \| `grok` \| `deepseek` \| `selfhosted` |
| `contextSize` | Context window in **tokens** (total input) | From official docs only |
| `maxTokens` | Max **output** tokens | From official docs only. Critical for Anthropic (unset → silent 4096 cap) |
| `isImagesSupported` | Does it accept **image input** (vision)? | true/false |
| `isDocsSupported` | Does it accept **document/file input** (PDF, etc.)? | true/false |
| `isToolSupported` | Does it support **tool / function calling**? | true/false. Gates PDF/DOCX/PPT/search/integrations in NSAI |
| `isReasoningModel` | Is it a **reasoning / thinking** model? | true/false |
| `isHighEffortOnlyModel` | Does it only run at high reasoning effort? | usually false; confirm only if reasoning model |
| `isImageGenerationModel` | Does it **generate images**? | true/false |
| `isGuardModel` | Is it a dedicated **safety/guard classifier**? | almost always false for a chat model |
| `isEmbeddingModel` + `embeddingDimensions` | Is it a **text-embedding** model? If so, output vector size | only for embedding models |
| (context) knowledge cutoff, release date, pricing | Helpful context, not a DB field | report if found |

Do **NOT** research or guess these — they are deployment/ops decisions, not model facts, and
belong to the person doing the seeding:

- `hostingProvider`, `region`, `baseUrl`, `apiKey` — where/how *we* host it.
- `quality`, `speed` — NSAI's internal relative scores (0-based; frontend denormalizes from 0-100%).
- `title`, `version`, `key`, `maxMessagesPerUser` — display/config choices.

For those, emit a placeholder and a one-line note ("ops decision — not researched").

## Procedure

1. Read `CreateModelDto` and `ModelEntity` (paths above) to lock the exact field names + enums.
2. `WebSearch` for the official provider docs page for the model. Then `WebFetch` the actual
   provider doc URL(s) — don't rely on the search snippet.
3. Fill each row of the table above **only** from what the fetched authoritative page states.
4. For anything the official sources don't state, write `UNVERIFIED` and say what's missing and
   where the user should confirm it (e.g. "context window not on the public model page — check
   the Azure/Vertex deployment console").
5. Never smooth over a gap. "I couldn't verify max output tokens" is the correct output; a
   plausible-looking number is not.

## Output format

Return a single report:

```
# Model spec research — <model>

## Verified facts (with sources)
- name: "<exact-id>"            [source: <url>]
- provider: <enum>             [source: <url>]
- contextSize: <n> tokens      [source: <url>]
- maxTokens: <n> tokens        [source: <url>]
- isImagesSupported: <bool>    [source: <url>]
- isDocsSupported: <bool>      [source: <url>]
- isToolSupported: <bool>      [source: <url>]
- isReasoningModel: <bool>     [source: <url>]
- isImageGenerationModel: <bool> [source: <url>]
- isEmbeddingModel: <bool> (embeddingDimensions: <n|N/A>) [source: <url>]
- knowledge cutoff / release / pricing: <...> [source: <url>]

## UNVERIFIED — do NOT assume, confirm before seeding
- <field>: <why it couldn't be verified + where to look>

## Ops decisions (not researched — set by whoever seeds the model)
- hostingProvider / region / baseUrl / apiKey / quality / speed / title / version / key / maxMessagesPerUser

## Ready-to-review draft row (VERIFIED values only; UNVERIFIED left blank)
{ name: "...", provider: "...", contextSize: ..., maxTokens: ..., isImagesSupported: ..., ... }

## Sources consulted
1. <url> — <what it confirmed>
2. ...
```

Hand this to whoever creates the model (or to the `add-model` / seed flow). The draft row must
contain **only** verified values — leave `UNVERIFIED` fields blank so nobody accidentally ships a guess.
