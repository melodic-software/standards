# Progressive disclosure

Layer information so the reader — human or agent — gets the cheapest useful glance first and drills to detail only on demand. An always-loaded surface pays its whole size on every read, even when a one-line index would have settled the question; layering moves that cost to the point of demand. This is a reasoning-only discipline: where to draw the glance-versus-detail line is a judgment, not something a tool decides.

It composes with `documentation-existence.md` (admit the page at all), `reference-dont-duplicate.md` (keep one copy of a fact), and `documentation-and-citations.md` (defer to the upstream owner): those decide *whether* the page exists, *whether* to hold a fact, and *where* it lives; this decides how to *layer* the copy you keep so a reader pays only for the depth they reach.

## Lead with a glance a reader can stop at

- The top layer is an index or summary that resolves the common question on its own — it carries the status, the next action, or the one-line answer most readers came for. An index that omits what they need forces them into the body anyway, which defeats the layering.
- Everything expensive — the full body, the history, the rationale — sits behind that glance, read only when the glance proves insufficient.
- Do not invert the ladder: leading with the costly layer before the cheap one makes every reader pay for depth before they know they need it.

## Budget the always-loaded surfaces first

The layers that load every session — a root instruction file, an always-on rule, a checklist a reviewer opens on every change — are where the discipline pays off most, because their cost recurs.

- Keep an always-loaded surface to its headline and demote the body to a layer fetched on demand. A thin gate that points at a reasoned source is the shape to reach for; a fat one that inlines the reasoning is the smell.
- Dumping full detail into an always-loaded surface is the core anti-pattern — most sessions never reach that detail, yet every session pays for it. Leave a one-line headline and a pointer to the on-demand body.

## The same ladder fits every surface

- **Documentation** — an index or summary over the full body; the reader stops at the one-line entry unless the question needs the doc.
- **Instructions and rules** — an always-loaded headline, then detail scoped to the path or context it applies to, then a reference document read only when cited.
- **Review criteria** — the thin bar a reviewer applies on every change, pointing at the reasoned criterion behind it rather than inlining it.

## Sources

- Nielsen, ["Progressive Disclosure"](https://www.nngroup.com/articles/progressive-disclosure/) (Nielsen Norman Group, 2006) — show the few most important options first and defer the rest to a secondary layer, improving learnability, efficiency, and error rate.
