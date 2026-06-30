# Deployment

How to deploy the `sandbox` control plane on **Windows, macOS, and Linux**, how to
**rebuild** it after changes, and how to **cut a release**.

`sandbox` is an E2B-compatible control plane: point the standard
[E2B SDK](https://github.com/e2b-dev/e2b) at it and it runs commands/files in
local **Docker** containers. We run the **Docker backend on every platform** —
this guide covers only that (no Tart/Shuru VM backends).

- [Prerequisites](#prerequisites)
- [Install (from source) — recommended](#install-from-source--recommended)
- [First run & configuration](#first-run--configuration)
- [Connecting a client (E2B SDK)](#connecting-a-client-e2b-sdk)
- [Rebuilding after changes](#rebuilding-after-changes)
- [Cutting a release](#cutting-a-release)
- [Running it as a service](#running-it-as-a-service)
- [Troubleshooting](#troubleshooting)

Everything below builds from our fork
**[`benlavalley/sandbox`](https://github.com/benlavalley/sandbox/tree/windows-support)**,
branch **`windows-support`**. Override the repo/branch anywhere below with the
`SANDBOX_REPO` / `SANDBOX_BRANCH` environment variables.

---

## Prerequisites

|              | macOS                 | Linux            | Windows                                        |
| ------------ | --------------------- | ---------------- | ---------------------------------------------- |
| **Docker**   | Docker Desktop        | Docker Engine    | Docker Desktop **+ TCP enabled** (see below)   |
| **git**      | ✓ (Xcode CLT)         | ✓                | [Git for Windows](https://git-scm.com/download/win) |
| **Bun**      | auto-installed by the installer | same   | same                                           |

### Windows only — expose the Docker TCP endpoint

The compiled binary runs on the Bun runtime, which **cannot open the Windows
Docker named pipe**. So on Windows the CLI talks to Docker over TCP. In Docker
Desktop enable:

> **Settings → General → "Expose daemon on `tcp://localhost:2375` without TLS"** → Apply & restart.

`sandbox` defaults `DOCKER_SOCKET` to `tcp://localhost:2375` on Windows, so once
that's on, no extra config is needed.

> ⚠️ `2375` without TLS is an **unauthenticated** Docker endpoint. It's bound to
> localhost — fine for a dev box, but anything that can reach `localhost:2375`
> controls Docker. Don't enable it on a shared/exposed machine.

---

## Install (from source) — recommended

The installers clone the repo at a branch and compile the binary with Bun. No
published release is required, and they always build the branch's latest commit.

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/benlavalley/sandbox/windows-support/scripts/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/benlavalley/sandbox/windows-support/scripts/install.ps1 | iex
```

Each installer ensures git + Bun (installs Bun if missing), clones the branch,
runs `bun build --compile`, and installs the binary onto your PATH:

| OS          | Install location                                  |
| ----------- | ------------------------------------------------- |
| macOS/Linux | first writable PATH dir: `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin` |
| Windows     | `%LOCALAPPDATA%\Programs\sandbox\sandbox.exe`     |

Override with env vars before running: `SANDBOX_REPO`, `SANDBOX_BRANCH`, `PREFIX`
(install dir).

> The installer prints the install path; make sure it's on your `PATH`. On
> Windows it also prints the `setx PATH ...` command to add it permanently.

---

## First run & configuration

```bash
sandbox serve        # macOS / Linux
sandbox.exe serve    # Windows
```

On start it prints the API key and where it's stored, and the ports it's on:

```
API key: e2b_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Config:  /Users/<you>/.sandbox/config.json      # Windows: C:\Users\<you>\.sandbox\config.json

Control plane listening on :49982
Envd proxy listening on :49983
```

- The key is generated once, stored in `~/.sandbox/config.json`, and reused. It's
  printed on **every** start so it's always discoverable.
- **`:49982`** — control plane (create / list / kill). **`:49983`** — envd data-plane proxy.

### Docker base image

The first `Sandbox.create("base")` looks for a local image `sandbox-base:latest`,
otherwise pulls `ghcr.io/circlesac/sandbox-base:latest`. If the pull fails
(image private/unavailable), build it locally from a checkout of this repo:

```bash
docker build -t sandbox-base:latest docker/sandbox
```

> The from-source installer clones to a temp dir and deletes it, so to build the
> base image keep a normal `git clone` of the repo around.

### Environment variables

| Var               | Default                                                       | Notes                                            |
| ----------------- | ------------------------------------------------------------- | ------------------------------------------------ |
| `API_KEYS`        | from `~/.sandbox/config.json`                                 | comma-separated; if set, skips the config file   |
| `DOCKER_SOCKET`   | `/var/run/docker.sock` (mac/Linux), `tcp://localhost:2375` (Windows) | unix socket, `npipe://`, or `tcp://host:port` |
| `PORT`            | `49982`                                                       | control-plane port                               |
| `SANDBOX_BACKEND` | `docker`                                                      | leave as `docker`                                |

---

## Connecting a client (E2B SDK)

```ts
import { Sandbox } from "e2b";

const HOST = "http://localhost:49982"; // or http://<server-ip>:49982
const opts = {
  apiUrl: HOST,          // control plane: create / list / kill
  sandboxUrl: HOST,      // data plane: commands / files / envd
  apiKey: "e2b_...",     // the key from ~/.sandbox/config.json
  validateApiKey: false, // only needed if your key isn't e2b_<hex> format
};

const sb = await Sandbox.create("base", opts);
console.log((await sb.commands.run("echo hello")).stdout); // "hello\n"
```

> **`sandboxUrl` is required** and must match `apiUrl`. The SDK does **not** fall
> back from `sandboxUrl` to `apiUrl` — without it, `commands.run`/`files.*` go to
> e2b's cloud and fail with `13: [internal] HTTP 400` (while create/list still
> appear to work, since those use `apiUrl`).

---

## Rebuilding after changes

Pick the loop that matches how it's installed.

**Installed from source (the common case)** — push, then re-run the installer,
which re-clones HEAD and rebuilds:

```bash
git push                       # push your branch
# then on each machine, re-run install.sh / install.ps1 (same commands as above)
```

**Local working copy** — rebuild in place:

```bash
cd cli
bun install
bun build --compile src/index.ts --outfile sandbox            # host target
# macOS only — re-sign so it runs:
codesign --remove-signature sandbox && codesign --force --deep -s - sandbox
# Install onto a PATH dir you own. /usr/local/bin is root-owned on Apple
# Silicon (use sudo there, or ~/.local/bin). Restart `sandbox serve` after.
install -m 0755 sandbox /opt/homebrew/bin/sandbox                 # put it on PATH
```

**Dev mode (no compile)** — runs straight from TypeScript, picks up edits on restart:

```bash
cd cli && bun run dev serve
```

> Only the host CLI is TypeScript. `envd-lite` (Go) runs **inside** the Linux
> container, so host-side CLI changes never require rebuilding it.

---

## Cutting a release

A release publishes prebuilt binaries for every platform to GitHub, so machines
can install without compiling.

1. **Bump the version** in `cli/package.json` (e.g. `27.0.0` → `27.0.1`).
2. **Commit + push** — the release tag is pinned to the pushed commit, so the
   bump must be on the remote first.
3. **Publish** (requires `gh` authenticated — `brew install gh && gh auth login`):

   ```bash
   scripts/release.sh        # builds all targets + publishes vX.Y.Z to your fork (origin)
   ```

`release.sh` runs `scripts/build.sh` (Bun cross-compiles macOS arm64/x64, Linux
x64/arm64, and Windows x64 from one machine), then `gh release create vX.Y.Z`
with the tarballs attached.

- **Build only, no publish:** `scripts/build.sh` → tarballs land in `cli/dist/`.
- **Different target repo:** `SANDBOX_RELEASE_REPO=owner/repo scripts/release.sh`.
- A release **won't overwrite an existing tag** — bump the version each time.

### Installing a prebuilt release (instead of from source)

`release.sh` uploads the per-platform tarballs to the fork's releases page —
[`benlavalley/sandbox/releases`](https://github.com/benlavalley/sandbox/releases).
To use one without compiling: download the tarball for your platform, extract the
binary (`sandbox`, or `sandbox.exe` on Windows), and put it on your PATH.

> The npm package `@circlesac/sandbox` and `cli/bin/install.sh` belong to the
> **upstream** project and pull from `circlesac/sandbox`. The npm postinstall
> (`install.js`) honors `SANDBOX_RELEASE_REPO=benlavalley/sandbox` if you wire the
> fork into an npm install — but for us the **from-source installers above are the
> supported path.**

---

## Running it as a service

`sandbox serve` runs in the foreground. To keep it running across reboots:

- **macOS:** `sandbox service install` (creates a launchd LaunchAgent;
  `service uninstall` / `service status` too).
- **Linux:** run it under **systemd** — a unit that execs `sandbox serve`.
- **Windows:** use **Task Scheduler** or a service wrapper (e.g.
  [NSSM](https://nssm.cc/)). The built-in `service` command is macOS-only.

---

## Troubleshooting

| Symptom                                                                 | Cause                                              | Fix                                                                                  |
| ----------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `✖ Cannot reach the Docker daemon` / `FailedToOpenSocket` / `ECONNREFUSED` at startup | Docker not running, or (Windows) TCP not enabled   | Start Docker. On Windows enable `tcp://localhost:2375` (see Prerequisites) or set `DOCKER_SOCKET`. |
| `13: [internal] HTTP 400` on `commands.run`/`files.*` (create/list work) | Client `opts` missing `sandboxUrl`                 | Set `sandboxUrl` to the same URL as `apiUrl`.                                         |
| `AuthenticationError: Invalid API key format`                           | SDK rejects a non-`e2b_` key client-side           | Use an `e2b_<hex>` key, or pass `validateApiKey: false`.                              |
| `Template "base" not found`                                             | Base image missing and ghcr pull failed            | `docker build -t sandbox-base:latest docker/sandbox`.                                 |
| `bun install` fails with `HTTP 404` (postinstall)                       | Version has no published release on the pinned repo | Building from source skips this automatically; for prebuilt set `SANDBOX_RELEASE_REPO` or release that version first. |
