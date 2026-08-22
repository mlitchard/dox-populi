# Blog post zero — outline

**Title:** What the Confluence of Determinate Nix, Paradox, and LLM Agents
Points To for the Working Developer
**Branch:** `main`
**Dependency:** the per-release ISO must be live on Hetzner before this
post ships — the exercises link to it.

## 1. The Promise

- Opening paragraph: what this blog is — the record of building a Screeps
  bot where an LLM wrote the infrastructure, the harness, and the spec;
  Paradox checked the spec and generated the decision logic; every change
  had to compile and pass the tests; and nix delivers the whole thing to
  your machine. What this post teaches: what that combination points to,
  and homework that ends with the project's world ticking on your own
  hardware.
- Why Screeps, one paragraph, three reasons: it's simple, it's a game, and
  the tutorial already exists — an official, public specification of what
  the creeps should do, written before this project touched it. A fixed
  target nobody can quietly move. Link to the game.
- The claim, one beat per tool:
  - **Determinate Nix** — delivery. Flake to bootable ISO; every claim in
    the series is rerunnable.
  - **Paradox** — the decision logic lives in a verified spec.
  - **LLM agents** — authorship at conversational speed; also the tutor.
  - What none of them does alone; what the three do together.
- The loop survives: code, test, code, test, until the checks pass — then
  delivery. CI/CD carries more weight than it ever did.
- The human is the final word: Paradox, tsc, and the tests produce
  evidence; the human rules on it, catching what green checks miss.
- Green checks are not understanding: you can interrogate the LLM about
  the spec it wrote. Every post in this series puts the author's actual
  questions on the page.
- Scope honesty: one project, a domain the tooling fits, n=1 — which is
  why the title points instead of promises.
- What you'll learn:
  1. Onboarding takes one host dependency — proven by doing it.
  2. What equipment the rest of the series requires and why — the same
     context sources the author fed the LLM.

## 2. The Session

Source: `docs/unedited/one/2026-07-26-this-session-*.txt`. The delivery fight:
making the project installable by people who have never heard of nix.
Author's questions set in bold. Candidate receipts (line numbers into the
transcript):

- **~110** — "so you are giving up on the requirements? i want non-nix
  users to have access." The audience doctrine, on the record, before the
  blog existed. The assistant offers two paths; the harder one (installer
  ISO) wins.
- **~260–287 → ~443–487** — the ISO-naming loop, cleanest
  fail → fix → pass on record: `nix eval` returns the wrong ISO name;
  root cause: `isoImage.isoName` is a dead alias in 25.05; fix:
  `image.baseName` + `mkForce`; pass verified by `nix eval`. The
  code-test circle, complete.
- **~788** — "stop guessing, if you are out of ideas say so. stop
  guessing." The assistant stops, reads the source, finds the real bug
  (wrong `STEAM_SCREEPS_DIR` path). Evidence demanded, evidence produced.
- **~868–876** — the secrets ruling: "they are going to prvide their own
  keys, dont hardcode a particular key... this is not optional." The
  human as final word, verbatim.
- **~1616–1628** — "this needs to be handled in the flake" — a live error
  becomes a design obligation; the identity fallback chain lands in
  flake.nix instead of in user instructions.

Curation notes: verdicts from Paradox, tsc, and the tests appear where
they actually happened in the conversation; trim assistant output hard,
keep the questions whole.

## 3. The Proof

- GIF sequence: QEMU boots the ISO → installer runs itself → reboot →
  world ticking in the browser client → a creep harvesting.
- Caption law: every GIF names the command that produced it, so the
  reader can re-shoot the shot.

## 4. The Postscript

- Exercises for objective 1:
  1. Download the release ISO (Hetzner link).
  2. Run the exact qemu invocation, given verbatim.
  3. Boot; watch the install run itself; log in.
  4. Find the world ticking.
  What you just learned: onboarding took one host dependency.
- Exercise for objective 2:
  5. Download the LLM's context sources — the same material the author
     fed the LLM while building this project, and what the reader feeds
     theirs when they interrogate the spec:
     - Paradox (public: gitlab.com/paradox_labs/paradox)
     - the official Screeps tutorial sources
     - typed-screeps (the ambient Screeps API types)
     Exact links pinned at draft time. Later posts assume the reader has
     these.
- Before the next post: open `dox/creeps.dox` and look around. Post one
  teaches interrogation; bring a question.
- Close: **No Silver Bullet.** Brooks, named. Accidental vs. essential
  complexity; the confluence attacks the accidental; the essential stayed
  human in every transcript this series will show you. Final line: what
  grows is what you can deliver with confidence.
