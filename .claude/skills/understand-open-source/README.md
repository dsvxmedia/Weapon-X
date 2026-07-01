# understand-open-source

A Claude Code skill that gives you a **deep, accurate understanding of any
open-source repo** — and a shareable HTML report — in one command.

Most people "understand" a library by skimming its README. This reads the **real
source code**. It downloads the repo's actual implementation, builds a graph of
how the code connects, uses that graph to find the parts that actually matter,
then **reads those real files** and writes up how the whole thing works.

## How it works

```
/understand-open-source <repo-name>
```

1. **Download the real source** with [opensrc](https://github.com/vercel-labs/opensrc)
   — the actual implementation files, not the docs.
2. **Build a code graph** with graphify — entities + how they connect.
3. **Find the parts that matter** — the graph surfaces the central code (god
   nodes) and subsystems so you don't read everything.
4. **Read the real code** for those parts — this is where the understanding
   actually happens.
5. **Get an HTML breakdown** — architecture, core abstractions with real code
   excerpts, a traced end-to-end flow, and where to start contributing.

## Install

You need two tools installed first:

```bash
# 1. opensrc — fetches real source for npm / PyPI / GitHub repos
npm install -g opensrc

# 2. graphify — builds the navigable code graph
#    (see graphify install docs)
```

Then drop `SKILL.md` into your Claude Code skills directory
(`.claude/skills/understand-open-source/SKILL.md`) and invoke it with
`/understand-open-source <repo-name>`.

## Example

```
/understand-open-source zod
```

→ downloads zod's source, graphs it, reads the core parser/type files the graph
points at, and writes `understanding-zod.html` you can open in any browser.

---

The graph finds the interesting parts. Reading the real code is what makes you
understand it. This skill always does both, in that order.
