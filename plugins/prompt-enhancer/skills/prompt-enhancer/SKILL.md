---
name: prompt-enhancer
description: Expert guidance for improving and enhancing prompts. Use when the user shares a raw, vague, or first-draft prompt and wants it clarified, tightened, strengthened, or made more reliable; asks to "improve / rewrite / optimize this prompt", "make this prompt better", or write a system prompt; or mentions prompt engineering, few-shot/multishot examples, chain-of-thought, role/system prompts, XML structuring, or prompt templates. Applies an ordered set of techniques (clarity, context, examples, structure, role, reasoning, chaining), scaled to the prompt's complexity, and returns the enhanced prompt plus a tagged change log explaining what changed and why.
---

# Prompt Enhancer

Use this skill to turn a base prompt into a stronger one. The default behavior
is a single pass: read the user's prompt, apply an ordered set of
prompt-engineering techniques, and return the enhanced prompt together with a
plain-language account of what changed and why. Rewrite **and** explain — never
hand back a silently transformed prompt the user cannot audit.

Enhance to disprove, not to decorate. Add a technique only when it makes the
prompt measurably clearer for its goal; if the original is already tight, say
so and change little. Match effort to the prompt's complexity.

Prompt-engineering guidance is **version-sensitive**: model behavior, token
limits, and provider-specific flags drift between releases. Treat the technique
*principles* below as durable, but verify any concrete model name, limit, or
API field against the provider's current documentation rather than trusting
fixed values from memory.

## When To Use

Use this skill when the user supplies a prompt (or describes one) and wants it
improved, clarified, tightened, or made more reliable — whether it is a
one-line request or a long system prompt. If the user instead wants a brand-new
prompt written from nothing, gather the goal first (see
[Thin Prompts](#thin-prompts)), then enhance the resulting draft.

## Process

1. **Read the base prompt and infer its goal.** What outcome does the user
   actually want, for what audience, in what shape? If the prompt is too thin
   to infer a goal, follow [Thin Prompts](#thin-prompts) before rewriting.
2. **Run the completeness check.** A well-formed prompt covers up to four
   components: an **instruction** (the task), **context** (background and
   motivation), **input data** (the material to act on), and an **output
   indicator** (the shape of the result). Not all are needed for every task —
   note which are missing *and matter*.
3. **Apply the techniques in priority order.** Work down the ordered list in
   [techniques](references/techniques.md), applying each only where it helps.
   The order is deliberate: clarity first, structure and examples next, role
   and reasoning last.
4. **Scale to complexity.** For a simple ask, a clarity pass may be the whole
   job. Reserve examples, XML structure, role framing, and chain-of-thought for
   prompts whose difficulty earns them. Name anything you *remove* as noise,
   not just what you add.
5. **Assemble the two-part result.** Return the [result](#result) below.
6. **Stay version-honest.** When the prompt targets a specific model or
   provider, advise verifying details against that provider's current docs. See
   the freshness note in [techniques](references/techniques.md).

## The Techniques, In Order

The ordered, sourced checklist lives in
[techniques](references/techniques.md). In brief:

1. Be clear, direct, and detailed — state the task and constraints explicitly.
2. Add context and motivation — explain *why*, so the model generalizes.
3. Use 3–5 relevant, diverse examples (multishot), wrapped in example tags.
4. Structure the prompt with XML-style tags separating instruction, context,
   and input.
5. Give the model a role via a system prompt.
6. Let the model think (chain-of-thought) for reasoning-heavy tasks.
7. Prefill or chain prompts for complex, multi-step work.

Worked before/after rewrites for each technique are in
[examples](references/examples.md).

## Result

Return exactly two parts, in this order:

1. **Enhanced prompt** — the rewritten prompt, ready to copy and use, in a
   fenced block so the user can lift it verbatim.
2. **Change log** — a short list of the changes, each tagged by the technique
   that motivated it and a one-line reason. Use these tags:
   - `clarity` — sharpened or disambiguated the instruction.
   - `context` — added background or motivation.
   - `example` — added or restructured examples.
   - `structure` — introduced or tidied XML-style sectioning.
   - `role` — set or adjusted a system role.
   - `reasoning` — invited step-by-step thinking.
   - `chaining` — split into stages or added prefill.
   - `cut` — removed noise, redundancy, or over-specification.

Close with a one-line **completeness note**: which of the four components
(instruction, context, input, output indicator) are now present, and any the
user must still supply (for example, real input data or domain facts).

## Thin Prompts

When the base prompt is too sparse to enhance well, do not invent intent. Ask
the user up to three targeted questions — typically goal, audience, and desired
result shape — then enhance the answer-informed draft. Asking is the fallback,
not the default; a workable prompt should be enhanced in one pass.

## Boundaries

- This skill improves prompts; it does not run them, benchmark them, or stand
  up an evaluation harness. Suggest the user test against their own success
  criteria, but keep testing out of scope.
- It does not assume a specific provider or model. The techniques are general;
  the live-doc pointers in [techniques](references/techniques.md) cover
  vendor-specific detail.
- It never fabricates the user's domain facts or input data. Missing material
  is flagged in the completeness note, not guessed.

## References

- [techniques](references/techniques.md) — the seven prompt-engineering
  techniques in priority order, the four completeness components, and the
  version-honesty note, with sources.
- [examples](references/examples.md) — worked before/after enhancements showing
  the two-part result format and proportional technique use.
