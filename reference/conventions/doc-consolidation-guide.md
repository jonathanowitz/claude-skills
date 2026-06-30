# Documentation Consolidation Guide

**Goal:** Keep docs lean (<10 files), reduce redundancy, maintain single source of truth

## Recommended Structure

### For Web Apps / SaaS Projects

```
docs/
├── README.md           # Project overview, quick start, architecture overview
├── DEPLOYMENT.md       # How to deploy (env vars, services, testing)
├── DEVELOPMENT.md      # How to develop (local setup, debugging, workflows)
├── ARCHITECTURE.md     # Technical design (schema, APIs, data flow, decisions)
├── TESTING.md          # How to test (manual tests, SQL queries, debugging)
├── FEATURES.md         # Feature flags, campaigns, toggles
└── CHANGELOG.md        # What changed when (links to releases/tags)
```

**Total: 7 core files**

### For Libraries / Tools

```
docs/
├── README.md           # What it does, installation, basic usage
├── API.md              # Complete API reference
├── EXAMPLES.md         # Usage examples, common patterns
├── CONTRIBUTING.md     # How to contribute, development setup
└── CHANGELOG.md        # Version history
```

**Total: 5 core files**

---

## Consolidation Mapping

**Common file sprawl:** 20+ files with overlapping content
**Solution:** Merge into 6-7 core files

### Example: Example Project Project

**Before (20+ files):**
```
DEPLOYMENT.md
DEPLOYMENT-CHECKLIST.md
PRE_LAUNCH_CHECKLIST.md
MANUAL-TEST-CASES.md
ENVIRONMENT-VARIABLES-SETUP.md
VERCEL-ENV-VARS-SETUP.md
LOGGING-SETUP.md
FEATURE_TOGGLES.md
SECURITY-AUDIT-RESULTS.md
TEST-USER-MANAGEMENT.md
KNOWN-ISSUES.md
NEXT-STEPS-STRIPE-OPTIONAL.md
database-brief.md
onboarding-rewrite-brief.md
email-setup-guide.md
day0-privacy-inventory.md
privacy-launch-checklist.md
brand-guidelines.md
IMPLEMENTATION_SUMMARY.md
ACME-IMPLEMENTATION-COMPLETE.md
ACME-FIXES-AND-API-ISSUE.md
```

**After (6 files):**
```
docs/
├── README.md           # Overview, quick start
├── DEPLOYMENT.md       # Env vars, Vercel, Stripe, testing checklist, logging
├── ARCHITECTURE.md     # Schema, API routes, data flow, tech stack
├── TESTING.md          # Manual tests, SQL queries, known issues, debugging
├── FEATURES.md         # Feature toggles, Acme campaign, promo campaigns
└── BRIEFS.md           # Design decisions: DB, onboarding, brand, privacy
```

**Consolidation:**
- **DEPLOYMENT.md** ← DEPLOYMENT-CHECKLIST, PRE_LAUNCH_CHECKLIST, ENVIRONMENT-VARIABLES-SETUP, VERCEL-ENV-VARS-SETUP, LOGGING-SETUP
- **TESTING.md** ← MANUAL-TEST-CASES, TEST-USER-MANAGEMENT, SECURITY-AUDIT-RESULTS, KNOWN-ISSUES
- **FEATURES.md** ← FEATURE_TOGGLES, NEXT-STEPS-STRIPE-OPTIONAL, ACME-IMPLEMENTATION-COMPLETE
- **BRIEFS.md** ← database-brief, onboarding-rewrite-brief, brand-guidelines, day0-privacy-inventory, privacy-launch-checklist, email-setup-guide
- **DELETE** ← ACME-FIXES-AND-API-ISSUE (bugs now fixed), IMPLEMENTATION_SUMMARY (now in git tags)

---

## Consolidation Process

### Step 1: Audit Current Docs

Create inventory:
```markdown
| File | Purpose | Overlap With | Keep/Merge/Delete |
|------|---------|--------------|-------------------|
| DEPLOYMENT.md | How to deploy | DEPLOYMENT-CHECKLIST | Merge |
| DEPLOYMENT-CHECKLIST.md | Pre-launch tests | DEPLOYMENT.md | Merge → DEPLOYMENT.md |
| ACME-FIXES.md | Bug fixes | (Bugs now fixed) | Delete |
```

### Step 2: Identify Core Categories

Typical categories:
- **Setup** (README, installation, quick start)
- **Development** (local dev, debugging, workflows)
- **Deployment** (env vars, services, checklists)
- **Architecture** (schema, APIs, decisions)
- **Testing** (manual tests, debugging, issues)
- **Features** (flags, campaigns, experiments)
- **History** (changelog, decisions, briefs)

### Step 3: Merge Related Files

**Example: Deployment**

Merge these:
- DEPLOYMENT.md (how to deploy)
- DEPLOYMENT-CHECKLIST.md (pre-launch steps)
- ENVIRONMENT-VARIABLES-SETUP.md (env vars)
- VERCEL-ENV-VARS-SETUP.md (Vercel specifics)
- LOGGING-SETUP.md (logging config)

Into one file:
```markdown
# Deployment Guide

## Prerequisites
[Quick checklist]

## Environment Variables
[Comprehensive env var guide]

## Vercel Setup
[Vercel-specific steps]

## Logging Configuration
[Event logging setup]

## Pre-Launch Checklist
[Final validation steps]

## Troubleshooting
[Common issues]
```

### Step 4: Delete Obsolete Files

**Delete when:**
- ✅ Bug is fixed (move to CHANGELOG or TESTING.md "Fixed Issues")
- ✅ Feature is complete (move to CHANGELOG)
- ✅ Implementation is done (decisions → ARCHITECTURE.md, delete play-by-play)
- ✅ Information is redundant (already in code, schema, or git)

**Archive when:**
- One-time reports (security audits, performance tests)
- Historical context (session summaries >30 days old)
- Reference material (might be useful later, but not active)

**Archive location:** `~/.claude/archive/project-name/YYYY-MM/`

### Step 5: Create Index (README.md)

```markdown
# Project Name

[Overview paragraph]

## Quick Start
[3-5 commands to get running]

## Documentation

- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** — How to deploy and configure
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — Technical design and decisions
- **[TESTING.md](docs/TESTING.md)** — How to test and debug
- **[FEATURES.md](docs/FEATURES.md)** — Feature flags and campaigns
- **[BRIEFS.md](docs/BRIEFS.md)** — Design decisions and briefs

## Project Status
[Current state, what's working, what's next]
```

---

## Best Practices

### 1. Single Source of Truth

**Bad:**
- Database schema in 3 places (database-brief.md, ARCHITECTURE.md, README.md)
- Deployment steps in 4 files (DEPLOYMENT.md, checklist, Vercel guide, env var guide)

**Good:**
- Schema lives in `migrations/` (canonical), referenced in ARCHITECTURE.md
- Deployment steps in one file (DEPLOYMENT.md), subsections for details

### 2. Link, Don't Copy

**Bad:**
```markdown
## Environment Variables

SUPABASE_URL=https://...
SUPABASE_ANON_KEY=eyJ...
STRIPE_SECRET_KEY=sk_...
[... full .env file copied]
```

**Good:**
```markdown
## Environment Variables

See `.env.example` for complete list.

Key variables:
- `SUPABASE_URL` — Supabase project URL (Dashboard → Settings → API)
- `STRIPE_SECRET_KEY` — Stripe secret key (Dashboard → Developers → API keys)

Add to Vercel: Settings → Environment Variables
```

### 3. Evergreen Over Temporal

**Bad:** Create new file for every change
```
ACME-IMPLEMENTATION.md          (Feb 6 AM)
ACME-FIXES.md                   (Feb 6 PM, same day)
ACME-OAUTH-FIXES.md             (Feb 6 PM, later)
```

**Good:** Update existing file
```
docs/FEATURES.md
  ## Acme Partnership Campaign
  [All Acme info in one place, updated as needed]
```

### 4. Delete Fearlessly

Git history preserves everything. Don't hoard obsolete docs.

**Safe to delete:**
- Fixed bug reports → Move to CHANGELOG "Fixed" section
- Completed migrations → Already in `migrations/` directory
- Implementation summaries → Already in git log
- Duplicate content → Keep best version, delete others

**How to verify before deleting:**
```bash
# Check git history to confirm info is preserved
git log --all --full-history -- path/to/file.md

# If file has useful content, extract to appropriate doc first
# Then delete the file
git rm docs/obsolete-file.md
```

---

## Anti-Patterns

### 1. Documentation as Thinking Tool

**Problem:** Creating docs while figuring things out, never cleaning up

**Example:**
```
STRIPE-EXPLORATION.md
STRIPE-IMPLEMENTATION-NOTES.md
STRIPE-IMPLEMENTATION-SUMMARY.md
STRIPE-COMPLETE.md
```

**Solution:**
- Use scratch files (not committed): `scratch/stripe-notes.md`
- Or commit but delete after extracting decisions
- Final state: One section in ARCHITECTURE.md or FEATURES.md

### 2. Timestamp-Based Files

**Problem:** Files named by date/time, not content

**Example:**
```
session-2026-02-05-notes.md
acme-fixes-2026-02-06.md
bug-report-feb-6.md
```

**Solution:**
- Sessions go in `~/.claude/sessions/` (expected to be temporal)
- Project docs use topic names (FEATURES.md, TESTING.md)
- Bugs go in TESTING.md "Known Issues" section, moved to "Fixed" when resolved

### 3. Copy-Paste Redundancy

**Problem:** Same information in multiple files (maintenance burden)

**Example:**
- Supabase setup in: README.md, DEPLOYMENT.md, database-brief.md, ARCHITECTURE.md
- (Each copy slightly different, becomes outdated)

**Solution:**
- Canonical location: DEPLOYMENT.md "Supabase Setup" section
- Others link to it: "See [DEPLOYMENT.md#supabase-setup](DEPLOYMENT.md#supabase-setup)"

---

## Maintenance

### Weekly
- Scan for new .md files in project root
- Merge into appropriate core doc or delete
- Update CHANGELOG with completed work

### Monthly
- Review all docs for accuracy
- Delete obsolete sections
- Archive old session summaries (>30 days) to `~/.claude/archive/`

### Per Feature
- After feature complete: Extract decisions to ARCHITECTURE.md or BRIEFS.md
- Delete implementation notes, bug reports (move to CHANGELOG)
- Update relevant core doc (FEATURES.md, DEPLOYMENT.md, etc.)

---

## Quick Reference

**Project has >10 .md files?** → Time to consolidate
**Two files cover same topic?** → Merge them
**File hasn't been updated in 30+ days?** → Archive or delete
**Information already in code/schema/git?** → Delete doc, link to source
**Creating new doc?** → Ask: "Could this be a section in existing doc?"

**Golden rule:** Prefer updating existing docs over creating new ones
