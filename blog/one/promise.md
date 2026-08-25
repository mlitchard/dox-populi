## The Promise

Boot this post's VM and the room is working: one creep shuttles energy to
the spawn, another hauls it to the room controller, the structure that
levels up the room. That's the second section of the official Screeps
tutorial. Section one asked for a harvester that feeds the spawn; section
two adds an upgrader that grows the room.

This post follows the session that delivered it. Partway through, the
harvester froze at the source with a full load. The post is the story of
getting it unstuck.

What you'll learn:

1. Where the bot's decisions live: in a spec, one
   [finite-state machine](https://en.wikipedia.org/wiki/Finite-state_machine)
   per role. The harness — the code that talks to the game — reads the
   world and carries out the current state.
2. How the code-test loop turns a live bug into a failing test, and the
   failing test into a fix.
3. How to interrogate a green test.

<!-- SIDE-BY-SIDE PLACEHOLDER: the official tutorial's role JS next to
     the spec's machine. Snippets ruled on separately. -->
