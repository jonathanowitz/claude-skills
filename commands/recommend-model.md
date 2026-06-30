# Model Recommendation

Analyze the current conversation context and any planned work, then recommend the most appropriate model.

## Instructions

Review the conversation to understand:
1. What has been discussed or worked on
2. What tasks are planned or requested
3. The complexity and nature of the work

Then recommend one of these models with clear reasoning:

### Model Options

**haiku** - Fast, low-cost, good for:
- File searches and exploration
- Simple edits (typos, small fixes, formatting)
- Straightforward code generation with clear specs
- Running commands and reporting results
- Summarization tasks

**sonnet** - Balanced, good for:
- Most coding tasks (features, bug fixes, refactoring)
- Code review and analysis
- Test writing
- Documentation
- Multi-file changes with clear patterns

**opus** - Most capable, use for:
- Complex architectural decisions
- Nuanced problem-solving requiring deep reasoning
- Ambiguous requirements needing interpretation
- Novel problems without clear patterns
- Multi-step planning with many dependencies
- Code review where subtle issues matter

## Output Format

```
## Recommendation: [model]

**Why:** [1-2 sentence explanation]

**Task summary:** [Brief description of what you understand needs to be done]

**If you need more capability:** [When to upgrade]
**If you want to save tokens:** [When to downgrade, if applicable]
```

## Example Recommendations

- "Fix the typo in README.md" → **haiku** (simple text edit)
- "Add input validation to the login form" → **sonnet** (standard coding task)
- "Design the authentication architecture for our microservices" → **opus** (complex architecture)
- "Search for all usages of the User class" → **haiku** (file exploration)
- "Refactor the payment module to use the new API" → **sonnet** or **opus** depending on scope
