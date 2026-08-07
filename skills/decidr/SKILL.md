---
name: decidr
description: Author a swipe-deck of yes/no/maybe-shaped questions, run it with the decidr CLI, and read the human's answers back into the session.
---

# decidr

decidr is a swipe-to-decide surface: instead of asking a person one question at a time in
chat (or hitting the four-question ceiling of a tool like `AskUserQuestion`), you author a
whole batch of questions as a **deck**, hand it to the `decidr` CLI, and a browser opens with
one card per question. The human answers each card with a single directional input — left,
right, or up — and when they're done, you read a structured **answer** file back into your
context. Use this whenever you have more than a handful of related decisions to put in front
of the human at once: triaging a backlog, picking between options across many items,
confirming a batch of small decisions before you act on them.

The workflow has four beats:

1. The human asks you (in this session) to run a decidr pass over something.
2. You author a **deck** — a JSON file describing the cards and the choices — against the
   schema below.
3. You run `decidr <deck.json>` **in the background**. It opens the person's
   browser prepopulated with the deck and prints the path to the answer file as the first
   line of stdout.
4. When that backgrounded process **exits**, you read the printed answer file and use the
   answers.

Two hazards will break the workflow if you skip them — read the "Running the CLI" section
below before you invoke anything.

## Authoring a deck

A deck is a single JSON file, validated against `contract/deck.schema.json` in the decidr
package. The shape, in full:

```json
{
  "schema": 1,
  "deck_id": "my-triage-pass",
  "title": "Triage the Q3 backlog",
  "prompt": "For each item, keep it, drop it, or flag it for later.",
  "choices": [
    { "value": "keep", "label": "Keep", "direction": "left", "key": "ArrowLeft" },
    { "value": "later", "label": "Later", "direction": "up", "key": "ArrowUp" },
    { "value": "drop", "label": "Drop", "direction": "right", "key": "ArrowRight" }
  ],
  "default": "later",
  "cards": [
    {
      "id": "card-1",
      "title": "First item's headline",
      "subtitle": "Optional one-line context",
      "body": "As much detail as the human needs to decide. This field is deliberately unbounded — reading is cheap when answering is one key, so don't compress it.",
      "meta": { "anything": "you want to carry through to the answer file" }
    }
  ]
}
```

Rules that matter when you author against the schema:

- `deck_id`, and every card `id`, must match `^[A-Za-z0-9_-]+$` — no dots, slashes, spaces, or
  non-ASCII. `deck_id` names a localStorage key and an answer-file sibling.
- `choices` must have **2 or 3** entries, never 4 — there are only three directions
  (`left`, `up`, `right`). Two choices bind left/right; three bind left/up/right.
- Each choice needs a unique `key` (a `KeyboardEvent.key` value, e.g. `"ArrowLeft"`,
  `"y"`, `"n"`). Never use `Backspace` — decidr reserves it to undo the last answer.
- `value` is what actually lands in the answer file — keep it stable, since you'll read it
  back and probably branch on it.
- `default` (deck-level and/or per-card) is the fallback answer if a card is skipped; a
  card's own `default` overrides the deck's.
- `cards` needs at least one entry; `title` is required and bounded (a card must be
  answerable on sight) but `body` is unbounded, so put the full context there.
- `meta` on a card is a free-form passthrough — the one place you can carry your own domain
  data through the deck; decidr never reads it, it just comes back in the answer file.

See `contract/fixtures/` in the decidr repo (github.com/witzcraft/decidr) for full worked
decks before writing your own.

## Running the CLI

```
decidr <deck.json>
```

This command **blocks** — the process it starts is the same process serving the browser
session, so it cannot exit until the human is done (or it times out idle). That has two
consequences you must handle correctly:

- **Run it backgrounded.** Use your `run_in_background` capability (or equivalent) to start
  it. If you run it in the foreground, it hangs your session until the human finishes
  answering — do not do this.
- **Read the answer file only after the process exits or finishes.** The first line the
  command prints to stdout is the absolute path to the answer file it will write. That path
  is valid the moment it's printed, but the file itself is only complete once the process has
  exited (status `complete` when the human finishes, or a non-zero exit if the session ended
  early). Reading it while the process is still running reads a half-written file. Poll or
  wait for the backgrounded process to finish, then read the JSON at that path.

Once the process has exited, read the answer file and use each card's recorded answer
(matched back to the `id` you authored) to drive whatever you do next.

## Installing this skill

A human gets this skill into their Claude Code with one command:

```
npx @witzcraft/decidr install-skill
```

That's how you got here if you're reading this from `~/.claude/skills/decidr/SKILL.md`.
