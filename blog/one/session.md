## The Session

The transcript behind this post is July 30th, the session that delivered
tutorial 2. What follows is the conversation itself — my prompts in bold,
the assistant's replies as it wrote them. Every quote is exact; the only
editing is trimming. The full transcript ships with this series' context
sources.

The integration test rode in the opening prompt.

> **analyse the code base , as well as
> /home/mlitchard/github/tutorial-scripts, and
> /home/mlitchard/github/screeps . tell me what the next step is to
> deliver tutorial 2 and then deploy. we will also need an integration
> test verifying tutorial 2 succeeded**

The assistant read all three repos and reported where the project stood:

> The brain is DONE. dox/creeps.dox already has everything section 2
> needs — upgrader role, upgrader FSM (collecting/upgrading), harvester
> FSM (harvesting/delivering), event vocabulary
> (storeEmpty/storeFull/spawnFull/tick) … Two complete transition
> functions sitting there, exported, unused.

> The shell is still living in section 1. That's the problem.

> **do it**

It rewrote the shell to run both creeps from the generated machines,
extended the integration test, and closed with:

> Z3 signed off. tsc signed off. Two witnesses, court of law.

I deployed to the local server and watched the room.

> **im watching the code in action, what was tutorial 2 attempting to
> do?**

> … section 1 was "can you eat," section 2 is "can you grow."

> **the harvester isnt doing anything**

The next several rounds narrowed it down.

> **yes the upgrader works, the other one doesnt**

> **standing at source with full store**

> That's the smoking gun. Full store at the source, not moving toward
> the spawn. … The fact that it's standing still means something is
> erroring out silently.

> **this is a clean build**

I pasted the code the broken harvester was running, pulled straight from
the client.

> **this is the code of the broken harvester "use strict"; …**

> I see it. The bug is in the event priority in emitEvent.
>
> When the harvester's store is full AND the spawn is full:
> …
> transfer(spawn) → ERR_FULL (not ERR_NOT_IN_RANGE) → no moveTo
> Creep is stuck forever.
>
> The FSM already handles this case correctly — delivering + spawnFull →
> harvesting. But the event never reaches it because storeFull is
> checked first.

The fix waited.

> **write an integration test that tests for correct behavior**

> Right. Test first, then fix. … it should fail against the current spec
> (proving the bug) and pass after the fix.

The test ran against the unfixed spec:

> There it is. One failure, exactly where we predicted:
>
> FAIL: collecting + spawnFull → upgrading (upgrader doesn't deliver to
> spawn) — expected "upgrading", got "collecting"

The bug was on record. Then the fix — one transition in the spec, one
reorder in the harness — and the checks:

> Three witnesses. All passed.

Back in the room, a creep was wrong again.

> **upgrader-2216 only carries 2 energy at a time**

> **i started clean**

> My bad. The event priority reorder was too blunt — it makes spawnFull
> fire for the upgrader on every tick once the spawn fills up, so it
> transitions to upgrading with just 2 energy instead of filling up
> first.
>
> The real fix: spawnFull should only fire when the creep's store is
> also full. It's the compound signal "ready to deliver but can't."

Every check had been green through both bugs.

> **why did the tests pass?**

> The tests passed because the FSM behavioral test only tests the
> transition functions — it verified collecting + spawnFull → upgrading,
> which is correct and still needed. It doesn't test emitEvent, which is
> where the bug was. The test was incomplete — it proved the spec fix
> but didn't catch the shell-level event emission problem.
>
> Let me add an emitEvent test. But first — emitEvent uses Screeps
> globals (RESOURCE_ENERGY, Creep, StructureSpawn), which don't exist
> outside the game runtime. I need to mock them for the test.

> **dont mock them, use the game runtime**

> Right. The game runtime is the real test. Let me add event telemetry
> to the shell so the itest can verify emitEvent produces the right
> signals under real game conditions.

Days later the same test caught a bug the session had missed. CI failed
the integration test on GitLab's runner while it passed on my machine:
the harvester had delivered a partial load, the spawn filled
mid-transfer, and with the creep's store at 30 of 50 the compound
condition stayed quiet — the creep repeated delivering, tick after tick,
for the full timeout.

> The fix: when transfer() returns ERR_FULL, feed a "spawnFull" event
> back to the FSM. The brain still makes the decision (delivering +
> spawnFull → harvesting), the hands just observe that the transfer was
> rejected …

> **Is there a way to write a regression test for this situation, set up
> this exact situation, and test that the right behavior happens**

> Yes. Add a counter in the shell that tracks ERR_FULL recoveries, then
> poll for it in the itest. That proves the exact code path — partial
> transfer, ERR_FULL, re-evaluation — was exercised in the real game
> runtime.

> If anyone ever breaks the ERR_FULL handling, this test times out on
> CI. No mocks, real game runtime.
