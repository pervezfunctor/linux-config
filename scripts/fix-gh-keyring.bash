#!/usr/bin/env bash
set -euo pipefail

# Check for duplicate gh keyring entries (empty vs valid username)
# https://github.com/cli/cli/issues/6753

service="gh:github.com"
user="pervezfunctor"

if secret-tool lookup service "$service" username "" >/dev/null 2>&1; then
    echo "Found duplicate gh keyring entry with empty username. Removing..."
    secret-tool clear service "$service" username ""
    echo "Removed. Checking auth status..."
    if secret-tool lookup service "$service" username "$user" >/dev/null 2>&1; then
        echo "Valid entry for $user still present."
    else
        echo "No entry for $user. Run: gh auth login -h github.com -w"
    fi
    exit 0
fi

if secret-tool lookup service "$service" username "$user" >/dev/null 2>&1; then
    echo "gh keyring looks clean."
else
    echo "No gh keyring entry found. Run: gh auth login -h github.com -w"
    exit 1
fi
