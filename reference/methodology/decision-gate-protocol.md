# Decision Gate Protocol

**Purpose:** Prevent strategic/tactical context switching that kills momentum

## The Problem

Common anti-pattern:
1. Start implementing feature X
2. Mid-implementation, user asks: "Should we use strategy A or B for this?"
3. Stop coding, discuss strategy for 30 minutes
4. Return to implementation, context lost
5. Discover built work doesn't align with strategy decision
6. Refactor or abandon work

**Result:** Wasted time, decision fatigue, incomplete features

## The Solution: Three Decision Gates

### Gate 1: Before Building

**When:** User requests feature or you propose implementation
**Question:** "Is this approved? Is this urgent?"

**If YES to both:** Proceed with implementation
**If NO to either:** Clarify before coding

**Example dialogue:**
```
User: "Add a referral system"
You: "Before I build this, let me confirm the approach:
     - Free users get rewards for referring? Or paid users only?
     - Reward currency: credits, extended access, or cash back?
     - Should I plan this first, or do you want MVP and iterate?"

[Wait for answers, THEN build]
```

**Don't build features without:**
- Clear requirements (what it should do)
- Strategic alignment (why we're building it)
- User approval (go ahead)

---

### Gate 2: During Implementation

**When:** User asks strategic question while you're coding
**Action:** Capture question, defer to end of session

**Example dialogue:**
```
User: [While you're fixing OAuth bug] "Hey, should the referral system reward free users or just paid users?"

You: "Good question. Let me capture this for discussion after I finish the OAuth fix:

     Strategic question for end of session:
     - Referral rewards: free users vs paid users
     - Related: Should free users unlock features by sharing (no payment)?

     For now, I'll finish the OAuth bug fix (5 min remaining), then we can discuss strategy."

[Return to tactical work, discuss strategy when code is done]
```

**Benefits:**
- Maintains coding momentum
- User gets thoughtful answer (not rushed)
- Decisions made with full context (not mid-bug-fix)

---

### Gate 3: After Feature Complete

**When:** Feature is built and tested
**Question:** "Ship, defer, or pivot?"

**Decision template:**
```markdown
## Feature Decision: [Feature Name]

**Status:** Built and tested

**What it does:**
[1-2 sentences]

**Time invested:**
[Estimate: hours or sessions]

**Strategic fit:**
- Primary goal: [Revenue? Growth? Retention?]
- Does this feature serve that goal? [Yes/No/Unclear]

**User validation:**
- Do we have signal this is needed? [Yes/No/Assumption]

**Decision options:**
1. **Ship:** Deploy to production now
2. **Defer:** Keep code, don't deploy (revisit when [trigger])
3. **Pivot:** Modify approach based on [new information]

**Recommendation:** [Ship/Defer/Pivot]
**Rationale:** [Why?]
```

**Example:**
```markdown
## Feature Decision: Stripe Payment + Referral System

**Status:** Built and tested

**What it does:**
One-time payments ($29.99), referral codes with viral rewards

**Time invested:** ~10 hours (multiple sessions)

**Strategic fit:**
- Primary goal: Viral growth for next season (not immediate revenue)
- Does this feature serve that goal? Unclear — scattered referrals vs concentrated community

**User validation:**
- Do we have signal this is needed? No — no users have asked for payment yet

**Decision options:**
1. **Ship:** Deploy payment system now
2. **Defer:** Keep code, don't deploy (revisit after Acme campaign provides usage data)
3. **Pivot:** Build Acme free promo instead (concentrated community > scattered referrals)

**Recommendation:** Defer payment, pivot to Acme promo
**Rationale:** Need usage data before optimizing viral mechanics. Concentrated community (Acme) provides better signal than scattered referrals.
```

---

## When to Use Each Gate

| Gate | Timing | Purpose | Example |
|------|--------|---------|---------|
| **Before Building** | User requests feature | Clarify requirements and get approval | "Should I build referral system for free users or paid?" |
| **During Implementation** | Mid-coding question | Capture and defer to end of session | "Let me finish OAuth fix, then discuss referral strategy" |
| **After Feature** | Feature complete | Ship/defer/pivot decision | "Referral built. Ship now or defer until usage data?" |

---

## Red Flags: When You're Violating the Protocol

1. **Building without approval** — "I'll just implement this and see if they like it"
2. **Strategic discussion mid-bug-fix** — Context thrashing, poor decisions
3. **Shipping without validation** — Feature complete ≠ feature validated
4. **Building deferred features** — Wasted effort, should have waited for signal

---

## Common Traps

### Trap 1: "Just build it, we'll decide later"
**Problem:** Builds momentum but risks wasted work
**Solution:** Quick 2-minute planning call before coding

### Trap 2: "Let's discuss strategy while building"
**Problem:** Neither coding nor strategy gets full attention
**Solution:** Finish current task, then discuss (mono-task)

### Trap 3: "Feature is done, ship it!"
**Problem:** No validation that feature serves strategic goal
**Solution:** After-feature decision gate (ship/defer/pivot)

---

## Integration with Shape Up

Shape Up already has decision gates:
- **Shaping:** Define appetite, sketch solution (Gate 1: Before Building)
- **Betting:** Approve or defer (Gate 1: Before Building)
- **Building:** Execute (Gates 2 & 3: During/After)

This protocol extends Shape Up to tactical sessions:
- Before building: "Is this approved and urgent?" (mini-shaping)
- During building: "Defer strategic questions" (focus)
- After building: "Ship/defer/pivot?" (mini-betting)

---

## Quick Reference

**Before building:**
- ✅ Ask: "Is this approved? Is this urgent?"
- ❌ Don't start coding on vague requests

**During implementation:**
- ✅ Capture strategic questions for later
- ❌ Don't stop coding to discuss strategy

**After feature:**
- ✅ Explicit ship/defer/pivot decision
- ❌ Don't auto-ship without validation

**Key principle:** Separate strategy (what to build) from tactics (how to build)
