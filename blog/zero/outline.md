# Blog post zero — outline

**Title:** How's the Water? What LLM Agents, Formal Methods, and
Reproducible Environments Could Point To for the Working Developer
**Branch:** `main`
**Dependency:** the per-release ISO must be live on Hetzner before this
post ships — the exercises link to it.

## 1. The Promise

- Opening (as written in intro.md): the two-fish joke, DFW's "This Is
  Water" linked on the word water. Then the anecdote: an LLM agent built
  a bot that plays Screeps — it wrote the spec the code is generated from
  and most of the infrastructure; the author directed it and inspected
  everything it produced. One disk image; with QEMU you boot it and watch
  the bot play. There's no one thing that happened to make this possible.
  Thesis: what the confluence of LLM agents, formal methods, and a
  reproducible environment points to for the working developer. Coda:
  "We're swimming in new waters, and the currents of discovery flow."
  What this post teaches: what that combination points to, and homework
  that ends with the project's world ticking on your own hardware.
- "We stand on the shoulders of giants" (as written in intro.md): every
  load-bearing piece of this project was built by someone else. A
  curriculum for a working developer, or an aspirant, needs an artifact;
  games are handy. Screeps, three reasons: simple enough to approach, it
  has a user base, and its tutorial hands us a starting point somebody
  else defined — "fit for purpose" was already answered. The game, the
  open-source server, the tutorial, years of players writing about it —
  in place before this project; the curriculum stands on it. The artifact
  arrives whole: one download, one boot. Link to the game.
- The claim, one beat per category, in the title's order (as written in
  intro.md):
  - **LLM agents** — the tutor; it wrote the lines it explains, so
    understanding comes from interrogating it and verification comes from
    elsewhere.
  - **Formal methods** — Paradox is the exhibit: the agent writes a spec
    of the bot's decisions, Paradox checks it, the code is generated from
    the spec that survives.
  - **Reproducible environment** — delivery. Works-on-my-machine is a
    claim you can't interrogate; this series asks you to reproduce and
    interrogate. Therefore nix.
  - The access paragraph delivers the alone/together beat: agent
    unchecked alone, Paradox waiting on an expert alone; together the
    on-ramp into formal methods gets wider and less steep, expertise
    stays with the people who built the tools, the author is one step up
    the ramp.
- The loop survives: code, test, code, test, until the checks pass — then
  delivery. CI/CD carries more weight than it ever did.
- The human is the final word: Paradox, tsc, and the tests produce
  evidence; the human rules on it, catching what green checks miss.
- Green checks are not understanding: you can interrogate the LLM about
  the spec it wrote. Every post in this series puts the author's actual
  questions on the page.
- Scope honesty: one project, a domain the tooling fits, n=1 — which is
  why the title says could point instead of promising.
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
