```
          _                     ___           _      _           
         | |                   /   |         | |    (_)          
 _ __ ___| | ___  _ __   ___  / /| | __ _  __| |_ __ ___   _____ 
| '__/ __| |/ _ \| '_ \ / _ \/ /_| |/ _` |/ _` | '__| \ \ / / _ \
| | | (__| | (_) | | | |  __/\___  | (_| | (_| | |  | |\ V /  __/
|_|  \___|_|\___/|_| |_|\___|    |_/\__, |\__,_|_|  |_| \_/ \___|
                                     __/ |                       
                                    |___|                        
```

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/giuliocsr/rclone4gdrive/releases)
[![Lint](https://github.com/giuliocsr/rclone4gdrive/actions/workflows/lint.yml/badge.svg)](https://github.com/giuliocsr/rclone4gdrive/actions/workflows/lint.yml)

> Please, help me in leading this project! Look at `CONTRIBUTING.md` for how to contribute.
> 
> Every star **counts**! Consider it! ⭐

# rclone4gdrive <!-- omit in toc -->

Seamless, automated, and transparent two-way Google Drive backup for Linux.

- [Overview](#overview)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Directory structure](#directory-structure)
- [How rclone4gdrive works](#how-rclone4gdrive-works)
- [Customization](#customization)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [Meta](#meta)

## Overview

rclone4gdrive is a rclone wrapper for two-way Google Drive synchronization — typically used for cloud backup. Your `~/gdrive/` directory acts as a live mirror of your Google Drive root: anything you add, modify, or delete locally is transparently synced to Drive, and changes on Drive sync back.

It automates the rclone operations, OAuth, and error handling behind a "set up and forget" experience — scheduled syncs, automatic token refresh, and self-healing failure recovery — so filesystem-aware cloud backup from Linux needs minimal manual intervention.

**Highlights**
- One-command guided setup (`init`): checks/installs dependencies, performs Google OAuth, and wires up systemd — no manual `rclone config` or unit editing
- Works on desktops (browser authorization) and headless servers (paste-a-token flow)
- Uses rclone's shared credentials by default (zero Google Cloud setup), or your own `client_id`/`client_secret` for heavy use
- Hourly two-way sync via systemd user units, with automated failure recovery (token refresh, resync)
- Non-destructive OAuth token refresh, verified before committing
- `status`, `restart`, manual `sync`, and `uninstall` commands
- Ignores Google Docs/Sheets/Slides; syncs empty directories
- POSIX shell, no Bash required

**You don't need to**
- create Google Cloud Console credentials — rclone's shared credentials are used by default (bring your own only to avoid shared rate limits)
- run `rclone config` yourself — `init` creates and authorizes the remote
- write or enable systemd unit files by hand — `init` installs and enables them
- use root for the app — everything runs under your user (`init` only asks for `sudo` to install `rclone`/`jq` and enable lingering, which you can do yourself)

## Quick start

```sh
git clone https://github.com/giuliocsr/rclone4gdrive
cd rclone4gdrive
./rclone4gdrive init
```

That's the whole setup. `init` walks you through everything:

1. **Dependencies.** If `rclone`, `jq`, or user lingering is missing, `init` offers to install/enable them with `sudo`. Approve the prompts (or install them yourself beforehand).
2. **Google credentials.** By default it uses rclone's shared credentials — just press Enter. (Use your own only if you hit rate limits; see [Advanced init options](#advanced-init-options).)
3. **Authorize once.** A browser opens; sign in to Google and click **Allow**. This is the *only* manual step, and it happens exactly once.

When `init` finishes, `~/gdrive/` mirrors your Google Drive and stays in sync every hour. Run `rclone4gdrive status` to confirm.

> The one browser "Allow" click is unavoidable — Google requires a human to consent to Drive access for a personal account. After that single click, everything (including renewing the token forever after) is automatic.

### Headless / server install

On a machine with no browser, add `--headless`:

```sh
./rclone4gdrive init --headless
```

`init` still handles dependencies and systemd, but for authorization it prints a command for you to run on **any computer that has a browser and rclone**:

```sh
rclone authorize "drive"
```

(If you use your own credentials, it will be `rclone authorize "drive" "YOUR_ID" "YOUR_SECRET"` instead.) A browser opens there; after you click **Allow**, rclone prints a single JSON line starting with `{"access_token" ...`. Copy that **entire** line, paste it at `init`'s prompt, and press Enter. The token is stored and you're done.

### Advanced init options

```sh
rclone4gdrive init --help
```

| Option | What it does |
|---|---|
| `--bundled` | Use rclone's shared Google credentials (the default) |
| `--client-id ID`<br>`--client-secret SECRET` | Use your own Google OAuth credentials (best for heavy use; both required) |
| `--headless` | Force the paste-a-token authorization flow (servers with no browser) |
| `--no-deps-install` | Check dependencies but do not attempt to install them or enable linger |

Example — fully non-interactive setup with your own credentials on a desktop:

```sh
rclone4gdrive init --client-id 1234-abc.apps.googleusercontent.com --client-secret GOCSPX-xxxx
```

## Usage
> Your `~/gdrive/` directory is effectively a real-time view of your Google Drive root directory. Everything inserted, modified, or deleted within `~/gdrive/` will be transparently synchronized to your configured Google Drive location. This works both ways — changes made on Google Drive will also sync back to your local `~/gdrive/` directory.

After installation, you can use the following commands:
```sh
rclone4gdrive status        # Show timer/service status and the health of sync + authorization
rclone4gdrive restart       # Restart the timer and start the service immediately
rclone4gdrive sync          # Run a real two-way rclone bisync now (Google Drive <-> ~/gdrive)
rclone4gdrive sync-daemons  # (Re)install and enable the systemd user units
rclone4gdrive init          # (Re)run guided setup
rclone4gdrive uninstall     # Remove everything rclone4gdrive installed (units, scripts, the gdrive remote, ~/gdrive)
rclone4gdrive help          # Show this help message
```

> **Note:** `sync` performs a *real* two-way synchronization and will propagate changes (including deletions) both ways.

> **Upgrading from an earlier version:** the `rclone.service` unit now runs the bisync through an internal command instead of calling rclone directly, and `init` is now guided. If you already had rclone4gdrive installed, just run `rclone4gdrive init` once after updating (it will skip the parts that are already done).

## Directory structure
- `rclone4gdrive`           : Main script / entrypoint (contains the guided `init`)
- `config.sh`               : Shared configuration (remote name, sync dir, rclone paths, common bisync flags) sourced by every script
- `refresh_token.sh`        : Refreshes the OAuth token and updates `rclone.conf`
- `rclone-fail-handler.sh`  : Handles sync failures and triggers recovery
- `daemons/`                : systemd user unit files
	- `rclone.service`         : Runs the bisync via an internal helper command
	- `rclone.timer`           : Schedules regular syncs (hourly)
	- `rclone-fail.service`    : Handles failures and triggers recovery actions

## How rclone4gdrive works

*This section is for the curious. You don't need any of it to use the tool.*

**The moving parts.** rclone4gdrive is a thin orchestrator around four things: `rclone bisync` (the actual two-way sync), a systemd **timer** that fires hourly, a systemd **service** that runs the bisync, and a **failure handler** that recovers from problems. Three small shell scripts wire them together, and `config.sh` holds the single shared definition of the remote name, local directory, rclone binary, and the common bisync flags.

**Setup, in detail (`init`).**
1. *Dependencies.* `init` checks for `rclone`, `jq`, and user lingering (so timers run even when you're logged out). For anything missing it offers to install/enable it with `sudo`, falling back to exact copy-paste instructions.
2. *Credentials.* Google Drive access requires an OAuth *client*. By default `init` uses rclone's own registered client (the "shared" credentials) so you never touch the Google Cloud Console. You can instead pass your own `client_id`/`client_secret` for a private rate-limit budget. Either way, the client identifies the *application* — it never shares your files or storage with anyone; access to your data is granted only by your personal authorization token.
3. *Authorization.* This is the one step a human must perform, because Google requires explicit consent for Drive access on a personal account. On a desktop, `rclone config create`/`config reconnect` opens a browser, runs a localhost callback, and writes the token into `rclone.conf` automatically — you just click **Allow**. On a headless server, `init` instead uses the `rclone authorize` paste-a-token flow (see [Headless / server install](#headless--server-install)). If `init` detects the remote is already authorized, it skips this entirely, so re-running `init` is safe and idempotent.
4. *Verify.* `init` runs `rclone about gdrive:` to confirm the token actually works before declaring success.
5. *Initial sync.* It runs a one-time `rclone bisync --resync` to download your Drive into the (empty) local folder, establishing the bisync baseline so the first scheduled sync succeeds instead of failing with "must run --resync".
6. *Deploy.* Finally it copies the scripts to `~/bin/rclone4gdrive/`, adds that directory to your `PATH` via `~/.bashrc`, installs the systemd units, and arms the timer.

**Token lifecycle.** The one-time consent produces a refresh token stored in `rclone.conf`. Access tokens expire after about an hour; when they do, `refresh_token.sh` uses the refresh token to get a new one, updates `rclone.conf` (with backup + rollback, verified by a non-destructive dry-run). So after that single click, renewal is fully automatic forever.

**The hourly sync.** `rclone.timer` fires `rclone.service`, which runs the bisync. Rather than duplicate the bisync flags inside the unit (which can drift out of sync with the scripts), the unit delegates to an internal command — `rclone4gdrive sync-service` — that sources `config.sh`. That command is deliberately omitted from `rclone4gdrive help` and you never run it yourself; it's plumbing. The unit is `Type=oneshot`, so any non-zero exit is treated as failure, which is what triggers recovery.

**Failure recovery.** If a sync fails, `OnFailure=rclone-fail.service` runs `rclone-fail-handler.sh`. It inspects the last journal lines for known error patterns and acts: an expired/revoked token triggers `refresh_token.sh`; a "must run --resync" condition triggers a `--resync`. If recovery succeeds, it restarts the timer; otherwise it leaves the timer stopped and asks for manual intervention.

**Single source of truth.** Every bisync invocation — the timer, manual `sync`, failure-recovery resync, and the token-check dry-run — reads `REMOTE`, `SYNC_DIR`, `RCLONE_BIN`, and `BISYNC_COMMON_FLAGS` from `config.sh`. Change one line there and all of them update together; there are no duplicated flags to keep in agreement.

## Customization
- Edit `config.sh` to change the rclone remote name, the local sync directory (`~/gdrive` by default), or the common bisync flags applied to every sync
- Edit the systemd unit files in `daemons/` to change sync frequency or behavior (then run `rclone4gdrive sync-daemons`)

## Contributing
Pull requests and issues are welcome! Please, help me in leading this project! Look at CONTRIBUTING.md for how to contribute.

## Acknowledgements
rclone4gdrive relies on the following third-party tools and services:
- **rclone**: For robust cloud file synchronization and bisync operations ([rclone.org](https://rclone.org/))
- **jq**: For parsing and manipulating JSON data in shell scripts ([stedolan.github.io/jq/](https://stedolan.github.io/jq/))
- **Google Drive**: As the cloud storage backend, accessed via the Google Drive API ([google.com/drive/](https://www.google.com/drive/))

## Meta
giuliocsr

<p xmlns:cc="http://creativecommons.org/ns#" xmlns:dct="http://purl.org/dc/terms/"><a property="dct:title" rel="cc:attributionURL" href="https://github.com/giuliocsr/rclone4gdrive">rclone4gdrive</a> by <a rel="cc:attributionURL dct:creator" property="cc:attributionName" href="https://github.com/giuliocsr">giuliocsr</a> is licensed under <a href="http://creativecommons.org/licenses/by-nc-sa/4.0/?ref=chooser-v1" target="_blank" rel="license noopener noreferrer" style="display:inline-block;">CC BY-NC-SA 4.0<img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/cc.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/by.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/presskit/icons/nc.svg?ref=chooser-v1"><img style="height:22px!important;margin-left:3px;vertical-align:text-bottom;" src="https://mirrors.creativecommons.org/icons/sa.svg?ref=chooser-v1"></a></p>

https://github.com/giuliocsr
