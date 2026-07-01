---
name: understand-open-source
description: "Deeply understand any open-source repo. Downloads its real source with opensrc, builds a code graph with graphify, uses the graph to find the parts that matter, READS the actual code for those parts, and produces an HTML breakdown report for you. Use when you want to truly understand how a library/repo works — not skim its docs. Pass the repo name as the argument."
---

# Understand Open Source

Turn any open-source repo into a deep, accurate understanding — and a shareable
HTML report — in one pass. You download the repo's **real source code** (not just
docs), build a **graph of how the code connects**, let the graph point you at the
parts that actually matter, then **read those real files** and explain how the
whole thing works.

The argument is the **repo name** to understand:

```
/understand-open-source <repo-name>
```

Examples: `/understand-open-source zod` · `/understand-open-source react` ·
`/understand-open-source github:vercel-labs/opensrc` · `/understand-open-source pypi:requests`

`$ARGUMENTS` is the repo name the user passed. Use it everywhere below as `<repo>`.

---

## Dependencies (check these FIRST)

Before doing anything, confirm both tools are installed. If either is missing,
tell the user the install command and stop.

1. **opensrc** (vercel-labs/opensrc) — fetches the real source of a package/repo.
   ```bash
   command -v opensrc >/dev/null || echo "MISSING: install with  npm install -g opensrc"
   ```
2. **graphify** — builds a navigable code graph and report.
   ```bash
   command -v graphify >/dev/null || echo "MISSING: install graphify (see graphify docs)"
   ```

Do not proceed until both resolve.

---

## Step 1 — Download the real source with opensrc

`opensrc path` fetches the source on first use and prints the local cached
directory (instant on repeat). Capture that path.

```bash
SRC=$(opensrc path "$ARGUMENTS")
echo "Source downloaded to: $SRC"
ls "$SRC"
```

`opensrc` accepts npm names by default and registry prefixes for others
(`pypi:<pkg>`, `crates.io`, `github:<owner>/<repo>`). Pass the user's repo name
straight through.

> Why this matters: you now have the project's **actual implementation files** on
> disk — the ground truth — not a summary, not the README.

---

## Step 2 — Build the code graph with graphify

Run graphify over the downloaded source to extract entities and how they connect.
This is AST-based (no API cost).

```bash
graphify update "$SRC"
```

This writes `graphify-out/` (next to where you run it) containing:
- `graphify-out/GRAPH_REPORT.md` — god nodes (most-connected/central code) +
  community structure (how the codebase clusters into subsystems)
- `graphify-out/graph.json` — the graph the query commands traverse
- `graphify-out/wiki/` — navigable per-area notes (if generated)

If the report looks empty or stale, regenerate clustering with
`graphify cluster-only "$SRC"`.

---

## Step 3 — Use the graph to find the parts that matter

**Read `graphify-out/GRAPH_REPORT.md` first.** The god nodes and communities tell
you where the important code lives so you don't waste time reading everything.

Then traverse the graph to answer the specific structural questions:

```bash
graphify query "what are the core modules and how do they depend on each other?"
graphify explain "<a god-node or key entity from the report>"
graphify path "<entry point>" "<core abstraction>"
```

Build a shortlist of the **5–12 most important files/symbols** the graph surfaces:
the entry points, the central abstractions (god nodes), and one representative
file per major community/subsystem.

> The graph is the map, not the territory. It tells you WHERE to look. It does not
> replace reading the code.

---

## Step 4 — READ THE ACTUAL CODE (this is the point)

For every item on the Step 3 shortlist, open and **read the real source files**
inside `$SRC`. This is where the real understanding happens — the graph pointed
you at the interesting parts; now read them.

```bash
cat "$SRC/<path-the-graph-pointed-at>"
```

For each file you read, capture: what it does, the key functions/types, the
control/data flow, and how it connects to the other shortlisted parts (use what
the graph told you about its neighbors). Read enough real code to explain the
repo's architecture from the inside, not from its docs.

---

## Step 5 — Generate the HTML breakdown

Produce a single self-contained `understanding-<repo>.html` report. Write it from
what you learned reading the real code in Step 4, structured by what the graph
revealed in Step 3.

Sections:
1. **What this repo is** — one-paragraph plain-English summary.
2. **Architecture at a glance** — the major subsystems (from graph communities)
   and how they connect.
3. **The core abstractions** — the god nodes / central files, what each does,
   with short real code excerpts from `$SRC`.
4. **How a typical flow works** — trace one important path end-to-end through the
   real files (e.g. input → parse → core → output).
5. **Where to start if you want to contribute / extend it** — the 3–5 files that
   matter most and why.

Keep it self-contained (inline CSS, no external assets) so it opens anywhere.
Save it to the current working directory.

```bash
echo "Report written to: $(pwd)/understanding-$(echo "$ARGUMENTS" | tr '/:' '__').html"
```

---

## Step 6 — Deliver it to the user

Hand the finished HTML back to the user:
- Tell them the path to `understanding-<repo>.html` and that they can open it in a
  browser.
- Give a 3–4 line spoken-friendly summary of the single most useful thing you
  learned about how the repo actually works.

---

## The one rule

The graph (graphify) finds the interesting parts. Reading the real downloaded code
(opensrc) is what actually makes you understand the repo. Always do both, in that
order. Never write the breakdown from the README or the graph alone.
