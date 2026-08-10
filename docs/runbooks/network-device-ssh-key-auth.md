# Runbook: SSH public-key authentication on HPE Comware switches

Applies to `medina`/`anderson` (HPE 5130, Comware). Per ADR-0033, network
device configuration is manual/out of IaC scope — this is that manual
procedure, documented for repeatability.

## Key constraint: no ed25519 support

Comware's SSH implementation supports RSA, DSA, and ECDSA for public-key
authentication — **not ed25519**, unlike every other key in this project.
A dedicated RSA key is required.

## One-time: generate the key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_network -C "admin@network-devices"
```
Private key → KeePass, same as every other project key.

## Per-switch procedure

1. **Connect with password auth**:
```bash
   ssh -o HostKeyAlgorithms=+ssh-rsa admin@<switch>.station.solsys.dev
```

2. **Enable SCP transfer**:

system-view
scp server enable


3. **Transfer the public key** (from your Mac, separate terminal):
```bash
   scp -O -o HostKeyAlgorithms=+ssh-rsa ~/.ssh/id_rsa_network.pub admin@<switch>.station.solsys.dev:flash:/id_rsa_network.pub
```

4. **Import the key**:

public-key peer admin-key import sshkey flash:/id_rsa_network.pub


5. **Verify the import**:

display public-key peer admin-key

   Compare against `ssh-keygen -lf ~/.ssh/id_rsa_network.pub` locally.

6. **Bind the key to the user** — under `ssh user`, not `local-user`:

ssh user admin service-type stelnet authentication-type publickey assign publickey admin-key


7. **Verify the binding**:

display ssh user-information admin


8. **Save**:

save force


## Client-side SSH config — three separate gotchas, all needed together

Add to `~/.ssh/config`:

Host medina.station.solsys.dev anderson.station.solsys.dev 10.10.10.2 10.10.10.3
HostKeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa
IdentityFile ~/.ssh/id_rsa_network
IdentitiesOnly yes


Each line fixes a distinct failure mode:
- **`HostKeyAlgorithms +ssh-rsa`** — without this: "Unable to negotiate...
  no matching host key type found." Modern OpenSSH disabled `ssh-rsa` as a
  *host key* algorithm by default; this switch generation only offers it.
- **`PubkeyAcceptedAlgorithms +ssh-rsa`** — without this: "Permission
  denied (publickey)" with "no mutual signature algorithm" in verbose
  output. Same root cause, but for the client's pubkey signature
  algorithm — a separate setting.
- **`IdentitiesOnly yes`** — without this: "Too many authentication
  failures for admin." If `ssh-agent` has multiple keys loaded, OpenSSH
  offers all of them before the configured one, and these switches have a
  low `MaxAuthTries` limit — you get disconnected before your actual key
  is tried.

## Verifying

```bash
ssh admin@medina.station.solsys.dev
ssh admin@anderson.station.solsys.dev
```
Should log in with no password prompt, using only the config above.