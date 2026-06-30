# file-cleanup

Organize project files into clear directory structure (src/, docs/, data/).

## Usage

```
/file-cleanup
```

## What This Does

1. **Scan project root** - Lists files and directories
2. **Categorize files** - Source code, docs, data, temp files
3. **Propose structure** - src/, docs/, data/ organization
4. **Execute moves** - Reorganizes with user approval
5. **Update references** - Fixes imports, links, configs

## Process

### Step 1: Scan
```
Scanning project root...

Found:
- 43 files in root (expected: <10)
- Mixed: code, docs, data, images
- Temporary files: test-config.html, *.JPG

Recommended: Organize into src/, docs/, data/
Proceed? [y/N]
```

### Step 2: Categorize
```
Source code (→ src/):
  web/*.html, web/*.js, web/*.css
  api/**/*.js
  cli/*.py

Documentation (→ docs/):
  *.md files (will be consolidated first)

Data (→ data/):
  data/schedule.json → data/seed/schedule.json
  *.pdf → data/source/*.pdf
  *.JPG → data/source/*.JPG

Configuration (stays in root):
  .env.example, .gitignore, package.json, vercel.json

Temporary files (DELETE):
  test-config.html (committed by mistake)
  Example Project logo - temp.png (move to data/assets/logo.png)

Archive (→ ~/.claude/archive/project-name/):
  archive/* directory
```

### Step 3: Propose Structure
```
Proposed structure:

project/
├── src/
│   ├── web/          (← web/)
│   ├── api/          (← api/)
│   └── cli/          (← cli/)
├── docs/
│   └── [consolidated docs]
├── data/
│   ├── seed/         (← data/schedule.json)
│   ├── source/       (← PDFs, images)
│   └── assets/       (← logo, brand assets)
├── migrations/       (unchanged)
├── .env.example      (unchanged)
├── .gitignore        (updated: src/*, docs/*)
├── package.json      (updated: paths)
├── vercel.json       (updated: routes)
└── README.md         (updated: structure docs)

Proceed? [y/N]
```

### Step 4: Execute
- Creates directories
- Moves files
- Updates imports/references
- Updates config files (vercel.json, package.json)
- Updates documentation links
- Git commits: "Reorganize project structure"

### Step 5: Verify
- Confirms all imports still work
- Checks for broken links
- Runs basic smoke test (if available)

## Configuration

**Customize via prompts:**
- Skip directories: "Keep web/ in root, don't move to src/"
- Custom structure: "Create lib/ for shared code"
- Preserve paths: "Don't update package.json, I'll do it manually"

## Output

- Organized directory structure
- Updated configuration files
- Git commit with file moves
- Summary of changes

## When to Use

- Project root has >20 files (should have <10)
- Mixed concerns (code, docs, data) in root
- Hard to find files (unclear organization)
- Before shipping (clean structure for handoff)

## Common Structures

### Web App (Full-Stack)
```
src/
  web/      # Frontend
  api/      # Backend
  cli/      # Scripts
docs/       # Documentation
data/       # Seed data, assets
migrations/ # Database
```

### Library/Package
```
src/        # Source code
lib/        # Built output (gitignored)
docs/       # Documentation
test/       # Tests
examples/   # Usage examples
```

### CLI Tool
```
src/        # Source code
bin/        # Entry point scripts
docs/       # Documentation
test/       # Tests
```

## Related

- Skill: `/doc-consolidate` (organize documentation)
- Reference: `~/.claude/references/project-folder-structure.md`
