# Elicitation (Phase 3)

Requirements elicitation, not small talk: every question exists because its
answer changes the epic, the plan, or the priority. Ask **only** what Phase 2
research could not answer — asking the user something the code already told
you burns trust and time.

## The seven categories

Cover each one — from evidence when you have it, from a question when you
don't. A category with neither becomes an Open question in the epic.

| Category | What it decides | Example question |
| :--- | :--- | :--- |
| Affected users | Epic stakeholders; reach for prioritization | Who hits this — all users or a segment? |
| Severity & frequency | Priority, urgency, milestone order | How often, and how bad when it happens? |
| Business impact | Business-goal alignment; the "why now" | What does this cost us — revenue, churn, support load? |
| Constraints | Plan dependencies and risks | Deadline? Freeze windows? Compliance? Team availability? |
| Prior attempts | Evidence; ruled-out options | Has anyone tried to fix this before? What happened? |
| Definition of fixed/done | Success metrics, acceptance criteria | What number or behavior tells us this is resolved? |
| Evidence conflicts | Confidence; sometimes reframes the problem | You said X, but the code/history shows Y — which is current? |

## How to ask

- **Batch.** One structured round (AskUserQuestion with up to 4 questions,
  options where the answer space is known) — not a drip of one-offs. A
  second round is allowed only when a first-round answer opens something
  genuinely new.
- **Offer your evidence-based default as the first option.** "Research
  suggests checkout p95 (~3.1s) is the pain — is that the target?" is
  faster to confirm than an open question.
- **"I don't know" is an answer.** Record the unknown in the epic's Open
  questions, lower the hypothesis confidence, and consider a spike task to
  buy the answer. Never invent a metric target the user didn't confirm and
  evidence didn't establish.
- Skip the round entirely when evidence covered all seven categories —
  jumping straight to Phase 4 with a well-evidenced epic is the ideal run,
  not a shortcut.
