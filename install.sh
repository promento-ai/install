#!/bin/sh
# Promento's installer.
#
#   curl -fsSL https://raw.githubusercontent.com/promento-ai/install/main/install.sh | sh -s -- \
#     --host dokploy --url https://<host> --key-file <path>
#
# It knows the kinds of host and each one's image, and nothing else of a platform: it pulls the host's image and runs
# that image's own installer, `<image> install`, with every flag that is not the script's. What it says goes to
# standard error; standard output is the installer's, and so is its exit status. `--help` lists its flags.
set -eu

# The kinds of host, and the image of each.
HOSTS="dokploy"
image_of() {
  case "$1" in
    dokploy) printf '%s' "ghcr.io/promento-ai/service-host-dokploy" ;;
  esac
}

usage() {
  cat << 'USAGE'
Installs Promento: pulls the host's image and runs its installer.

  --host <kind>                 The kind of host: dokploy. Asked on a terminal when it is not given.
  --version v<x.y.z>            The host's version. The newest released when it is not given.
  --key-file <path>             A file that holds the platform's key.
  --registry-user <user>        A GitHub user that reads Promento's images.
  --registry-token-file <path>  A file that holds that user's token, which reads packages (read:packages).
  --yes                         Nothing is asked: what is missing fails, naming its flag.
  --help                        This text.
  Any other flag                Passed to the host's installer: `--host <kind> --help` lists them.

  PROMENTO_PLATFORM_KEY         The platform's key, when no file is named.
  PROMENTO_REGISTRY_USER        The GitHub user, when no flag names it.
  PROMENTO_REGISTRY_TOKEN       Its token, when no file is named.

Promento's images are private: a pull that is refused is made again signed in, with the user and the token given, or
with a sign-in approved on github.com, whose address and code the script prints.
USAGE
}

host=""
version=""
key_file=""
token_file=""
yes=""
registry_user="${PROMENTO_REGISTRY_USER:-}"
registry_token="${PROMENTO_REGISTRY_TOKEN:-}"

say() { printf '%s\n' "$*" >&2; }
fail() {
  say "promento: $*"
  exit 1
}

# Whether a terminal can be asked: the script itself arrives on standard input when piped, so questions read /dev/tty.
has_tty() { [ -z "$yes" ] && (: < /dev/tty) 2> /dev/null; }

# A file's content, without the spaces around it: empty for a file that is missing, unreadable or blank.
content_of() {
  [ -r "$1" ] || return 0
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | sed -e '/^$/d'
}

# The script's flags are read, each `--flag value` or `--flag=value`; every other argument is kept, in order, for the
# host's installer.
remaining=$#
while [ "$remaining" -gt 0 ]; do
  argument=$1
  shift
  remaining=$((remaining - 1))
  case "$argument" in
    --host | --version | --key-file | --registry-user | --registry-token-file)
      [ "$remaining" -gt 0 ] || fail "$argument takes a value."
      flag=$argument
      value=$1
      shift
      remaining=$((remaining - 1))
      ;;
    --host=* | --version=* | --key-file=* | --registry-user=* | --registry-token-file=*)
      flag=${argument%%=*}
      value=${argument#*=}
      ;;
    --yes | -y)
      yes=1
      continue
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      set -- "$@" "$argument"
      continue
      ;;
  esac
  [ -n "$value" ] || fail "$flag takes a value."
  case "$flag" in
    --host) host=$value ;;
    --version) version=$value ;;
    --key-file) key_file=$value ;;
    --registry-user) registry_user=$value ;;
    --registry-token-file) token_file=$value ;;
  esac
done

# The kind of host.
if [ -z "$host" ]; then
  has_tty || fail "--host names the kind of host: one of $HOSTS."
  printf 'The kind of host (%s): ' "$HOSTS" > /dev/tty
  IFS= read -r host < /dev/tty || host=""
fi
case " $HOSTS " in
  *" $host "*) ;;
  *) fail "unknown host $host: one of $HOSTS." ;;
esac

# The host's version: the image's tag.
if [ -n "$version" ]; then
  printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "--version is a version, v<x.y.z>."
fi
image="$(image_of "$host"):${version:-latest}"

# The platform's key and the registry's token, each read from its file into the variable the installer reads.
if [ -n "$key_file" ]; then
  PROMENTO_PLATFORM_KEY=$(content_of "$key_file")
  [ -n "$PROMENTO_PLATFORM_KEY" ] || fail "$key_file holds no key."
  export PROMENTO_PLATFORM_KEY
fi
if [ -n "$token_file" ]; then
  registry_token=$(content_of "$token_file")
  [ -n "$registry_token" ] || fail "$token_file holds no token."
fi

docker info > /dev/null 2>&1 || fail "Docker does not answer: start it, or run this as a user allowed to use it."
