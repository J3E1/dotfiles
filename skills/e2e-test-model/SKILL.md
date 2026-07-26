---
name: e2e-test-model
description: Drive the live NodeShift web app in a browser to fully end-to-end test a newly-seeded model — chat/streaming, PDF/DOCX/PPT generation, doc-from-attachment, vision, tools/search/integrations, reasoning. Runs as a FLAG-CONDITIONAL matrix: only tests the capabilities the model's flags declare, and asserts the ones it doesn't are correctly hidden. Reports pass/fail per capability with evidence.
argument-hint: <model title or name as shown in the picker> [app URL]
allowed-tools: AskUserQuestion, Read, Grep
---

# E2E test a new model (browser)

You are driving the **real NodeShift web app in a browser** (browser-extension Claude) to prove
a newly-added model actually works across every feature it claims to support. The model to test
is in `$ARGUMENTS`.

The core principle: **NSAI features are gated on the model's capability flags.** So this is not a
fixed script — it's a *conditional matrix*. First learn which flags the model has, then:

- For each `true` flag → run its test and require it to **work**.
- For each `false` flag → assert the feature is **absent / disabled** for this model (a bug is
  the feature showing up when the model can't do it, just as much as it not working when it should).

Never assume a capability. If you can't determine a flag, ask the user with `AskUserQuestion`
before deciding whether to test that section.

## Step 0 — Establish the flag matrix (do this first)

Find out, for the model under test, the value of each capability flag. Ask the user, or have them
paste the model's admin row / the values the `research-model-specs` skill produced:

| Flag | Feature it gates | If false, expect… |
|---|---|---|
| `isToolSupported` | PDF, DOCX, PPT, doc-from-attachment, web/deep search, integrations | those tools unavailable |
| `isImagesSupported` | image/vision upload | image upload blocked/hidden |
| `isDocsSupported` | document/file analysis | doc upload blocked/hidden |
| `isImageGenerationModel` | image generation | no image-gen |
| `isReasoningModel` | thinking/reasoning UI | no reasoning trace |

Also confirm the pre-flight facts before testing behavior:
- The model is **enabled**, **not** in maintenance mode, and **appears in the ModelPicker**.
- It is selectable in a new chat and its capability chips/filters match the flags above.

Write down the matrix, then run only the applicable sections below.

## Step 1 — Core chat (ALWAYS run)

1. Start a new chat, select the model.
2. Send a simple prompt (e.g. "In one sentence, what is NodeShift?"). Confirm:
   - Response **streams** (renders progressively, not one final dump). Some providers use
     *simulated* streaming — still expect smooth incremental text, just note if it arrives chunkier.
   - Answer is coherent and on-topic.
3. Send a follow-up that depends on the previous turn → confirm **context is retained**.
4. Ask for a **long** structured answer (markdown headings, a table, a fenced code block) →
   confirm formatting renders and output isn't truncated well before its stated `maxTokens`.
5. Start another response and **Stop** it mid-stream → confirm it halts cleanly.
6. **If `isReasoningModel`:** confirm the reasoning/thinking indicator appears and the final
   answer still lands.

## Step 2 — Tool-gated features — ONLY if `isToolSupported = true`

If the model is not tool-capable, instead **verify these are unavailable** for it and skip the rest.

1. **PDF generation** — "Generate a one-page PDF summarizing X." → a PDF artifact is produced,
   downloads, opens, and its content matches the request.
2. **DOCX / Word** — "Create a Word document with sections A, B, C." → `.docx` downloads, opens,
   sections present and formatted.
3. **PPT / presentation** — "Make a 4-slide deck about X." → deck generates (external
   presentation-builder), slides render with titles/content; note if slide images appear.
4. **Document from an attached document (template flow)** — upload a template document, then
   "Fill this template using the following details: …" → output document mirrors the template
   structure with the new content.
5. **Web / Deep search** — ask something needing current info ("What happened with X this week?").
   Requires search to be enabled server-side (Tavily) → answer includes fresh info / citations.
   If search UI isn't offered, note it (may be an env/config gap, not a model bug).
6. **Integrations / tool call** — trigger at least one connected tool (e.g. a knowledge/RAG lookup
   or a Composio action) → confirm the tool is invoked and its result is used in the reply.

For each: capture what you asked, whether the artifact/result appeared, and whether the content
was correct — not just "it responded."

## Step 3 — Attachment-gated features

- **Vision — ONLY if `isImagesSupported`:** upload an image, ask "What's in this image?" →
  accurate description. If the flag is **false**, confirm the app **blocks/hides image upload**
  for this model.
- **Document analysis — ONLY if `isDocsSupported`:** upload a PDF/DOCX, ask a question answerable
  only from its contents → answer is grounded in the file. If **false**, confirm doc upload is
  blocked/hidden.
- **Image generation — ONLY if `isImageGenerationModel`:** "Generate an image of …" → an image
  is produced.

## Step 4 — Failure / guardrail checks (light pass)

- Send an input larger than the context window (paste a very long block) → app degrades
  gracefully (compression or a clean error), **no crash / 500 / infinite spinner**.
- If you can, observe behaviour on a provider/rate-limit error → a readable error message, chat
  stays usable.

## Step 5 — Report

Return a per-capability results table. Do **not** report a blanket "works" — report each cell:

```
# E2E results — <model>

Flag matrix: isToolSupported=<>, isImagesSupported=<>, isDocsSupported=<>,
             isImageGenerationModel=<>, isReasoningModel=<>

| Capability            | Applicable? | Result   | Evidence / notes                         |
|-----------------------|-------------|----------|------------------------------------------|
| Appears in picker     | yes         | PASS/FAIL | ...                                     |
| Core chat + streaming | yes         | PASS/FAIL | ...                                     |
| Context retention     | yes         | PASS/FAIL | ...                                     |
| Reasoning             | flag-based  | PASS/FAIL/N-A | ...                                 |
| PDF generation        | flag-based  | PASS/FAIL/N-A | ...                                 |
| DOCX generation       | flag-based  | PASS/FAIL/N-A | ...                                 |
| PPT generation        | flag-based  | PASS/FAIL/N-A | ...                                 |
| Doc from attachment   | flag-based  | PASS/FAIL/N-A | ...                                 |
| Web / deep search     | flag-based  | PASS/FAIL/N-A | ...                                 |
| Integrations / tools  | flag-based  | PASS/FAIL/N-A | ...                                 |
| Vision (image input)  | flag-based  | PASS/FAIL/N-A | ...                                 |
| Document analysis     | flag-based  | PASS/FAIL/N-A | ...                                 |
| Image generation      | flag-based  | PASS/FAIL/N-A | ...                                 |
| Absent-when-off checks| yes         | PASS/FAIL | list features correctly hidden          |
| Oversized input       | yes         | PASS/FAIL | ...                                     |

## Blockers (must fix before merge)
- ...

## Non-blocking notes
- ...

Verdict: READY TO MERGE / NOT READY — <one line>
```

A capability is only **PASS** if you saw the actual working output (the PDF opened, the image was
described correctly), not merely that the model replied. Anything you couldn't test → mark why,
don't pass it by default.
