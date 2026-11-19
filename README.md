# Installing Promento

One command, run on the machine that holds the platform Promento runs on:

```sh
curl -fsSL https://raw.githubusercontent.com/promento-ai/install/main/install.sh | sh -s -- \
  --host dokploy --url https://<host> --key-file <path>
```

The command names a kind of host and what that host's platform asks. The script pulls the host's image and runs that image's own
installer, which makes the host; the host then installs Promento, and the command ends on two lines: where Promento
answers, and the link that opens its setup. The script knows the kinds of host and each one's image, and nothing else of
a platform.

| Kind | What it is | Its installer's flags |
| --- | --- | --- |
| `dokploy` | A Dokploy you already run: `ghcr.io/promento-ai/service-host-dokploy`. | `--url https://<host>`, Promento's address, and `--dokploy-url <url>`: [its README](https://github.com/promento-ai/service-host-dokploy#installing-it). |

## Its flags

| Flag or variable | What it is |
| --- | --- |
| `--host <kind>` | The kind of host. Asked on a terminal; without one, required. |
| `--version v<x.y.z>` | The host's version. Without it, the newest released: the image's tag `latest`. |
| `--key-file <path>` | A file that holds the platform's key. The script reads it into `PROMENTO_PLATFORM_KEY` for the installer. |
| `PROMENTO_PLATFORM_KEY` | The platform's key, when no file is named. With neither, the installer asks it on a terminal. |
| `--registry-user <user>`, `PROMENTO_REGISTRY_USER` | A GitHub user that reads Promento's images. |
| `--registry-token-file <path>`, `PROMENTO_REGISTRY_TOKEN` | That user's token, which reads packages (`read:packages`): a file, or the variable when no file is named. |
| `--yes` | Nothing is asked: what is missing fails, naming its flag. |
| `--help` | The flags. |
| Any other flag | Passed to the host's installer, untouched. |

A key is never a flag's value: it comes by a file or a variable, and is in no argument of any command the script runs.
What the script says goes to standard error; standard output and the exit status are the installer's.

## Signing in to the registry

Promento's images are private. The script pulls first with no sign-in: a machine whose Docker reads them already is
asked nothing, and its login is neither read nor changed. A pull the registry refuses is made again signed in, with a
GitHub user and a token:

- **Given**, by the flags or the variables above.
- **Or obtained with a code approved on GitHub.** The script prints an address and a code,
  `https://github.com/login/device` and eight characters, and waits: open the address in any browser, on any machine,
  enter the code and approve. It asks to read packages, and nothing else. Nothing is typed in the terminal. With
  `--yes` and no token given, the script fails instead, naming the flags.

A user and a token given are tried on any refusal of the registry's; the code is asked only when Docker says
`unauthorized`, and any other failure of the pull is said as Docker says it.

The sign-in is written in a Docker configuration directory made for the run, by Docker itself and by no credential
helper of the machine's, and removed once the image is pulled, and at the run's end whatever the end, a terminal that
hangs up among them: the machine's Docker keeps no login of Promento's. Each call to GitHub is bounded at 30 seconds,
and the wait for the approval at the code's own life, fifteen minutes. The script then hands the user and the token to the installer, for
the platform's own pulls. It leaves no file and no container.

## Unattended, and by an agent

```sh
sh install.sh --host dokploy --url https://<host> --key-file <path> \
  --registry-user <user> --registry-token-file <path> --yes
```

An agent that holds a shell on the machine installs Promento without ever holding a secret: it names the key's file,
which the owner wrote, and never reads it; and with no token given and no `--yes`, it relays to the owner the address
and the code the script prints, and the owner approves them.

## Run again

The command run again goes on from the first step not done. On a Promento whose setup is open it prints the setup's
link again; on one that is set up, its address alone.

## Its tests

```sh
sh tests/run.sh
```

They run the script whole, with stand-ins for `docker`, `curl` and `sleep` first on `PATH` (`tests/stubs`), each
writing what it is given where the test reads it. `Check` (`.github/workflows/check.yml`) runs ShellCheck on the script
and its tests, then the tests, on every push.

The design is `promento-ai/core` → `docs/superpowers/specs/2026-11-19-one-command-install-design.md`.
