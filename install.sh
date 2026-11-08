#!/bin/sh
# Promento's installer.
#
#   curl -fsSL https://raw.githubusercontent.com/promento-ai/install/main/install.sh | sh
#
# It checks the machine, offers to install Docker when it is missing, asks which host runs Promento, and runs that
# host's own installer, which asks its own questions and starts Promento. Every question has a flag, for an
# unattended install:
#
#   … | sh -s -- --host docker --yes --registry-user <user> [--version vX.Y.Z] [--port 4300] [--public-url URL]
#
# with the registry token in PROMENTO_REGISTRY_TOKEN. Promento's images are private to the promento-ai
# organisation on GitHub: the token is a GitHub token that reads packages (read:packages).
set -eu

HOSTS="docker dokploy"
# PROMENTO_HOST_IMAGE runs another image of the Docker host, already on this machine: a build being tested.
DOCKER_HOST_IMAGE="${PROMENTO_HOST_IMAGE:-ghcr.io/promento-ai/service-host-docker:latest}"
DOKPLOY_HOST_README="https://github.com/promento-ai/service-host-dokploy#readme"
REGISTRY="ghcr.io"

host=""
yes=""
registry_user="${PROMENTO_REGISTRY_USER:-}"
registry_token="${PROMENTO_REGISTRY_TOKEN:-}"
passed=""

say() { printf '%s\n' "$*" >&2; }

# Whether a terminal can be asked: the script itself arrives on standard input when piped, so questions read /dev/tty.
has_tty() { [ -z "$yes" ] && (: </dev/tty) 2>/dev/null; }
fail() { say "promento: $*"; exit 1; }

ask() {
  question=$1
  default=${2:-}
  if ! has_tty; then
    printf '%s' "$default"
    return
  fi
  if [ -n "$default" ]; then printf '%s [%s] ' "$question" "$default" >/dev/tty; else printf '%s ' "$question" >/dev/tty; fi
  IFS= read -r answer </dev/tty || answer=""
  printf '%s' "${answer:-$default}"
}

ask_secret() {
  question=$1
  if ! has_tty; then return; fi
  printf '%s ' "$question" >/dev/tty
  stty -echo </dev/tty 2>/dev/null || true
  IFS= read -r answer </dev/tty || answer=""
  stty echo </dev/tty 2>/dev/null || true
  printf '\n' >/dev/tty
  printf '%s' "$answer"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) host=${2:-}; shift 2 ;;
    --yes|-y) yes=1; shift ;;
    --registry-user) registry_user=${2:-}; shift 2 ;;
    --version|--port|--public-url) passed="$passed $1 ${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,13p' "$0" 2>/dev/null || true; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

# Docker.
if ! command -v docker >/dev/null 2>&1; then
  case "$(uname -s)" in
    Linux)
      install_docker=$(ask "Docker is not installed. Install it now with Docker's own script (get.docker.com)? [y/N]" "n")
      case "$install_docker" in
        y|Y|yes) curl -fsSL https://get.docker.com | sh ;;
        *) fail "Promento runs in Docker. Install Docker, then run this again." ;;
      esac
      ;;
    *) fail "Promento runs in Docker. Install Docker Desktop (https://www.docker.com/products/docker-desktop/), then run this again." ;;
  esac
fi
docker info >/dev/null 2>&1 || fail "Docker is installed but does not answer: start it, or run this as a user allowed to use it."

# The host.
if [ -z "$host" ]; then
  say "Which host runs Promento?"
  say "  docker   Docker on this machine"
  say "  dokploy  a Dokploy you already run"
  host=$(ask "Host:" "docker")
fi
case " $HOSTS " in *" $host "*) ;; *) fail "unknown host $host: one of $HOSTS." ;; esac

if [ "$host" = "dokploy" ]; then
  say "The Dokploy host is deployed in Dokploy itself: follow $DOKPLOY_HOST_README"
  exit 0
fi

# The registry: Promento's images are private to promento-ai, and the host pulls the core and every service with
# the same user and token, so they are asked even when this machine's Docker is already signed in.
if [ -z "$registry_user" ] || [ -z "$registry_token" ]; then
  say "Promento's images are private: sign in to $REGISTRY with a GitHub account of promento-ai."
  [ -n "$registry_user" ] || registry_user=$(ask "GitHub user:" "")
  [ -n "$registry_token" ] || registry_token=$(ask_secret "GitHub token that reads packages (read:packages):")
fi
[ -n "$registry_user" ] && [ -n "$registry_token" ] || fail "a GitHub user and a token that reads packages are needed to pull Promento's images."
printf '%s' "$registry_token" | docker login "$REGISTRY" -u "$registry_user" --password-stdin >/dev/null 2>&1 || fail "$REGISTRY refused that user and token."
[ -n "${PROMENTO_HOST_IMAGE:-}" ] || docker pull -q "$DOCKER_HOST_IMAGE" >/dev/null || fail "$REGISTRY refused $DOCKER_HOST_IMAGE."

[ -n "$yes" ] && passed="$passed --yes"

# The host's own installer: it asks the rest, starts the core and itself, and says where Promento answers.
export PROMENTO_REGISTRY_USER="$registry_user" PROMENTO_REGISTRY_TOKEN="$registry_token"
if has_tty; then
  # shellcheck disable=SC2086
  exec docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock \
    -e PROMENTO_REGISTRY_USER -e PROMENTO_REGISTRY_TOKEN "$DOCKER_HOST_IMAGE" install $passed </dev/tty
fi
# shellcheck disable=SC2086
exec docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -e PROMENTO_REGISTRY_USER -e PROMENTO_REGISTRY_TOKEN "$DOCKER_HOST_IMAGE" install $passed
