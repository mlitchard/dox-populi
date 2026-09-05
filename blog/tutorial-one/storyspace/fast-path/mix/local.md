# Get in the mix.
Take a look at the following sections of flake.nix:
[`reset-local`](https://gitlab.com/dox-populi/screeps/-/blob/baea2878c85d40a7dcbfd68bb39f727d909c60f8/flake.nix#L854)
  and
[`stop`](https://gitlab.com/dox-populi/screeps/-/blob/baea2878c85d40a7dcbfd68bb39f727d909c60f8/flake.nix#L837)

Identify the similarities and make
an [issue](https://gitlab.com/dox-populi/screeps/-/boards)
to refactor into a single paramaterized script called `local`.
It works like this
`nix run .#local -- reset`
or
`nix run .#local -- stop`

# Stretch Goal
After you make the issue, take it and deliver.

## How to make an refactor issue
1. Go to the [issues board](https://gitlab.com/dox-populi/screeps/-/boards)
2. Click the `+` button in the `open` column.
3. Fill in the title with `Refactor reset-local and stop into a single parameterized script called local`.
4. Click the issue's `Edit` button.
5. Under description, click the template dropdown and select `Refactor`.
6. Go from there.
