# Worked Examples: Before and After

Each example shows a base prompt, the enhanced prompt, and the change log. The
goal is to illustrate the two-part result format and how techniques are applied
*proportionally* — small prompts get small fixes.

---

## Example 1 — Simple prompt, clarity only

**Base prompt:**

```
write a function to sort users
```

**Enhanced prompt:**

```
Write a Python function `sort_users(users)` that sorts a list of user dicts by
their `last_name`, then `first_name`, both ascending and case-insensitive.
Return a new list; do not mutate the input. Include a docstring.
```

**Change log:**

- `clarity` — named the language, signature, sort keys, and return contract.
- `clarity` — stated the no-mutation constraint that was implied but unwritten.
- `cut` — nothing removed; the original was just underspecified.

**Completeness note:** instruction and output indicator now present; input data
(the actual user list) is supplied at call time. No examples needed — the
contract is unambiguous in prose.

---

## Example 2 — Format-sensitive task, examples + structure added

**Base prompt:**

```
Classify these support tickets by urgency.
```

**Enhanced prompt:**

```
You are a support triage assistant.

<instructions>
Classify each ticket as one of: low, medium, high, critical.
Base urgency on customer impact and time-sensitivity, not tone.
Output one line per ticket as: <id>: <urgency>
</instructions>

<examples>
<example>
Input: "Login page returns 500 for all users since 9am."
Output: T1: critical
</example>
<example>
Input: "Typo on the pricing FAQ page."
Output: T2: low
</example>
<example>
Input: "Export works but is slow for large accounts."
Output: T3: medium
</example>
</examples>

<input>
{paste tickets here, one per line, prefixed with an id}
</input>
```

**Change log:**

- `role` — added a triage-assistant role to focus judgment.
- `clarity` — defined the label set and the basis for urgency.
- `structure` — split instructions, examples, and input into tags so pasted
  tickets cannot be read as commands.
- `example` — added three diverse examples spanning the urgency range.
- `clarity` — specified an exact per-ticket result line.

**Completeness note:** instruction, context, and output indicator present;
the user supplies the input data in the `<input>` block.

---

## Example 3 — Over-engineered prompt, trimmed

**Base prompt:**

```
You are the world's greatest, most amazing, incredibly talented expert writer
with 30 years of experience. Please, if you would be so kind, possibly help me
maybe write a short and concise but also detailed and thorough tweet about cats.
```

**Enhanced prompt:**

```
You are an experienced copywriter.
Write one tweet (under 280 characters) about why cats make good apartment pets.
Tone: warm and a little witty.
```

**Change log:**

- `cut` — removed flattery and hedging ("world's greatest", "if you would be so
  kind") that add no signal.
- `cut` — resolved the contradictory "concise but detailed and thorough" into a
  single concrete constraint (under 280 characters).
- `role` — kept a one-line role; dropped the inflated persona.
- `clarity` — pinned the subject, length, and tone.

**Completeness note:** instruction, role, and output indicator present; no
external input data required.

---

## Reading these examples

Notice the proportionality: Example 1 needed only clarity, Example 2 earned
structure and examples because format mattered, and Example 3 was improved
mostly by *removing* noise. Enhancement is not "apply all seven techniques" —
it is choosing the few that move this prompt toward its goal.
