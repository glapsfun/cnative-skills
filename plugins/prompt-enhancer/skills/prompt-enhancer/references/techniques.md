# Prompt-Engineering Techniques, In Priority Order

Apply these in order when enhancing a base prompt. The ordering is deliberate:
the earlier techniques pay off for almost every prompt, while the later ones
are reserved for harder tasks. Apply a technique only where it makes the prompt
measurably clearer for its goal — do not stack all seven onto a simple request.

Each technique below names *what it does*, *when to reach for it*, and the
*signal* in the base prompt that calls for it.

## 1. Be clear, direct, and detailed

- **What:** State the task, constraints, and success conditions explicitly.
  Replace vague verbs ("handle", "deal with") with concrete ones. Spell out
  scope, length, audience, and any "go beyond the basics" expectations.
- **When:** Always. This is the highest-leverage change for most prompts.
- **Signal:** One-liners, undefined pronouns, implied-but-unstated requirements.

## 2. Add context and motivation

- **What:** Explain *why* the task matters and how the result will be used. A
  model that understands the goal generalizes better than one given a bare
  rule. ("Never use ellipses" → "This is read aloud by text-to-speech, which
  cannot pronounce ellipses, so never use them.")
- **When:** Whenever a constraint would otherwise look arbitrary, or the use
  case shapes the right answer.
- **Signal:** Bare rules, unexplained "do/don't" lists, missing audience.

## 3. Use examples (multishot)

- **What:** Show 3–5 examples of the desired behavior. Make them **relevant**
  (mirror the real use case), **diverse** (cover edge cases so the model does
  not latch onto an accidental pattern), and **structured** (wrap each in an
  example tag so it is clearly demonstration, not instruction).
- **When:** Output format, tone, or structure matters and is hard to describe
  in words.
- **Signal:** Format requirements, classification or extraction tasks,
  "make it look like X."

## 4. Structure with XML-style tags

- **What:** Separate instruction, context, examples, and input into clearly
  labeled sections (for example `instructions`, `context`, `input`) so the
  model never confuses data for commands. Use consistent, descriptive tag
  names; nest when there is natural hierarchy.
- **When:** The prompt mixes several content types, or includes user-supplied
  input that must not be read as instructions.
- **Signal:** Long prompts, prompts with pasted data, prompt-injection risk.

## 5. Give the model a role

- **What:** Set a role or persona in the system prompt to focus tone and
  expertise ("You are a meticulous security reviewer"). Even one sentence
  shifts behavior.
- **When:** Specialized tone, domain rigor, or a consistent voice is needed.
- **Signal:** Generic-sounding requests that would benefit from expert framing.

## 6. Let the model think (chain-of-thought)

- **What:** Invite step-by-step reasoning before the final answer for tasks
  that need analysis, math, or multi-factor judgment. Optionally separate the
  thinking from the final answer.
- **When:** Reasoning-heavy tasks where a snap answer is often wrong.
- **Signal:** Math, logic, planning, "explain your reasoning," nuanced tradeoffs.

## 7. Prefill or chain prompts

- **What:** For complex, multi-step work, split the task into chained prompts
  (each handling one stage), or prefill the start of the response to constrain
  format. Each stage's output feeds the next.
- **When:** The task is too large or multi-stage for one clean pass.
- **Signal:** Pipelines, "first do A, then B, then C," fragile single-shot megaprompts.

## The four completeness components

Independent of the seven techniques, check that the prompt covers the
components it needs:

- **Instruction** — the specific task to perform.
- **Context** — background or motivation that steers the answer.
- **Input data** — the material the task operates on.
- **Output indicator** — the type or format of the desired result.

Not every prompt needs all four; flag only the missing ones that matter.

## Freshness and version-honesty

Prompt-engineering guidance, model names, token limits, and provider-specific
flags change over time. When the user's prompt targets a specific model or
provider, advise verifying details against the provider's current docs rather
than trusting fixed values from memory. Treat the technique *principles* above
as durable, but treat any concrete numbers, model identifiers, or API field
names as things to confirm live.

## Sources

These techniques are synthesized from:

- Anthropic — [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices).
- Anthropic — [Prompt engineering overview](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/overview)
  (improvement-as-workflow; hosted prompt improver/generator).
- Prompt Engineering Guide — [Elements of a prompt](https://www.promptingguide.ai/introduction/elements)
  (four components).
