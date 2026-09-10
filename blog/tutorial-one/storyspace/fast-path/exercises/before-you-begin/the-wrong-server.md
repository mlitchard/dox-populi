# The Wrong Server

Where the evidence lived: the script in the checkout. From
`docs/unedited/2026-07-30-100641-local-command-caveatcaveat-the-messages-below-w.txt`,
around line 467.

The agent had just finished a change, checks green, and handed me the
next command:

> Next move is yours. You want to deploy and run the itest? That's
> nix run .#deploy for live, or nix build
> .#checks.x86_64-linux.itest for the full VM integration test.

**this appears to connect me to the public screeps server not my
local server**

> Let me look at exactly what deploy and deploy-local do, and how the
> server is configured.
>
> Right. Two completely different apps:
>
> - nix run .#deploy — pushes to https://screeps.com/api/user/code
> (the public server). Requires your decrypted SCREEPS_TOKEN.
> - nix run .#deploy-local — pushes to http://127.0.0.1:21025 (your
> private server). Self-provisions the account, places Spawn1, the
> whole nine.
>
> You want the local loop.

The recommended command was plausible, confidently delivered, and
pointed my code at a server on the other side of the internet. What
caught it was watching where the session actually connected; what
settled it was the deploy script's own source, which names its
target URL. Every instruction after this exchange says
`deploy-local` — the command this tutorial has you running.
