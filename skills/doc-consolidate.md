# doc-consolidate

Consolidate project documentation to reduce file count and redundancy.

## Usage

```
/doc-consolidate
```

## What This Does

1. **Audit current docs** - Lists all .md files in project root and docs/
2. **Identify redundancy** - Flags overlapping content
3. **Propose consolidation** - Maps files to 6-7 core docs
4. **Execute merge** - Consolidates files with user approval
5. **Clean up** - Deletes obsolete files, creates docs/ directory

## Process

### Step 1: Audit
```
Scanning documentation files...

Found 23 .md files:
- DEPLOYMENT.md (3.2 KB)
- DEPLOYMENT-CHECKLIST.md (1.8 KB) [OVERLAP: DEPLOYMENT.md]
- PRE_LAUNCH_CHECKLIST.md (2.1 KB) [OVERLAP: DEPLOYMENT.md]
- database-brief.md (6.0 KB)
- onboarding-rewrite-brief.md (9.9 KB)
[...]
```

### Step 2: Propose Structure
```
Recommended consolidation (23 → 6 files):

docs/README.md
  ← Current README.md (if exists)

docs/DEPLOYMENT.md
  ← DEPLOYMENT.md
  ← DEPLOYMENT-CHECKLIST.md (merge as section)
  ← PRE_LAUNCH_CHECKLIST.md (merge as section)
  ← ENVIRONMENT-VARIABLES-SETUP.md (merge as section)

docs/TESTING.md
  ← MANUAL-TEST-CASES.md
  ← TEST-USER-MANAGEMENT.md (merge as section)
  ← KNOWN-ISSUES.md (merge as section)

docs/ARCHITECTURE.md
  ← (New file: technical design, schema, APIs)

docs/FEATURES.md
  ← FEATURE_TOGGLES.md
  ← ACME-IMPLEMENTATION-COMPLETE.md (merge as section)

docs/BRIEFS.md
  ← database-brief.md
  ← onboarding-rewrite-brief.md
  ← brand-guidelines.md

DELETE:
  - ACME-FIXES-AND-API-ISSUE.md (bugs now fixed)
  - IMPLEMENTATION_SUMMARY.md (details in git log)
  - archive/* (move to ~/.claude/archive/project-name/)

Proceed with consolidation? [y/N]
```

### Step 3: Execute
Creates `docs/` directory, merges files, updates cross-references, deletes obsolete files.

### Step 4: Verify
- Confirms all content preserved
- Checks for broken links
- Creates docs/README.md index

## Configuration

**Customize via prompts:**
- Skip certain files: "Skip CHANGELOG.md, keep as-is"
- Custom structure: "Merge FEATURES.md into ARCHITECTURE.md"
- Archive location: "Archive to ~/archive/project/ instead of ~/.claude/archive/"

## Output

- docs/ directory with consolidated files
- Archive of originals in ~/.claude/archive/project-name/YYYY-MM-DD/
- Summary of changes (files merged, deleted, created)

## When to Use

- Project has >10 .md files
- Redundant content across files (e.g., deployment in 3 places)
- Hard to find information (unclear which file to check)
- Before shipping (clean documentation for handoff)

## Related

- Reference: `~/.claude/references/doc-consolidation-guide.md`
- Skill: `/file-cleanup` (organizes source code, not docs)
