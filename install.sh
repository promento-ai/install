#!/bin/sh
# Promento's installer.
#
#   curl -fsSL https://raw.githubusercontent.com/promento-ai/install/main/install.sh | sh -s -- \
#     --host dokploy --url https://<host> --key-file <path>
#
# It knows the kinds of host and each one's image, and nothing else of a platform: it pulls the host's image and runs
# that image's own installer, `<image> install`, with every flag that is not the script's. What it says goes to
# standard error; standard output is the installer's, and so is its exit status. `--help` lists its flags.
#
# Everything runs from `main`, called on the file's last line: a download cut short runs nothing.
set -eu

# The registry Promento's images are pulled from.
REGISTRY="ghcr.io"

# GitHub's device sign-in: GitHub CLI's OAuth application, as Promento's hub signs in, and where a code is approved.
GITHUB_CLIENT_ID="178c6fc778ccc68e1d6a"
DEVICE_ADDRESS="https://github.com/login/device"

# The kinds of host, and the image of each.
HOSTS="dokploy"
image_of() {
  case "$1" in
    dokploy) printf '%s' "$REGISTRY/promento-ai/service-host-dokploy" ;;
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
  Any other flag                Passed to the host's installer, untouched: the host's README lists its flags.

  PROMENTO_PLATFORM_KEY         The platform's key, when no file is named.
  PROMENTO_REGISTRY_USER        The GitHub user, when no flag names it.
  PROMENTO_REGISTRY_TOKEN       Its token, when no file is named.

Promento's images are private: a pull that is refused is made again signed in, with the user and the token given, or
with a sign-in approved on github.com, whose address and code the script prints.
USAGE
}

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

# A count of seconds GitHub answers, as a number the shell computes with: `$2` for none, nothing, or what is no number.
seconds() {
  case "$1" in
    '' | *[!0-9]*) printf '%s' "$2" ;;
    *)
      counted=$(printf '%s' "$1" | sed 's/^0*//')
      printf '%s' "${counted:-$2}"
      ;;
  esac
}

# One field of a form GitHub answers, `name=value&name=value`.
field() { printf '%s\n' "$1" | tr '&' '\n' | sed -n "s/^$2=//p" | head -n 1; }

# One call to GitHub, bounded: an address that does not answer ends it. What it sends that is secret arrives on its
# standard input, never as an argument.
github() { curl -fsS --connect-timeout 10 --max-time 30 "$@"; }

# GitHub's device sign-in, asking to read packages alone: the script prints an address and a code, and waits while the
# owner approves the code in any browser, on any machine. It sets the registry's user and token. Nothing is read from a
# terminal.
device_sign_in() {
  unanswered="GitHub does not answer: --registry-user and --registry-token-file give a user and a token instead."
  lapsed="the code was not approved in time: run the command again."

  started=$(printf 'client_id=%s&scope=read:packages' "$GITHUB_CLIENT_ID" |
    github -X POST https://github.com/login/device/code --data @-) || fail "$unanswered"
  device_code=$(field "$started" device_code)
  user_code=$(field "$started" user_code)
  [ -n "$device_code" ] && [ -n "$user_code" ] || fail "$unanswered"
  interval=$(seconds "$(field "$started" interval)" 5)
  expires_in=$(seconds "$(field "$started" expires_in)" 900)

  say "Promento's images are private: sign in to GitHub to read them."
  say "Open $DEVICE_ADDRESS and enter the code $user_code"

  waited=0
  while :; do
    sleep "$interval"
    waited=$((waited + interval))
    answer=$(printf 'client_id=%s&device_code=%s&grant_type=urn:ietf:params:oauth:grant-type:device_code' "$GITHUB_CLIENT_ID" "$device_code" |
      github -X POST https://github.com/login/oauth/access_token --data @-) || fail "$unanswered"
    registry_token=$(field "$answer" access_token)
    [ -z "$registry_token" ] || break
    case "$(field "$answer" error)" in
      authorization_pending) ;;
      slow_down) interval=$((interval + 5)) ;;
      expired_token) fail "$lapsed" ;;
      access_denied) fail "the sign-in was refused on GitHub." ;;
      *) fail "$unanswered" ;;
    esac
    [ "$waited" -lt "$expires_in" ] || fail "$lapsed"
  done

  account=$(printf 'header = "Authorization: Bearer %s"\n' "$registry_token" | github -K - https://api.github.com/user) ||
    fail "GitHub did not say whose sign-in this is."
  registry_user=$(printf '%s\n' "$account" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$registry_user" ] || fail "GitHub did not say whose sign-in this is."
}

main() {
  host=""
  version=""
  key_file=""
  token_file=""
  yes=""
  registry_user="${PROMENTO_REGISTRY_USER:-}"
  registry_token="${PROMENTO_REGISTRY_TOKEN:-}"
  # The platform's key is the installer's alone: no other command the script runs is started with it.
  platform_key="${PROMENTO_PLATFORM_KEY:-}"
  unset PROMENTO_PLATFORM_KEY PROMENTO_REGISTRY_USER PROMENTO_REGISTRY_TOKEN

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
      --yes)
        yes=1
        continue
        ;;
      --help)
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
    case "$version" in
      *[!v0-9.]*) fail "--version is a version, v<x.y.z>." ;;
    esac
    printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "--version is a version, v<x.y.z>."
  fi
  image="$(image_of "$host"):${version:-latest}"

  # The platform's key and the registry's token, each read from its file.
  if [ -n "$key_file" ]; then
    platform_key=$(content_of "$key_file")
    [ -n "$platform_key" ] || fail "$key_file holds no key."
  fi
  if [ -n "$token_file" ]; then
    registry_token=$(content_of "$token_file")
    [ -n "$registry_token" ] || fail "$token_file holds no token."
  fi

  docker info > /dev/null 2>&1 || fail "Docker does not answer: start it, or run this as a user allowed to use it."

  # A sign-in to the registry is written in a Docker configuration directory of the run's own, removed once the image
  # is pulled, and at the run's end whatever the end, a terminal that hangs up among them: this machine's Docker keeps
  # no login of Promento's.
  config=""
  trap '[ -z "$config" ] || rm -rf "$config"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 141' PIPE
  trap 'exit 143' TERM

  # The pull, tried first with no sign-in: this machine's Docker may read Promento's images already. One the registry
  # refuses is made again signed in, once: with the user and the token given, or, when Docker says `unauthorized`, with
  # a sign-in approved on GitHub. A pull that fails for anything else is said as Docker says it.
  say "Pulling $image"
  if ! refusal=$(docker pull "$image" 2>&1); then
    said=$(printf '%s\n' "$refusal" | tail -n 1)
    lowered=$(printf '%s' "$refusal" | tr '[:upper:]' '[:lower:]')
    if [ -n "$registry_user" ] && [ -n "$registry_token" ]; then
      case "$lowered" in
        *unauthorized* | *denied*) ;;
        *) fail "$said" ;;
      esac
    else
      case "$lowered" in
        *unauthorized*) ;;
        *) fail "$said" ;;
      esac
      [ -z "$yes" ] ||
        fail "Promento's images are private: --registry-user and --registry-token-file give a GitHub user and a token that reads packages."
      device_sign_in
    fi
    config=$(mktemp -d)
    # A configuration that holds an entry is written by Docker itself, and by no credential helper of the machine's.
    printf '{"auths":{"%s":{}}}\n' "$REGISTRY" > "$config/config.json"
    printf '%s' "$registry_token" | docker --config "$config" login "$REGISTRY" -u "$registry_user" --password-stdin > /dev/null 2>&1 ||
      fail "$REGISTRY refused that user and token."
    refusal=$(docker --config "$config" pull "$image" 2>&1) || fail "$(printf '%s\n' "$refusal" | tail -n 1)"
    rm -rf "$config"
    config=""
  fi

  # The registry's user and token go to the installer together or not at all, for its platform's own pulls; the
  # platform's key when there is one. Each variable is named and not written: its value is in no argument.
  if [ -n "$registry_user" ] && [ -n "$registry_token" ]; then
    PROMENTO_REGISTRY_USER=$registry_user
    PROMENTO_REGISTRY_TOKEN=$registry_token
    export PROMENTO_REGISTRY_USER PROMENTO_REGISTRY_TOKEN
  fi
  if [ -n "$platform_key" ]; then
    PROMENTO_PLATFORM_KEY=$platform_key
    export PROMENTO_PLATFORM_KEY
  fi

  # The host's installer, with the machine's Docker socket and network, attached to the terminal when there is one.
  # The script ends with the installer's status.
  status=0
  if has_tty; then
    docker run --rm -it --network host -v /var/run/docker.sock:/var/run/docker.sock \
      -e PROMENTO_PLATFORM_KEY -e PROMENTO_REGISTRY_USER -e PROMENTO_REGISTRY_TOKEN "$image" install "$@" < /dev/tty || status=$?
  else
    docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock \
      -e PROMENTO_PLATFORM_KEY -e PROMENTO_REGISTRY_USER -e PROMENTO_REGISTRY_TOKEN "$image" install "$@" || status=$?
  fi
  exit "$status"
}

main "$@"
