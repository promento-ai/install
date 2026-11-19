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

finish
printf '%s cases, %s failed\n' "$cases" "$failures"
[ "$failures" -eq 0 ]
