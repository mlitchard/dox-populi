# Documentation Instead of Deduction

Where the evidence lived: the published bundle. From
`docs/unedited/2026-09-02-102600-im-in-trouble-claude.txt`, around
line 7365.

The viewer's map was empty. The renderer's metadata package looked
importable, and the agent had spent three rounds deducing an interop
shape for it — each plausible, each producing a new error on my
screen. I pasted the latest:

```
metadata level 0: object Array(1)
metadata level 1: object Array(0)
Error: could not resolve renderer metadata (no objects key found)
```

> Level 1 is a truly empty object — the metadata module hands esbuild
> nothing at all, which no interop shape explains from the outside.
> Time to read the actual published bundle instead of deducing: I'll
> fetch the metadata dist file's wrapper from unpkg (like I did for
> the renderer) and see exactly how it attaches its exports.

One read of the published file ended it. The fix's own comment
carries the finding:

> The metadata dist is an IIFE with no module exports: importing it
> runs a side effect that assigns window.RENDERER_METADATA.

The import became a bare side-effect import, the resolver became a
read of that global, and the fact went into
`docs/viewer-contract.md`. The walked-and-guessed `.default` chain,
its debug logging, and its wrong comment all came out in the same
edit. What I said next is on the record at line 7482, and it governs
this whole page:

**from now on I require you to rely on documentation instead of
deduction**
