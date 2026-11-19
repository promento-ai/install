#!/bin/sh
# The tests of install.sh: `sh tests/run.sh`.
#
# Each case runs the script whole, as the owner runs it, with stand-ins for docker, curl and sleep first on PATH
# (tests/stubs). A case has a directory of its own: it writes there what the stand-ins answer, and reads there what
# they were given. Every case runs with no terminal: where one is attached, the cases run in a session of their own.
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../install.sh"

# A terminal attached would be asked: the cases start again in a session that has none.
if (: < /dev/tty) 2> /dev/null && [ -z "${PROMENTO_TESTS_DETACHED:-}" ]; then
  if command -v setsid > /dev/null 2>&1; then
    PROMENTO_TESTS_DETACHED=1 exec setsid -w sh "$0" "$@"
  fi
  printf 'tests/run.sh: a terminal is attached and setsid is missing: run it with no terminal.\n' >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
cases=0
name=""
dir=""
status=0
bad=0

# Starts a case: a directory of its own, and none of the script's variables.
start() {
  finish
  name=$1
  cases=$((cases + 1))
  dir="$work/$cases"
  mkdir -p "$dir"
  : > "$dir/docker.calls"
  : > "$dir/curl.calls"
  : > "$dir/sleep.calls"
  bad=0
  unset PROMENTO_PLATFORM_KEY PROMENTO_REGISTRY_USER PROMENTO_REGISTRY_TOKEN
}

# Ends the case in hand, saying whether it passed.
finish() {
  [ -n "$name" ] || return 0
  if [ "$bad" -eq 0 ]; then printf 'ok %s\n' "$name"; else failures=$((failures + 1)); fi
  name=""
}

wrong() {
  [ "$bad" -ne 0 ] || printf 'not ok %s\n' "$name"
  bad=1
  printf '  %s\n' "$1"
}

# Runs install.sh with the arguments given; its status, standard output and standard error are kept.
run() {
  status=0
  PATH="$here/stubs:$PATH" PROMENTO_TEST_DIR="$dir" sh "$script" "$@" > "$dir/out" 2> "$dir/err" || status=$?
}

status_is() { [ "$status" -eq "$1" ] || wrong "status $status, expected $1"; }
# A whole line of standard error.
says() { grep -Fxq -- "$1" "$dir/err" || wrong "standard error lacks the line: $1 (it holds: $(tr '\n' '|' < "$dir/err"))"; }
# A whole line of a file of the case's.
has() { grep -Fxq -- "$2" "$dir/$1" || wrong "$1 lacks the line: $2 (it holds: $(tr '\n' '|' < "$dir/$1" 2> /dev/null))"; }
# Some text anywhere in a file of the case's.
holds() { grep -Fq -- "$2" "$dir/$1" || wrong "$1 does not hold: $2"; }
lacks() { if grep -Fq -- "$2" "$dir/$1" 2> /dev/null; then wrong "$1 holds: $2"; fi; }
empty() { [ ! -s "$dir/$1" ] || wrong "$1 is not empty: $(tr '\n' '|' < "$dir/$1")"; }
nothing_called() {
  empty docker.calls
  empty curl.calls
  empty sleep.calls
}

IMAGE="ghcr.io/promento-ai/service-host-dokploy"

# --- The flags ------------------------------------------------------------------------------------------------------

start "a kind of host the script does not know is refused before anything is touched"
run --host nope --yes
status_is 1
says "promento: unknown host nope: one of dokploy."
nothing_called

start "the Docker host is no kind the script knows"
run --host docker --yes
status_is 1
says "promento: unknown host docker: one of dokploy."
nothing_called

start "with no terminal, the kind of host is required"
run --yes
status_is 1
says "promento: --host names the kind of host: one of dokploy."
nothing_called

start "a version is v<x.y.z>"
for version in 1.2.3 latest v1.2 v1.2.3-rc.1 "v1.2.3 x"; do
  run --host dokploy --version "$version" --yes
  status_is 1
  says "promento: --version is a version, v<x.y.z>."
done
nothing_called

start "a key's file that is missing, empty or of spaces alone holds no key"
: > "$dir/empty"
printf '  \n\n' > "$dir/spaces"
for file in "$dir/missing" "$dir/empty" "$dir/spaces"; do
  run --host dokploy --key-file "$file" --yes
  status_is 1
  says "promento: $file holds no key."
done
nothing_called

start "a token's file that is missing holds no token"
run --host dokploy --registry-user octo --registry-token-file "$dir/missing" --yes
status_is 1
says "promento: $dir/missing holds no token."
nothing_called

start "a flag of the script's that has no value says so"
for flag in --host --version --key-file --registry-user --registry-token-file; do
  run "$flag"
  status_is 1
  says "promento: $flag takes a value."
done
nothing_called

start "--help prints the flags and touches nothing"
run --help
status_is 0
for flag in --host --version --key-file --registry-user --registry-token-file --yes PROMENTO_PLATFORM_KEY; do holds out "$flag"; done
empty err
nothing_called

start "a Docker that does not answer ends the run"
printf '1' > "$dir/docker.info"
run --host dokploy --yes
status_is 1
says "promento: Docker does not answer: start it, or run this as a user allowed to use it."
has docker.calls "<info>"

# --- The pull, and the installer ------------------------------------------------------------------------------------

RUN="<run> <--rm> <--network> <host> <-v> </var/run/docker.sock:/var/run/docker.sock> <-e> <PROMENTO_PLATFORM_KEY> <-e> <PROMENTO_REGISTRY_USER> <-e> <PROMENTO_REGISTRY_TOKEN>"

start "the host's image is pulled, and its installer run with the key of the file and the flags that are not the script's"
printf 'the-key-of-the-file\n' > "$dir/key"
run --host dokploy --url https://promento.example --key-file "$dir/key"
status_is 0
has docker.calls "<pull> <$IMAGE:latest>"
has docker.calls "$RUN <$IMAGE:latest> <install> <--url> <https://promento.example>"
has docker.env "PROMENTO_PLATFORM_KEY=the-key-of-the-file"
has docker.env "PROMENTO_REGISTRY_USER unset"
has docker.env "PROMENTO_REGISTRY_TOKEN unset"
lacks docker.calls "the-key-of-the-file"
lacks err "the-key-of-the-file"
has out "Promento answers at https://promento.example"
empty curl.calls

start "a version named is the image's tag, in the pull and in the run"
run --host=dokploy --version=v0.10.0 --url https://promento.example
status_is 0
has docker.calls "<pull> <$IMAGE:v0.10.0>"
has docker.calls "$RUN <$IMAGE:v0.10.0> <install> <--url> <https://promento.example>"

start "with no file, the key is the variable's"
PROMENTO_PLATFORM_KEY="the-key-of-the-variable"
export PROMENTO_PLATFORM_KEY
run --host dokploy --url https://promento.example
status_is 0
has docker.env "PROMENTO_PLATFORM_KEY=the-key-of-the-variable"
lacks docker.calls "the-key-of-the-variable"

start "with no key at all, the installer is given none: it asks, or says what is missing"
run --host dokploy --url https://promento.example
status_is 0
has docker.env "PROMENTO_PLATFORM_KEY unset"

start "every flag that is not the script's reaches the installer as it was written, one argument each"
run --dokploy-url "http://a b" --host dokploy "--other=x y" --flag --yes "it's \"quoted\""
status_is 0
has docker.calls "$RUN <$IMAGE:latest> <install> <--dokploy-url> <http://a b> <--other=x y> <--flag> <it's \"quoted\">"

start "the script ends with the installer's status"
printf '3' > "$dir/docker.run"
run --host dokploy --url https://promento.example
status_is 3

start "a pull that fails for anything but a refusal is said as Docker says it, and nothing more is tried"
for message in "Error response from daemon: denied" "Error response from daemon: dial tcp: connect: connection refused"; do
  : > "$dir/docker.calls"
  printf '1|%s\n' "$message" > "$dir/docker.pull"
  run --host dokploy --url https://promento.example
  status_is 1
  says "promento: $message"
  lacks docker.calls "<login>"
  lacks docker.calls "<run>"
done
empty curl.calls

start "with no terminal, the installer is attached to none"
run --host dokploy --url https://promento.example
status_is 0
lacks docker.calls "<-it>"

# --- A pull refused, with a user and a token given ------------------------------------------------------------------

REFUSED="1|Error response from daemon: Head \"https://ghcr.io/v2/promento-ai/service-host-dokploy/manifests/latest\": unauthorized"
NEEDS_SIGN_IN="promento: Promento's images are private: --registry-user and --registry-token-file give a GitHub user and a token that reads packages."

# The configuration directory `login` was given, and whether it is still there.
config_dir() { sed -n 's/ exists$//p' "$dir/docker.config" 2> /dev/null; }
config_removed() {
  made=$(config_dir)
  [ -n "$made" ] || wrong "login was given no configuration directory that exists (docker.config: $(cat "$dir/docker.config" 2> /dev/null))"
  [ -z "$made" ] || [ ! -e "$made" ] || wrong "the configuration directory $made is left behind"
}

start "a pull refused is made again signed in, with the user and the token of a file, in a directory of the run's own"
printf '%s\n0|\n' "$REFUSED" > "$dir/docker.pull"
printf 'the-token-of-the-file\n' > "$dir/token"
run --host dokploy --url https://promento.example --registry-user octo --registry-token-file "$dir/token"
status_is 0
made=$(config_dir)
has docker.calls "<pull> <$IMAGE:latest>"
has docker.calls "<--config> <$made> <login> <ghcr.io> <-u> <octo> <--password-stdin>"
has docker.calls "<--config> <$made> <pull> <$IMAGE:latest>"
has docker.stdin "the-token-of-the-file"
has docker.env "PROMENTO_REGISTRY_USER=octo"
has docker.env "PROMENTO_REGISTRY_TOKEN=the-token-of-the-file"
lacks docker.calls "the-token-of-the-file"
lacks err "the-token-of-the-file"
config_removed
empty curl.calls

start "the user and the token of the variables sign in the same"
printf '%s\n0|\n' "$REFUSED" > "$dir/docker.pull"
PROMENTO_REGISTRY_USER=octo
PROMENTO_REGISTRY_TOKEN="the-token-of-the-variable"
export PROMENTO_REGISTRY_USER PROMENTO_REGISTRY_TOKEN
run --host dokploy --url https://promento.example --yes
status_is 0
has docker.stdin "the-token-of-the-variable"
has docker.env "PROMENTO_REGISTRY_TOKEN=the-token-of-the-variable"
lacks docker.calls "the-token-of-the-variable"
config_removed

start "a login the registry refuses ends the run, and leaves nothing"
printf '%s\n' "$REFUSED" > "$dir/docker.pull"
printf '1' > "$dir/docker.login"
printf 'the-token\n' > "$dir/token"
run --host dokploy --url https://promento.example --registry-user octo --registry-token-file "$dir/token"
status_is 1
says "promento: ghcr.io refused that user and token."
lacks docker.calls "<run>"
config_removed

start "a second pull that fails is said as Docker says it, and leaves nothing"
printf '%s\n1|Error response from daemon: manifest unknown\n' "$REFUSED" > "$dir/docker.pull"
printf 'the-token\n' > "$dir/token"
run --host dokploy --url https://promento.example --registry-user octo --registry-token-file "$dir/token"
status_is 1
says "promento: Error response from daemon: manifest unknown"
lacks docker.calls "<run>"
config_removed

start "with --yes and nothing given, a pull refused names the two flags, and GitHub is not asked"
printf '%s\n' "$REFUSED" > "$dir/docker.pull"
run --host dokploy --url https://promento.example --yes
status_is 1
says "$NEEDS_SIGN_IN"
lacks docker.calls "<login>"
empty curl.calls

start "with --yes, a user with no token is nothing given"
printf '%s\n' "$REFUSED" > "$dir/docker.pull"
run --host dokploy --url https://promento.example --registry-user octo --yes
status_is 1
says "$NEEDS_SIGN_IN"
empty curl.calls

start "after a sign-in, the script still ends with the installer's status, and leaves nothing"
printf '%s\n0|\n' "$REFUSED" > "$dir/docker.pull"
printf '3' > "$dir/docker.run"
printf 'the-token\n' > "$dir/token"
run --host dokploy --url https://promento.example --registry-user octo --registry-token-file "$dir/token"
status_is 3
config_removed

finish
printf '%s cases, %s failed\n' "$cases" "$failures"
[ "$failures" -eq 0 ]
