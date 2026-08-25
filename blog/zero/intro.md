Two fish are swimming in the ocean.
One fish turns to the other and says, "How do you like the [water](https://en.wikipedia.org/wiki/This_Is_Water)?"
"What's water?" says the other fish.

An LLM agent built a bot that plays [Screeps](https://screeps.com), a strategy game for programmers.
It wrote the spec the code is generated from, as well as most of the infrastructure.
My job was to direct it and to inspect everything it produced.
The result fits on one disk image; if you have [QEMU](https://en.wikipedia.org/wiki/QEMU),
you can boot it and watch the bot play.
There's no one thing that happened to make this possible.
I'd like to take a look at what the confluence of LLM agents,
[formal methods](https://en.wikipedia.org/wiki/Formal_methods), and a [reproducible environment](https://docs.determinate.systems/getting-started/individuals/)
points to for the working developer.

We're swimming in new waters, and the currents of discovery flow.

## We stand on the shoulders of giants

Every load-bearing piece of this project was built by someone else.
A curriculum for a working developer, or an aspirant, needs an artifact
at its center. Games are handy that way. I chose Screeps because it's
simple enough to approach, it has a user base, and its tutorial hands us a
starting point somebody else defined: the tutorial says what a working bot
must do, so "fit for purpose" was already answered. The game, the
open-source server it runs on, the tutorial, years of players writing about
it — all of that was in place before this project. The curriculum stands on
it. The artifact arrives whole: one download, one boot, and everything this
series describes is running on your machine.

The LLM agent is the tutor. When I didn't understand what it had built, I
asked, and the answers came in plain language. Every post in this series
quotes those exchanges from the session transcripts. It also wrote the
lines it explains. So my understanding comes from questioning the agent,
and verification comes from Paradox.
The agent writes a spec of the bot's decisions. Paradox checks it with an
[SMT solver](https://en.wikipedia.org/wiki/Satisfiability_modulo_theories).
The code is generated from the spec that survives.
What doesn't hold together never reaches the game.

The verification research is decades old, and the solvers have been fast
for years. What stayed expensive was the writing: a spec had to be filled
out by someone trained to write specs, and that training used to be a career.
The agent is what changed the cost. An LLM samples from the
space of plausible programs, and a plausible program can be wrong in ways
that don't look wrong. The spec language narrows what the agent can say
down to decision structure. The check rejects a spec that contradicts itself,
and a case the agent never considered comes back as a failure with the
case named. On its own, the agent's output is unchecked. On its own,
Paradox waits for an expert. Put them together and the on-ramp into
formal methods gets wider and less steep. The deep expertise is still
where it always was: with the people who built Paradox and the solver
under it. I'm a developer without that training, and this project is one
step up the ramp.

But if delivery isn't reproducible, the whole exercise just becomes
something that works on my machine, and a claim you can't interrogate is a
claim you don't have to believe. This series asks you to reproduce and
interrogate. Therefore nix.


