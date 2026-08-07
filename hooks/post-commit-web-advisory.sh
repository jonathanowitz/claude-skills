#!/bin/bash
# Fires after commits that touch web/ — reminds the agent to capture evidence
# before PR creation. Non-blocking: exits 0 always.
CHANGED=$(git diff HEAD~1 HEAD --name-only 2>/dev/null | grep -c '^web/' || true)
if [ "$CHANGED" -gt 0 ]; then
  echo "[ADVISORY] Web files committed. If you haven't yet, run:"
  echo "  node tools/agent-browse.mjs screenshot <name>"
  echo "  before \`gh pr create\` to satisfy the verification evidence gate."
fi
exit 0
