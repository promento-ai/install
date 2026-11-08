# Installing Promento

```sh
curl -fsSL https://raw.githubusercontent.com/promento-ai/install/main/install.sh | sh
```

The script checks the machine, offers to install Docker when it is missing, asks which host runs Promento, and runs
that host's own installer, which asks its own questions and starts Promento:

- **docker** — Docker on this machine: a VPS, or your own computer. `service-host-docker` starts Promento's core and
  itself, then installs every other service.
- **dokploy** — a Dokploy you already run: `service-host-dokploy` is deployed in Dokploy, as its README says.

Promento's images are private to the `promento-ai` organisation: the script asks a GitHub user and a token that reads
packages (`read:packages`), and the host pulls with them.

## Unattended

```sh
PROMENTO_REGISTRY_TOKEN=<token> sh install.sh --host docker --yes --registry-user <user> \
  [--version vX.Y.Z] [--port 4300] [--public-url http://localhost:4300] \
  [--public-routing yes|no] [--https-email <e-mail>] [--tls-issuer acme|internal]
```

`--public-routing yes` lets the Docker host route the public addresses of the apps Promento runs, with HTTPS on ports
80 and 443 (`service-host-docker`'s README).

## Without piping a script into a shell

```sh
docker login ghcr.io -u <user>
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock \
  -e PROMENTO_REGISTRY_USER=<user> -e PROMENTO_REGISTRY_TOKEN=<token> \
  ghcr.io/promento-ai/service-host-docker:latest install
```

The design is `promento-ai/kernel` → `docs/superpowers/specs/2026-11-08-services-and-hosts-design.md` §11.
