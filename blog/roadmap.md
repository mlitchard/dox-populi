# Blog roadmap — Dox Populi

**Masthead:** *Dox Populi*. Two words, no subtitle.

**About page:** unnumbered, linked from the masthead — `blog/about/`.
The author's record, scope-honest; the disclosure behind the no-degree
promise.

**Thesis:** The confluence of Determinate Nix
(reproducible delivery, flake to bootable ISO), Paradox (decision
logic as a verified spec), and LLM agents (authorship and tutoring at
conversational speed) points to significant improvements to a working
developer's effectiveness: delivering an agentically-created,
fit-for-purpose codebase with confidence and efficiency. One project's
evidence, rerunnable by the reader — that is the standard every post
holds itself to.

**Audience:** the working developer, and the aspirant on the way to becoming
one — 16 to 25, often self-taught, no CS degree assumed. With respect to
verified specs and agent-authored code, everyone stands at the same
starting line: nobody arrives knowing Paradox, and no degree gets you
closer. The curriculum has one level because everyone starts at it. For the
self-taught especially, the stack supplies what going it alone usually
lacks: a verdict on every attempt (Paradox, tsc, the tests) and a tutor
on demand (the LLM). The homework's floor: an aspirant with QEMU and an
afternoon. That floor is the claim.

**Doctrine (every post obeys these):**

- **The loop survives.** Prior software engineering practice carries over,
  changed. Every post narrates the same circle: code, test, code, test,
  until the checks pass — then delivery. CI/CD carries more weight than it
  ever did.
- **The human is the final word.** Paradox, tsc, and the tests produce
  evidence; the human rules on it, catching what green checks miss.
  Inspection never leaves his hands.
- **Green checks are not understanding.** The reader (and the author) can
  interrogate the LLM about the Paradox it wrote and come away
  understanding more. The same LLM that authors the spec teaches it. Every
  post demonstrates this by putting the author's questions on the page.
- **Posts lead with the game.** The engineering rides along; we never say
  so on the page.
- **Homework stays local.** Exercises target the reader's own VM world,
- **Jargon links out.** First use of a term of art in any post links to a
  Wikipedia entry or similar. No degree assumed is a promise about
  vocabulary too.

**The bar every post must clear:** what did the reader get that they couldn't
get with vim and vibes? If a post reads like a nix flex, it doesn't ship.

## The template (every post, same skeleton)

1. **The Promise** — this is what this post is about, this is what you'll
   learn.
2. **The Session** — curated excerpts from `docs/unedited/`, the author's
   questions set in bold as the through-line. The reader watches the LLM
   help at each step and watches the author cross-examine it. Verdicts
   from Paradox, tsc, and the tests appear in the conversation where
   they actually happened.
3. **The Proof** — the manual test, captured: animated GIFs and stills of
   the world doing the thing (steamless client in the browser is the
   capture surface). The reader can boot the ISO and re-shoot it.
4. **The Postscript** — exercises that enforce what was learned.

## Evidence map (branch ↔ session transcripts ↔ story)

| Branch / commits | Sessions on record | The story |
|---|---|---|
| pre-branch main, 2026-07-25→28 | `one/2026-07-26-this-session` | The delivery fight: installer ISO for non-nix users, qemu/ext4/Screeps-path failures, secrets identity chain. The vendoring + self-provisioning deploy session predates the captured record — no transcript on disk |
| `1-tutorial-2` | `one/2026-07-30-local-command-caveat` | First FSM: harvester/upgrader, spawnFull bug, ERR_FULL recovery |
| `2-install-fix` | `one/2026-07-30-session-prompt-pre-build` | Installer pre-builds devShell — the "non-nix people" promise |
| `3-tutorial-3` | `one/2026-07-30-this-session`, session-prompt-tutorial-3 | Builder role + harness becomes a generic FSM interpreter (zero literals) |
| `4-tutorial-4` | `one/2026-07-30-session-prompt-tutorial-4`, session-prompt-tutorial-4 | Tiered bodies, literal-bridge trick, colony survives its own deaths |
| `8-fix-dev-iso`, `9-tick-speed` | `one/2026-07-31-this-session`, session-prompts vm-repo-mount + tick-speed | dd-pattern installer, tests mirror the dev env, parameterized tick |
| `7-tutorial-5` | `one/2026-07-31-local-command-caveat`, `2026-08-02-local-command-caveat`, session-prompt-tutorial-5 | Tower FSM; Paradox guards unusable → flat product event vocabulary; Memory.trace flight recorder vs one-tick transients |
| `10-test-analysis` | ("had claude sum up the tutorial") | CI dedup via flake gitlab overlay; oracle sweep replaces regression pins |
| `11-attack-defense` | `2026-08-01-this-session`, `2026-08-02-this-session`, session-prompts raider-offense + live-invader | The enemy is Paradox-specified too. Raiders NPC user, relentless war, first-blood itest, the two-laws tower deadlock |
| `12-flakehub-prep` | `2026-08-12-i-need-to-change` (upstream rename) | Going public: FlakeHub, generated CI, mirror parity |
| `13-detsys-install` | — | Determinate Nix drives the dev VM; vm-boot asserts it (`tests/vm.nix`); fh + flake-checker in the devShell; disko pinned via FlakeHub release |
| (future) | `docs/evolution-plan.md` | The hybrid mutator; the engine kit |

## The slate (6 posts, plus one future post)

0. **"What the Confluence of Determinate Nix, Paradox, and LLM Agents
   Points To for the Working Developer."** — branch: `main`
   The manifesto. The claim, stated carefully: an LLM wrote the
   infrastructure, the harness, and the spec; Paradox checked the spec
   and generated the decision logic from it; every change had to compile
   and pass the tests; nix delivered it soup-to-nuts. One project, in a domain the tooling fits, every claim
   rerunnable. The Session: the delivery fight from the genesis
   transcript — "i want non-nix users to have access" on the record, and
   the ISO-naming fail → fix → pass loop. The Proof: the release ISO
   boots in QEMU and the world ticks. The Postscript exercises: download
   the ISO, boot it, watch it install itself — what the reader learns is
   that onboarding takes one host dependency. Closes with "No Silver
   Bullet": Brooks split difficulty into accidental and essential; the
   confluence attacks the accidental, and the essential stayed human in
   every transcript on record.
   *Dependency: ISOs are built per release and hosted on Hetzner — the
   download link must exist before this post ships.*

1. **"Your First Spec."** — branch: `1-tutorial-2`
   The .dox FSM side-by-side with the official tutorial JS. Same behavior;
   one of them is machine-checked. The spawnFull bug and ERR_FULL recovery
   land in The Session. The Proof: harvester and upgrader working the
   room.

2. **"The Harness Knows Nothing, Jon Snow."** — branch: `3-tutorial-3`
   The harness becomes a generic FSM interpreter: zero role literals, zero
   state literals, every decision moved into the spec. The title is a
   falsifiable claim — grep the harness for a role name, find nothing. The
   check-vs-generate asymmetry lands in The Session as honest
   "here's where the tool bit us" material. The Proof: the builder raising
   structures the harness has never heard of.

3. **"Bodies, Budgets, and the Literal Bridge."** — branch: `4-tutorial-4`
   Tiered bodies, richest-first; union variant names matching Screeps
   property strings — a misspelled variant is a compile error, while the
   code reads like plain old string indexing. The Proof: the colony surviving
   its own deaths.

4. **"Verified and Wrong."** — branch: `7-tutorial-5`
   The tower gets an FSM from the same spec, and every check passes
   while the colony freezes: the spec said building + sinksFull →
   building, a self-loop the gates blessed — consistency is what
   `paradox check` verifies, and the self-loop is consistent. The live bug hunt lands in The Session — the
   author watching the world stop, telemetry fingering the self-loop,
   the two-transition spec fix, the gates green on the correction. The
   guards retreat survives as a context paragraph cited from the
   session prompt. The Proof: the tower one-shotting the invader.

5. **"First Blood."** — branch: `11-attack-defense`
   No handwritten JS decision logic, ever — the raider is
   Paradox-specified, built by the same pipeline, seeded as an NPC user. The Session: the author
   cross-examining his own weakened test ("why is damageTaken off the
   stand?"), the escalating-wave protocol, the two-laws tower deadlock at
   990 energy, and the no-surgery doctrine amended by its own author to
   one arming write. First blood asserted: damageTaken >= 1. The Proof:
   raiders against the tower, first blood on camera.

*(future)* **"Evolution."**
   The hybrid mutator from `docs/evolution-plan.md`: deterministic genome
   mutations inner loop, LLM macro-mutations on fitness plateau, checkers
   gating both tiers between generations inside the sandbox. The human
   stays the final word on what leaves it.

## Sequencing

- Ship post 0 and post 1 close together — a manifesto alone is a wish with
  indentation; manifesto plus proof is a case.
- Post 5 is the traffic driver — war stories travel.
- Evolution is the cliffhanger that keeps people subscribed.
