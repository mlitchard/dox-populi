# Before You Begin

These exercises put five languages on your screen: TypeScript in
`harness/`, a paradox spec in `dox/`, nix in the flake, JSON from a live
server, and two files of the tutorial's original JavaScript. Each
exercise names the files it touches, and the languages arrive a few
lines at a time.

## Bring your agent
I use Claude Code exclusively, with fable passing off particular tasks
to appropriate model. You can use your preferred agent.

## The loop

Ask your agent a question about the code in front of you. Take its
answer as a claim. Verify the claim yourself, and keep what survives.

A claim that keeps losing to the evidence is telling you about your
model. Ask smaller questions, or bring a stronger one.

## Feeding the agent

I had Claude write the spec by first reading the source code for
Paradox, and the model tutorial code. That was my first test of this whole approach: could Claude
read the Paradox source and write Paradox? Could it write the solution to the tutorial
in concert with the typescript harness? It could, and it did.

The viewer in this repo carries the sharpest example of source as
food. Its map came up empty, and the agent spent three rounds
deducing how the renderer's metadata package ought to import — each
round plausible, each wrong. What ended it was reading the published
bundle itself: the file exports nothing; it assigns
`window.RENDERER_METADATA` and that's all. One read, working map. My
ruling from that exchange is on the record and it governs this whole
page: rely on documentation instead of deduction. The session is in
`docs/unedited/2026-09-02-102600-im-in-trouble-claude.txt`.

Give your agent the same food: the sources of the projects you're
asking about, cloned where it can read them. They feed its answers
and they hold the evidence your checks need.

[MICHAEL: the install list — the repos and where to clone them.]

## Where claims get settled

You are the arbiter; the agent's claims are settled by you, on
evidence you can hold. Every toolchain in the flake doubles as an
instrument that produces it.

- **A file in this repo** — the file, sitting in your checkout.
- **Game behavior** — the running world: deploy and watch.
- **The game API** — the
  [Screeps API reference](https://docs.screeps.com/api/), and the
  screeps repos above when the claim reaches into the engine.
- **TypeScript** — the compiler: turn the claim into a line and put
  it through the gate; tsc rejects it or compiles it, evidence
  either way. `vendor/screeps.d.ts` settles what the game's types
  declare, and the
  [TypeScript handbook](https://www.typescriptlang.org/docs/handbook/)
  settles claims about the language.
- **nix** — the evaluator: `nix eval` or `nix build` the attribute
  the claim is about, and `flake.nix` is in your checkout to read.
  The [Nix reference manual](https://nix.dev/manual/nix/) settles
  claims about the language.
- **The spec** — `paradox check` verifies the named properties, and
  the [Paradox source](https://gitlab.com/paradox_labs/paradox) is
  public.
- **JavaScript semantics** —
  [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript),
  and the running world for what the two tutorial files actually do.

## Why Did the Tests Pass?

The loop above is how this repo was built. The transcripts in
`docs/unedited/` are the unedited record; four moments from them,
one per kind of evidence:

- [Why Did the Tests Pass?](before-you-begin/why-did-the-tests-pass.md)
  — three green checks, and the running world had the last word.
- [This Is a Clean Build](before-you-begin/a-clean-build.md) — the
  agent's theory against what I knew I had done.
- [It Passes Locally](before-you-begin/it-passes-locally.md) — CI
  reached a deadlock my machine missed.
- [The Wrong Server](before-you-begin/the-wrong-server.md) — a
  confident command pointed at the wrong world.

## The JavaScript

The original tutorial's JS is two short files. One semantic in it
deserves respect: a misspelled property reads as `undefined`, and the
error arrives later, somewhere else. It has its own exercise —
[same-mistake.md](same-mistake.md) — where the running world
demonstrates it. Each JS file also has a typed counterpart in the
port, so a claim about the JS can be held against the same behavior
written with declared types.

## Start

[sources.md](sources.md) is first.
