# Feature Brief Template

**Purpose:** Frame the problem, sketch solution, get approval before building

## Brief Header

```markdown
# Feature Brief: [Feature Name]

**Status:** [Shaping / Approved / In Progress / Shipped / Deferred]
**Appetite:** [Small (1-2 sessions) / Medium (3-5 sessions) / Large (1-2 weeks)]
**Shaped by:** [Your name]
**Date:** YYYY-MM-DD
```

---

## 1. Problem

**What's the user problem or opportunity?**

[2-3 sentences describing what users can't do today or what opportunity we're missing]

**Who is this for?**
- [Primary user persona]
- [Use case or job to be done]

**How are they solving this today?**
- [Current workaround or competitor solution]

**What's the impact if we don't solve this?**
- [User frustration, lost revenue, competitive gap]

---

## 2. Appetite

**How much time is this worth?**

- [ ] **Small:** 1-2 sessions (a few hours)
- [ ] **Medium:** 3-5 sessions (1-2 days)
- [ ] **Large:** 1-2 weeks

**Why this appetite?**
[Rationale: strategic importance, complexity, urgency]

**Non-negotiables:**
[What must be included to solve the core problem]

**Nice-to-haves:**
[What can be cut if we run out of time]

---

## 3. Solution Sketch

**Core concept:**
[1-2 sentences describing the solution approach]

**User flow:**
1. [User does X]
2. [System responds with Y]
3. [User sees Z]
4. [Outcome: user accomplishes goal]

**Key UI elements:**
- [Element 1: what it does]
- [Element 2: what it does]
- [Element 3: what it does]

**Fat-marker sketch:**
[Rough mockup or description — breadboard level, not pixel-perfect]

**Alternative approaches considered:**
- [Approach A: why rejected]
- [Approach B: why rejected]

**Why this approach:**
[Rationale: fits appetite, solves core problem, build on existing work]

---

## 4. Rabbit Holes & No-Gos

**Rabbit holes to avoid:**
- [Complexity 1: scope boundary to prevent]
- [Complexity 2: scope boundary to prevent]
- [Complexity 3: scope boundary to prevent]

**Out of scope:**
- [Feature X: defer to later]
- [Feature Y: not solving this time]

**Dependencies:**
[What needs to exist before this can be built]

**Assumptions:**
[What we're assuming is true — validate before building]

---

## 5. Technical Approach

**Data model changes:**
[New tables, columns, or schema changes]

**API changes:**
[New endpoints or modifications]

**UI components:**
[New components or modifications]

**Third-party services:**
[External APIs, libraries, or services needed]

**Migration plan:**
[If changing existing behavior, how do we migrate users?]

---

## 6. Open Questions

**Before approval:**
- [ ] [Question 1: needs answer before building]
- [ ] [Question 2: needs answer before building]

**Can answer during build:**
- [ ] [Question A: can discover while implementing]
- [ ] [Question B: can discover while implementing]

---

## 7. Success Criteria

**How will we know this worked?**

**Qualitative:**
- [User can now accomplish X without workaround]
- [User feedback indicates Y]

**Quantitative:**
- [Metric 1: target value]
- [Metric 2: target value]

**Ship decision:**
- [ ] Core problem solved
- [ ] Works on mobile + desktop
- [ ] No breaking changes to existing features
- [ ] [Other criteria]

---

## 8. Implementation Notes

**This section filled in during/after building**

**What was built:**
[Actual implementation — may differ from sketch]

**What changed from sketch:**
[Discoveries that changed approach]

**What was cut:**
[Nice-to-haves that were descoped]

**Lessons learned:**
[What worked, what didn't, what to remember]

---

## Example Brief

# Feature Brief: Acme Partnership Landing Page

**Status:** Shipped
**Appetite:** Medium (3-5 sessions)
**Shaped by:** Claude
**Date:** 2026-02-06

## 1. Problem

**What's the user problem?**
Acme Widgets parents need to track their team schedules at competitions. We have 69 Acme teams in database, but users don't know we exist yet.

**Who is this for?**
- Acme Widgets parents (Springfield, Griffin, etc.)
- Use case: Track my team's performance times at upcoming competition

**How are they solving this today?**
- Checking printed schedules or competition app
- Manual notifications from coaches
- Missing schedule changes

**Impact if we don't solve:**
- Miss opportunity for concentrated community launch
- Slower user growth (scattered vs focused)

## 2. Appetite

**Time worth:** Medium (3-5 sessions)

**Why:** Strategic pilot for viral growth. Acme community provides:
- Built-in network effects (parents share with other parents)
- Real usage data (inform future features)
- Proof of concept (test core value prop)

**Non-negotiables:**
- Custom landing page at `/one-of-a-kind`
- Team selection (filter to Acme teams)
- Free premium access (no payment)

**Nice-to-haves:**
- Google OAuth (start with email/password)
- City filtering (if time allows)
- Custom branding (if time allows)

## 3. Solution Sketch

**Core concept:**
Dedicated landing page for Acme members. Sign up → auto-grant premium → redirect to app with teams pre-selected.

**User flow:**
1. User visits `/one-of-a-kind` (shared link)
2. Selects city (Springfield, Griffin, etc.)
3. Picks teams to follow (checkboxes)
4. Signs up (email/password)
5. Redirected to app with premium + teams selected

**Key UI elements:**
- Hero: "Acme Widgets: Track your teams free"
- City dropdown (reduces 69 teams to ~20 per city)
- Team checkboxes (multi-select)
- Sign up form (email, password, name)

**Alternative approaches:**
- Generic promo code: Too easy to leak, no targeting
- Email verification: Friction, Acme doesn't give us emails
- Payment with discount: Defeats "free" messaging

**Why this approach:**
- Link-based (easy to share)
- Pre-filters to Acme (focused UX)
- No verification friction (maximize signups)

## 4. Rabbit Holes & No-Gos

**Rabbit holes:**
- Email verification (trust link distribution)
- Complex team name matching (use exact strings from DB)
- Custom team profiles (defer to later)

**Out of scope:**
- Payment integration (free premium)
- Team manager roles (defer)
- Analytics dashboard (event logging sufficient)

**Dependencies:**
- Teams table populated with Acme teams ✅
- Subscriptions table exists ✅
- Premium grant API endpoint (build this)

**Assumptions:**
- Acme will share link with community
- Parents will sign up (link distribution = validation)

## 5. Technical Approach

**Data model:**
- `subscriptions` table: Add row with `source='acme_partner'`, `price_paid_cents=0`
- `expires_at='2026-04-30'` (end of season)

**API:**
- New endpoint: `/api/acme/grant-premium`
- Input: user token, team selections
- Output: subscription created

**UI:**
- New page: `web/one-of-a-kind.html`
- New script: `web/acme.js`
- Team data: Filter from `schedule.json` or Supabase

**Migration:** None (new feature)

## 6. Open Questions

**Before approval:**
- [x] Expiration date: Rest of season (Apr 30) or full year? → Rest of season
- [x] City filtering: Required or nice-to-have? → Build it (reduces overwhelming list)

**During build:**
- [ ] Google OAuth: Add if time allows
- [ ] Custom branding: Acme colors or Example Project brand? → Example Project brand

## 7. Success Criteria

**Qualitative:**
- Acme parents can sign up in <2 minutes
- Team selection is clear (city filter helps)
- Redirects to app with teams pre-loaded

**Quantitative:**
- >10 signups in first week (validation)
- >50% select >1 team (engagement)

**Ship decision:**
- [x] Can sign up and get premium
- [x] Teams selected carry over to app
- [x] Mobile responsive
- [x] No payment required

## 8. Implementation Notes

**What was built:**
- Landing page with dual flow (new user + existing user)
- City filtering (auto-skip for single-city gyms)
- "Other team" option (text input for unlisted teams)
- Google OAuth (added during build)
- SessionStorage bridge (prevent premium flicker)

**What changed:**
- Added Google OAuth (nice-to-have became must-have)
- Added existing user flow (users who signed up via main app)
- Added name validation (prevent default "Acme Member")

**What was cut:**
- Custom Acme branding (used Example Project brand)
- Email collection for marketing (just auth emails)

**Lessons learned:**
- City filtering crucial (69 teams overwhelming)
- OAuth added complexity but worth it (seamless for existing users)
- SessionStorage bridge pattern works well (reuse for other redirects)
