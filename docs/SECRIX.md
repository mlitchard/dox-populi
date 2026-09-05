# Managing secrets with secrix

The files in `secrets/` are [age](https://age-encryption.org)-encrypted,
managed with **secrix**. Each is encrypted to one or more recipients
(public keys) and decrypted with the matching private key. The project's
apps decrypt them with your key (see the "Your encryption key" section of
the README for which secret each app reads and where the key is looked
up).

This page covers creating and editing those files. Run the commands from
the dev shell (`nix develop`), where `secrix` is on the path; the
`nix run .#secrix` form shown here works anywhere.

You need an SSH keypair. Generate one if you don't have it:

```sh
ssh-keygen -t ed25519          # private key + <name>.pub
```

## Create a secret

`create` opens your `$EDITOR`; type the secret, save, and exit, and it is
encrypted to the recipients you name. Encrypt to your own public key so
your private key can decrypt it later:

```sh
nix run .#secrix create secrets/SCREEPS_LOCAL_CREDS -- \
  -r "$(cat ~/.ssh/id_ed25519.pub)"
```

For `SCREEPS_LOCAL_CREDS` the content is one line, `username:password`.

To create without an editor, pipe the value in with `encrypt`:

```sh
printf '%s' 'lambdafan:your-password' | \
  nix run .#secrix encrypt secrets/SCREEPS_LOCAL_CREDS -- \
    -r "$(cat ~/.ssh/id_ed25519.pub)"
```

## Edit a secret

`edit` decrypts the file with your private key (`-i`), opens it in your
`$EDITOR`, and re-encrypts on save:

```sh
nix run .#secrix edit secrets/SCREEPS_LOCAL_CREDS -- \
  -i ~/.ssh/id_ed25519 \
  -r "$(cat ~/.ssh/id_ed25519.pub)"
```

**Re-specify every recipient on edit.** secrix does not reuse the file's
existing recipient keys; whatever you pass with `-r`/`-u`/`-s` becomes the
new complete recipient set. Leave a key out and that key loses access.
`rekey` takes the same flags and is the command for deliberately changing
the recipient set.

## Read a secret

`decrypt` writes the cleartext to stdout — the way to recover a value you
forgot:

```sh
nix run .#secrix decrypt secrets/SCREEPS_LOCAL_CREDS -- \
  -i ~/.ssh/id_ed25519
```

## Notes

- All flags go after the `--` in the `nix run` form; positional arguments
  (the file path) may go before it.
- Recipients: `-r` adds an ad-hoc public key; `-u`/`-s` add users/systems
  configured in the flake. `nix run .#secrix -- -l` lists them.
- Quote a password with shell-special characters in single quotes so the
  shell passes it through untouched.
