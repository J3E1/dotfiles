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

- `hostingProvider`, `region`, `baseUrl`, `apiKey` — where/how *we* host it. (Anthropic/Gemini
  rows in this repo use `region: "EU"`, `hostingProvider: "Google"`, `baseUrl/apiKey: null` —
  mirror the sibling.)
- `quality`, `speed` — NSAI's internal relative scores. **The web will never give you these.**
  Set them **relative to the closest sibling model** already in the seed: a newer/better model
  gets a higher `quality` than the one it succeeds; a "lite"/"mini" gets lower quality + higher
  speed. `quality` is unbounded above (the `CreateModelDto` comment says so) — a new flagship
  may exceed all existing scores (e.g. Opus 5 → `100`, above Opus 4.8's `99`). Do NOT copy a
  sibling's `quality`/`speed` verbatim, or the two models become indistinguishable in the picker.
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

The draft row must contain **only** verified values — leave `UNVERIFIED` fields blank so nobody
accidentally ships a guess. Then register the model using the checklist below.

## Where a model must be registered (codebase placement checklist)

**A model is NOT just a seed row.** A single model name is hardcoded in ~6 places, and missing
any one leaves the model mis-sorted, absent from a picker, or (for some Claude models) throwing
provider 400s. Adding the seed row alone is the #1 way to ship a half-wired model.

**Find every place first — grep an existing sibling.** Before editing anything, pick the closest
already-shipped model (e.g. `claude-opus-4-8`, `gemini-3.5-flash`) and grep the whole repo for
its name in every form:

```bash
grep -rniE "opus-4-8|opus 4\.8|ClaudeOpus4_?8" --include=*.ts --include=*.tsx \
  --include=*.mjs --include=*.md . | grep -v node_modules | grep -v /dist/
```

Every hit is a candidate placement. Triage them into: **functional** (add the new model),
**decision** (ask/flag), **leave** (tests + comments).

### Functional — add the new model to ALL of these

| Location | What to add |
|---|---|
| `apps/nsai/migrations/data/models/<provider>.ts` | The `SEEDED_*_MODELS` row. **Claude also:** add the name to `ALLOWED_CLAUDE_MODELS` in the same file. |
| `apps/nsai/server/src/bot-shared/utils/bot-model-priority.utils.ts` | A priority number in the provider block (higher = more capable/newer). |
| `apps/nsai/frontend-shared/models/model-display-priority.ts` | The same priority number **and** consider `POPULAR_MODEL_NAMES` (the curated top-of-picker shortcut). |
| `apps/nsai/web/src/pages/models/components/constants.ts` | The name in the provider's known-model list (Add-Model form suggestions). |

Keep the priority number consistent across the two priority maps (they carry identical blocks).
Rank the new model against its siblings; renumber the block minimally to avoid collisions within
a provider.

### Provider routing (server) — the highest-risk step

A model on an **existing** provider+hosting combo usually needs **no** `getAiModel` change — but
check the provider's name-based branching in `apps/nsai/server/src/utils/ai-model.ts` and
`apps/nsai/server/src/utils/utils.ts`:

- **Anthropic / Claude:** a thinking-on-by-default model (Opus 5, Sonnet 5, Fable/Mythos) MUST be
  added to `CLAUDE_ADAPTIVE_THINKING_MODEL_NAMES` in `utils.ts` (adaptive thinking + it makes
  `shouldOmitTemperatureParam` true — these models **400 if sent `temperature`**). If omitting the
  `thinking` param should leave thinking ON (so Fast mode must send explicit `disabled`), also add
  it to `CLAUDE_THINKING_ON_WHEN_OMITTED_MODEL_NAMES`. Mirror the closest sibling exactly
  (e.g. Opus 5 ↔ Sonnet 5, both sets).
- **Gemini:** routes by **name prefix** — `gemini-3*` → `thinkingLevel`, `gemini-2.5*` →
  `thinkingBudget`. A new `gemini-3.x` / `gemini-2.5.x` needs **no** code change.
- **OpenAI:** name-based special cases exist (`gpt-5-pro`/`gpt-5.4`/`gpt-5.5`/`gpt-5.6` → responses
  API, `gpt-5.4-mini` → plain chat). A new gpt-5.x may need a branch here.
- **A brand-new provider or hosting combo** always needs a `getAiModel` change **plus** unit tests
  in `apps/nsai/server/src/utils/ai-model.spec.ts`.

### Decisions — surface to the user, don't silently change

These reference specific model names as **operational defaults**; changing them shifts routing or
publishes publicly, so flag rather than auto-edit:

- **Presentation routing defaults** — `PRESENTATION_BEST_MODEL_KEYS` and
  `BRANDED_PRESENTATION_MODEL_KEY` in `env-config.schema.ts`, the three
  `apps/nsai/server/.env-flavors/env.example.{staging,prod,1vm}.ts`, and
  `docs/configuration/backend-envs.md`. Prepending a stronger new model changes prod deck routing.
- **Landing marketing table** — `apps/nsai/landing/src/app/ai-models/components/ModelsTable/data.ts`
  is public-facing and carries per-model `countries` availability.

### Leave alone

Test fixtures (`*.spec.ts`) and code comments that merely use a sibling model name are not catalog
membership — don't add the new model to them.

### Verify

Type-check every package you touched — `migrations`, `server`, `frontend-shared`, `web` — and run
the affected specs (e.g. `bot-model-priority`, `ai-model.spec.ts`). To seed into a running DB:
`npm run seed:models:append` from `apps/nsai/migrations`. Then run the `e2e-test-model` skill.
