# Customer.io MCP — Workflow Recipes

**Source:** Shared by a Customer.io PM on the AI automation team (received 2026-05-14). Five common workflows to try with the MCP, plus patterns worth knowing.

**Related:** For API quirks and silent-fail gotchas discovered in practice, see [`customerio-api-gotchas.md`](customerio-api-gotchas.md).

The MCP lets Claude Code talk directly to the Customer.io workspace from the terminal — same access as the in-product agent, with the bonus of seeing local files. Recipes below build on each other; rough order: tokens first, then components, then composing emails from them.

---

## 1. Push the brand system into Customer.io as design tokens

**Why:** Claude reads local brand files and writes the same colors, fonts, and spacing into Customer.io's global styles. Every future email composed in Design Studio auto-references them, so the brand doesn't get redefined per email.

**Prompt:**
> Read my brand system files (paths: list yours, e.g. `~/context/brand-system/color-palette.md`, `typography.md`) and push my design tokens into my Customer.io workspace's global styles. Use the same names I use in code so I can reference them naturally later. Read-modify-write so you don't blow away the existing structure.

**What should happen:**
- Claude lists what tokens it found and proposes the mapping
- Calls the MCP to write them into the workspace
- Reads back to confirm everything landed

**Verify:** Open Customer.io → Design Studio → Styles. The color names, font, and spacing scale should appear in the token palette.

---

## 2. Build a brand component library

**Why:** Custom components are Lego blocks. Once `<my-header>`, `<my-cta>`, `<my-footer>` exist in the workspace, Claude can compose emails by referencing them rather than re-styling from scratch. Updates to a component flow into every email that uses it.

**Prompt:**
> Look at my brand system and the kinds of emails I'm likely to send (transactional welcome, schedule updates, premium upsell, etc.). Propose 4–6 reusable email components, then build them in my Customer.io workspace as custom components. Use my brand tokens. After creating, validate they render correctly by composing a test email that uses all of them.

**What should happen:**
- Claude proposes a component set with rationale and asks to confirm or tweak
- Creates each as a component node in Design Studio
- Builds a demo email that uses every component
- Renders the demo to confirm components actually expand (not literal `<my-header />` tags)

**Verify:** Open Design Studio → Components. The library should be visible. Open the demo email to see them composed.

---

## 3. Generate an email from brand context

**Why:** Skip the "Claude builds HTML, I copy it into Customer.io, fix the unsubscribe link, fix the Liquid syntax" loop. Claude builds it directly inside Customer.io, using tokens and components, with the right unsubscribe link and Liquid baked in.

**Prompt:**
> Build a transactional email for [purpose — e.g. welcome when someone unlocks the premium tier]. Use my brand components for the header, button, and footer. Save it as a template in my Customer.io workspace. Make sure the unsubscribe link uses Customer.io's `{% unsubscribe_url %}` syntax (not Resend's), and that any Liquid variables match what's actually available for this message type.

**What should happen:**
- Claude looks up the available variables via the MCP — no guessing
- Writes markup using components
- Saves as a template in Design Studio
- Renders to confirm and shares the editor link

**Verify:** Customer.io → Design Studio → Templates. Open it, send a test send.

---

## 4. Restyle an existing email to match the brand

**Why:** If a repo has an email file still using legacy inline styles or old colors, Claude can read it, map the styles to brand tokens, and either update the file in place or push it into Customer.io as a template.

**Prompt:**
> Read `[path/to/email-file]` and rewrite the inline styles using my brand system. Keep the copy verbatim — only change visual styling. Show me a side-by-side before/after preview in my browser before applying. If I approve, update the file in place.

**What should happen:**
- Claude reads the file and the brand tokens
- Generates a preview HTML and opens it locally
- Applies the change after approval

**Verify:** The browser preview tells whether the new version actually feels like the brand.

---

## 5. Trigger a test transactional or campaign send

**Why:** When sending via the MCP, Claude looks up the actual schema (subject template, available Liquid variables, layout) before sending. No more guessing whether it's `customer.first_name` or `user.firstName`.

**Prompt:**
> Send a test of transactional `[name or ID]` to me at `[email]`. Use this sample message data: `[variables you want to test]`. Watch the delivery and confirm the state hits "sent".

**What should happen:**
- Claude queries the transactional via MCP for its schema
- Triggers the send with the correct variable shape
- Polls delivery state until it's sent (or fails with a clear reason)

**Verify:** Email lands in inbox. Delivery state in Customer.io shows "sent".

---

## Patterns worth knowing

- **Always ask Claude to validate by rendering.** A successful API call doesn't mean the markup rendered. Adding "and confirm the rendered HTML isn't empty" to a prompt catches silent failures.
- **Read-modify-write for tokens.** Replacing the global styles object outright will fail — Customer.io validates internal metadata. Fetch existing first and modify in place.
- **Use the MCP for schema lookups.** When unclear what variables are available, ask Claude to ask Customer.io directly. Faster than trial and error.
