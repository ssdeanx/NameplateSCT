#!/usr/bin/env bash
# Runs every harness in this folder. Each harness is a plain lua5.1 script that stubs
# the client API, so the addon's combat path can be proven without launching WoW.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

LUA="${LUA:-lua5.1}"
status=0

for harness in Tests/harness/*_test.lua; do
	echo "== ${harness}"
	if ! "$LUA" "${harness}"; then
		status=1
	fi
	echo
done

if [ "$status" -eq 0 ]; then
	echo "TOTAL: all harnesses passed"
else
	echo "TOTAL: failures above"
fi

exit "$status"
