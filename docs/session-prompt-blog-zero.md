# Session: write the blog series. Start with post zero.

Branch strategy: every post is written against the repo branch it
describes, and that branch's code is the source of truth for that post.
Post zero gets a new branch, based off `main` — create it at session
start. Subsequent posts use the existing branch matching their place in
the series, per the roadmap's slate and evidence map: post one →
`1-tutorial-2`, post two → `3-tutorial-3`, post three → `4-tutorial-4`,
post four → `7-tutorial-5`, post five → `11-attack-defense`.

The codebase is the source of truth — as it stands on the post's branch.
Study it before anything else: `flake.nix`, `dox/creeps.dox`,
`shell/main.ts`, `tests/integration.nix`, `tests/vm.nix`, `vm/`, and
`CLAUDE.md` for the layout. Every technical claim in every draft must
match that branch's code. Where an outline, a transcript, or a draft
says something the code contradicts, the code wins — flag the conflict,
don't paper over it.

Sources of record — the code outranks all of them:

- `blog/roadmap.md` — thesis, doctrine, template, the slate. Editorial
  law; nothing you write may contradict it.
- `blog/zero/outline.md` — the post being drafted. Its structure is the
  post's structure.
- `docs/unedited/one/2026-07-26-this-session-*.txt` — the session transcript
  post zero quotes from.

Then, before any prose: verify the receipts. The outline pins candidate
quotes as approximate line numbers into the transcript. Pull the actual
text at each pin, quote it back to me exactly, and flag any pin where
the quote isn't there or says something different. No quote enters a
draft unverified. No quoting ghosts: if there's no transcript line for
it, it gets cited as an artifact or it doesn't appear.

Division of labor: I write the posts. You verify receipts, assemble
curated excerpts, and draft sections only when I say draft. Propose,
then wait. One section at a time.

Writing laws, non-negotiable:

- Plain language. Short sentences. No invented terms of art.
- Vocabulary: the spec (`dox/creeps.dox`), the decision logic (generated
  from the spec), the harness (the code that talks to the game), the
  infrastructure (the flake). File paths keep their real names.
- Banned: "faith"; "brain," "hands," and "shell" as names for the code;
  contrastive "X, not Y" phrasing; telling the reader what to feel.
- Name the tools: Paradox, tsc, the tests. Never "checker" or "compiler"
  as stand-ins. Never "Paradox + Z3" — Paradox uses Z3.
- On "prove": Paradox's machinery generates real proofs (an SMT solver
  and F*) — and the posts don't discuss them; outside the series'
  goals. In prose, state what the reader observes: Paradox verifies the
  named properties (consistent, total), a bad variant fails to compile,
  tests pass or fail. The human rules on the evidence, catching what
  green checks miss.
- Template per post: Promise (what you'll learn, first paragraph),
  Session (verified excerpts, my questions in bold), Proof (captures;
  every caption names the command that produced it), Postscript
  (exercises, each mapped to a stated objective).
- Jargon links out to Wikipedia or similar on first use.

Known dependency, not a blocker for drafting: the release ISO must be
live on Hetzner before post zero ships — the exercises link to it.

After post zero is done, the series continues in slate order: one, two,
three, four, five. Same laws, each post on its own branch, each post's
outline and transcripts as its sources of record; the code outranks
them.
