# Your encryption key

Secrets in `secrets/` are [age](https://age-encryption.org)-encrypted
files managed with **secrix**. Each is encrypted to one or more
recipients (public keys) and decrypted with the matching private key.
The project's apps decrypt them with **your** key, so setup is two
moves: create a key, then encrypt the secrets so your key can open
them.

## Create a key and put it where apps look
```sh
ssh-keygen -t ed25519          # <name> + <name>.pub
```
The search order:

1. `$SCREEPS_IDENTITY`
2. `$WORKDIR/identity`
3. `~/vm-keys/identity` (the conventional location — run-vm.sh shares
   this host directory into the VM at the same path)

If a secret exists and no key file is found, the app stops and tells
you where to put it.

## Create a secret

`create` opens your `$EDITOR`; type the secret, save, and exit, and it is
encrypted for the recipients you name. Name your own public key as the
recipient so your private key can decrypt the file later:

```sh
nix run .#secrix create secrets/SCREEPS_LOCAL_CREDS -- \
  -r "$(cat ~/vm-keys/identity.pub)"
```

For `SCREEPS_LOCAL_CREDS` the content is one line, `username:password`.

The encrypted file must be at `secrets/SCREEPS_LOCAL_CREDS` under the
repo root.

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
