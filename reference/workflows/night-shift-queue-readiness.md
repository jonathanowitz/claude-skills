# Night Shift — Queue Readiness Rubric

**Purpose:** A front-door gate applied to a candidate GitHub issue *before* it enters `tmp/night-shift-queue.md`. Night shift ships PRs autonomously and unattended; a task that looks well-formed but rests on a false or stale premise produces a confident, well-reviewed, wrong (or no-op) PR overnight. This rubric is the check that a night-shift brief is *true, decided, and machine-provable* before an autonomous agent acts on it.

**Companion:** `night-shift-protocol.md` (the loop itself). This is the pre-queue filter; that is the runtime.

---

## Why the loop's own gates don't cover this

Night shift already self-protects at runtime: review personas can return `NEEDS_DISCUSSION` and skip, and the RED/GREEN/iteration caps stop a stuck task. Those catch *"the agent got stuck."* They do **not** catch the dangerous class — a task whose premise is false, because every persona reasons *inside* the same brief and confidently ratifies it. That is the "dispatch failure is the brief" finding and the "building for a scenario that no longer exists" chronic: the failure is not an error, it is a clean-looking PR against a stale reality. A runtime gate never questions its own input. The premise check has to happen at the door, by a reader who looks at the *current* code — not by the agent that already believes the brief.

Think of readiness as `/shape-project` plus two things a human-in-the-loop never needs: **premise freshness** (issues rot after they are filed — a cited file moves, a "prerequisite" ships, a column is renamed) and **autonomy exclusions** (visual and config work a person could eyeball but an unattended agent should not attempt). We are not reinventing shaping; we are adding the two deltas that autonomy and time introduce.

---

## The six checks — all must be green

| # | Check | Green when | Common red flags | Evidence axis |
|---|-------|-----------|------------------|---------------|
| 1 | **Premise still true** | Every "blocks / prerequisite / depends-on" reference, and every cited file / column / symbol, re-verified against **current** `main` by *reading the code*, not grepping the issue. | Referenced issue already closed/shipped; cited line moved or gone; "the fix" already present; behavior-map entry contradicts the code | Rule #3 (verify external claims), stale-context chronic |
| 2 | **Decision resolved** | No open option set. If the body offers alternatives, USER's pick is **explicit in the body**. | "Design options (to shape)", "pick during shaping", "open questions", `needs-shaping` / `someday` label, two acceptable approaches with none chosen | dispatch-failure-is-the-brief |
| 3 | **Behavior named** | "Done" is a concrete behavior — ideally with a sibling pattern to copy, but the sibling is *ideal, not required*. The agent does not have to *invent* the correct output. | Acceptance is a goal ("make it better"), not a concrete behavior. Absence of a sibling to copy is at most **partial** — never a red on its own. | brief quality |
| 4 | **Test surface exists** | A unit / contract / e2e test can prove it done. | Pure-visual (contrast, theme color, spacing), pure-config (dashboard signups, secrets), "looks right" is the only oracle | skips-are-red |
| 5 | **Scenario is real** | The users / data the task assumes exist in `seed.sql` / the e2e fixture *today* — **cited as a `seed.sql:NN` or fixture line**. *Seedable-but-not-seeded is not green:* a scenario that could be seeded via an established pattern, but isn't in the fixture now, is `partial` — fold the fixture in as an explicit **step-0** of the issue (so the data exists by the time the agent runs), or re-scope. That is the pre-dispatch verifier's exact bar (it grades an unseeded scenario `absent` → HOLD), so a rubric green here must mean *seeded now*, not *seedable*. Green asserted from code seams alone, with no data citation, is **not** green. | Built for a multi-gym / collision / persona case that the pilot shape doesn't contain; scenario assumed, never checked; **"the delegation is seedable" mistaken for "the coach-on-≥2-teams is seeded"** (#1247); #5 called green with no seed/fixture citation | chronic #2 / MVS rung-0 |
| 6 | **In night-shift's reach** | App code in this repo with an `npm test` / Playwright surface. | Infra shell scripts, another repo, hook/config machinery, no test runner | — |

Check #1 is the non-negotiable one and the one that cannot be mechanized: it requires opening the current file at the cited line and confirming the world still matches the brief. A grep of the issue text proves nothing — the issue is the thing under suspicion.

**What counts as check-#1 *partial* (vs. green).** Partial means *part of the described work has actually shipped or moved in the code* — a handler now exists, a control was rebuilt, a "preferred" fix the body names has since landed — leaving a live sub-scope. It does **not** mean a rotted *pointer*: a vanished `tmp/` scope doc, a closed linked issue, or a title count that has since drifted is a missing detail, not premise-staleness, **so long as the thing-to-build is still current**. A rotted pointer alone leaves check #1 **green**, and the issue is judged on the other five checks (so a task that is current but untestable, whose only "staleness" is a missing reference, resolves on checks #2–#6 — often DEAD-END — rather than parking at STALE). The test is always: did the *work* move, or only a *reference to* the work?

**Evidence discipline — a green check needs a citation, or it isn't green.** Check #1's "read the code" rule generalizes to all six: the classifier must back every **green** with a concrete artifact it actually opened — a `file:line`, a `seed.sql:NN`, a test path. A check asserted green with no citation is **not a pass; it is unverified**, and an unverified claim fails the check until reading confirms it true or false. (Earned 2026-08-04: a classifier green-lit check #5 for a multi-team scenario from code seams alone, never opening the seed — the exact "assume the scenario, never check it" trap #5 exists to catch.) The issue body is never evidence for itself, on any check.

---

## The six-rung ladder — verdicts sorted by distance-to-ready

A flat pass/fail hides the prize. Most backlog issues aren't READY, but they aren't uniformly *not* ready either — one is a single confirm away, another is genuine open design, a third is dead scenario that no confirm will fix. Collapsing all of those to "NOT-READY" throws away the only signal that matters: *how far* an issue is from being feedstock, and the *specific gap* between it and ready. So the four flat verdicts become **six rungs, sorted by distance-to-ready**. The six checks above are unchanged — the rungs are how a candidate's check results resolve to a disposition.

| Rung | Meaning | Which checks | Disposition |
|------|---------|--------------|-------------|
| **READY** | all six checks green | all green | enter the night-shift queue as-is |
| **ONE-DECISION** | blocked *only* by a small set (1–3) of discrete, enumerable USER calls; everything else green | #2 red on **enumerable** decisions; rest green | the high-value bucket. The report states each decision as its own `[USER]{}` slot; answering them all promotes the issue to READY. See the boundary note below |
| **STALE / RE-SCOPE** | premise drifted (check #1) — part shipped or moved — **and stripping what shipped leaves a remainder that needs no new decision** (auto-repairable in principle) | #1 partial; the remainder needs no decision/design and has a test surface | strip the issue to the live sub-scope; the stripped issue is then READY or ONE-DECISION. **A diagnostic tag *under evaluation*, not yet a distinct action — see the maturity note.** If the remainder needs a decision → NEEDS-SHAPING; if it has no possible oracle → DEAD-END |
| **NEEDS-SHAPING** | open design space — multiple acceptable approaches, or "done" not yet a concrete behavior | #2 red on **open** design, or #3 red (done is a goal, not a behavior — *not* merely "no sibling to copy") | route to `/shape-project` or a human session. This is real design work, not one confirm |
| **DEAD-END** | permanently ineligible for *autonomous* work | #4, #5, or #6 red (unfixable) | never bring to night-shift. May still be worked by hand — pure-visual, pure-config, other-repo, no test oracle don't become eligible by waiting |
| **ALREADY-DONE** | check #1 finds the work shipped — **verified against the issue's acceptance criteria, not the mere presence of same-named files** | #1 finds it done: the stated requirements / KDs are met, confirmed by reading them | do **not** queue; close the issue and reconcile any stale behavior-map / doc entry that still marks it open |

**The ONE-DECISION / NEEDS-SHAPING boundary is the load-bearing one, and it is *not* the literal count 1.** The boundary is **enumerable discrete decisions** (you could write each as its own slot — "confirm the copy", "confirm the icon", "prelim vs final default") **vs. open design space** (you couldn't enumerate the calls because the approach itself is unchosen). A well-scoped issue needing two or three discrete confirms is ONE-DECISION, not shaping; a single question like "how should this screen work?" is NEEDS-SHAPING even though it's one sentence. The distinction is *shape of the gap*, not its cardinality. When a rung is genuinely hard to call at this boundary, that ambiguity is itself the finding — it means the boundary needs sharpening, not that the classifier failed.

**A named option that points to a *generic container* is not an enumerable decision — it is unshaped.** "Surface it in the payload / in metadata / in competition metadata / somewhere in the response" reads like a location pick, but acting on it still requires choosing the *specific* column, table, and handler — that choosing is the design work. An enumerable decision names concrete alternatives ("prelim vs. final default", "`hasResults` field on `schedule-by-comp`"); a placeholder container names none. Treat a generic-container "option" as **NEEDS-SHAPING**, not ONE-DECISION.

**Multi-fault precedence.** Real issues fail more than one check, across rung boundaries — the flat table above says what a *single* red maps to, not which red wins. Resolve it in this order, so two independent readers land the same rung: **evaluate check #1 first.** If it shows the work shipped → **ALREADY-DONE**; if the premise is partially stale (per the *partial* definition above — real work moved, not just a rotted pointer) → **STALE / RE-SCOPE** (re-scope to the live sub-scope, then re-run the ladder on the reduced issue). These two are *premise-axis* states — they change what you are even classifying, so they short-circuit before any other rung. Only when the premise is fully true, assign the **farthest-from-ready** applicable rung: **DEAD-END › NEEDS-SHAPING › ONE-DECISION › READY**. (So a fully-current issue that is both open-design and untestable is NEEDS-SHAPING-or-DEAD-END by this order — but a *stale* one that looks untestable is STALE first, because re-scoping may surface a testable sub-scope the stale bundle hid.)

**STALE is defined by an *action test*, not by how the issue drifted.** The rung only earns a separate name if a distinct action follows it — and the only action that distinguishes STALE from NEEDS-SHAPING is an *autonomous re-scoper* that strips the shipped parts and restates the remainder **without making any new decision**. So a drifted issue is STALE only when stripping what shipped leaves a remainder that needs **no new decision** — a mechanical restate such a re-scoper could (in principle) perform. Route the remainder through the ladder: if it needs a decision or open design → **NEEDS-SHAPING** (a human, no matter how it drifted); if it has no possible oracle → **DEAD-END**; only a remainder that is workable-without-a-decision keeps the issue at **STALE**. (So "one raw-error leak already sanitized, copy that same pattern to the sibling leak" is STALE — no decision; "one finding shipped, but the live finding offers three unchosen implementation approaches" is NEEDS-SHAPING — its remainder needs a pick; "one part shipped, the survivor is paste-a-secret-by-hand" is DEAD-END — no oracle.)

---

## Target: what a night-shift-ready issue body contains

The ladder tells you *where* an issue sits; this is the *target it's moving toward* — the written shape a READY issue body satisfies, so "flesh it out" has a spec to hit instead of being re-invented per issue. Each item is a check read constructively: not "does it pass?" but "what must the body *contain* so an unattended agent never has to invent the answer." An issue that names all six is READY by construction.

1. **A premise stated as a claim already verified against `main`** *(check #1)* — not "blocked by #900" but "the `results-publish` handler at `api/_src/results-publish.ts:NN` still rejects empty `rows[]` as of `main@<short-sha>`." The body cites *current* code, so the door-check is a confirmation, not a re-investigation. A bare cross-issue reference ("depends on #NN") is not a stated premise — it's an unresolved one.
2. **The single decided approach — no open options** *(check #2)* — the body names the one chosen path. Any "options / alternatives / could also" is either resolved to USER's explicit pick inline, or the issue is not READY (it's ONE-DECISION at best). An enumerable leftover decision is fine *as a listed slot*; an unstated one is not.
3. **The done-behavior named concretely, with a reference to copy** *(check #3)* — "done" is a described behavior plus, ideally, a sibling implementation the agent mirrors (`see how X does it at path:NN`), not a goal ("make it better", "improve the flow"). The agent reproduces a known shape; it does not design one.
4. **The test oracle that will prove it** *(check #4)* — the body names the surface that turns the change green: a unit/contract test to add, an existing Playwright spec to extend, a specific assertion. "Looks right" is not an oracle. If nothing can prove it done, the issue is DEAD-END for autonomy, however clear.
5. **Confirmation the scenario's data exists today** *(check #5)* — the users, gyms, roles, or rows the task assumes are present in `seed.sql` / the e2e fixture / project memory *now*, stated as such. A task built for a collision or persona case the pilot shape doesn't contain is building for a scenario that doesn't exist.
6. **In-repo, in-reach** *(check #6)* — the work is app code in this repo with an `npm test` / Playwright surface, not infra shell, another repo, or hook/config machinery. This is usually implicit but is the fastest DEAD-END to spot.

A body carrying all six needs no shaping conversation and no mid-run human call — which is exactly what "autonomously workable" means. The ladder's rungs are named by *which of these six the body is missing*: missing one enumerable decision → ONE-DECISION; missing a chosen approach entirely → NEEDS-SHAPING; missing an oracle that can never exist → DEAD-END.

---

## How to apply it

1. **Cheap pre-filter (optional, saves the reasoning pass on obvious rejects).** Grep the candidate set for the check-2/5/6 red-flag signals: `needs-shaping` / `someday` labels, the phrases "to shape" / "open questions" / "pick during", cross-repo `--repo` targets. This is a *pre-filter, never the gate* — a clean grep does not mean READY, it means "worth the reasoning pass."
2. **Reasoning pass, per candidate.** Run the six checks. For check #1 you MUST read the current code at every cited location — this is where staleness hides and where the value is. A `sonnet` agent can do this per-issue in parallel; pin the model, hand it the issue body + the files it cites.
3. **Emit a readiness report** (format below) — not a pass/fail flag but the *specific* blocker per not-ready item and the *one decision* that would promote each near-ready item. "Not ready" is far less useful than "one confirm away from ready."

### Readiness report format

Write to the project's `tmp/night-shift-readiness-YYYY-MM-DD.md` (with the `- [ ] Done` header per tmp/ convention):

- **Batch headline** — N of M ready; what the premise check caught.
- **Verdict table** — one row per candidate, the six checks, the verdict.
- **Per-issue detail** — the evidence (`file:line`) behind each non-green check.
- **Decisions needed** — the small human calls (close X? re-scope Y?), each as a `[USER]{}` slot.
- **Resulting queue** — the READY set, in stack order.

---

## Maturity path — resist the subsystem

This is a rubric, not a scoring engine. Night shift already carries heavy telemetry; a second measurement layer for readiness is over-build. The checks that matter (premise-truth, decision-resolved, scenario-real) are semantic and cannot be reduced to a shell script without manufacturing false confidence.

1. **Now:** apply by hand (or one pinned `sonnet` pass), emit the report. The report *is* the deliverable.
2. **Later, once the rubric is stable across a couple of runs:** fold the six checks into the loop's **Step 1 (Pick Next Task)** as a gate that refuses a not-ready item and logs *which check* failed. Keep the read-the-code requirement for check #1 — it stays a reasoning step, never a grep.

Do not build a standalone `/queue-check` skill or a readiness-telemetry file until the by-hand version has earned it.

**The STALE rung presumes an autonomous re-scoper that does not yet exist — do not build it yet.** Until it does, STALE and NEEDS-SHAPING trigger the *same* action: a human promotes the issue. STALE therefore earns no distinct machinery right now. Keep tagging it (by the action test above) as a **hypothesis under test**: run a couple of real feedstock passes by hand, then review the STALE-tagged issues and ask "could an agent have restated this without a decision?" Only if that is *reliably* yes does the auto-re-scoper — and STALE as a distinct action — earn its build. The manual cycles are how we find out whether auto-re-scoping is even possible; committing to build it before that evidence is the exact over-build this section exists to prevent. (Decision: 2026-08-04, after a blind-eval re-run showed the STALE/NEEDS-SHAPING split only matters downstream of an action that doesn't exist yet.)

---

*Created: 2026-07-22 — after a 4-candidate batch where the premise check found 2 of 4 stale (one already shipped, one two-thirds obsolete), work that would otherwise have run as no-op/conflicting overnight PRs.*
