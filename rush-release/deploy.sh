#!/usr/bin/env bash
set -euo pipefail
[[ "$DEPLOY_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]
install -d -m 700 ~/.ssh
printf '%s\n' "$DEPLOY_KEY" > ~/.ssh/rush
chmod 600 ~/.ssh/rush
printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > ~/.ssh/known_hosts
opts=(-i ~/.ssh/rush -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes)
host="$DEPLOY_USER@$DEPLOY_HOST"
stage="/srv/rush-updates/.incoming-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
ssh "${opts[@]}" "$host" "umask 022 && mkdir -m 700 '$stage'"
cleanup() { ssh "${opts[@]}" "$host" "rm -rf -- '$stage'" || true; }
trap cleanup EXIT
scp "${opts[@]}" rush-feed/{windows-x64.zip,stable.bin} rush-release/publish.py "$host:$stage/"
ssh "${opts[@]}" "$host" "chmod 644 '$stage/windows-x64.zip' '$stage/stable.bin' && python3 '$stage/publish.py' '$stage'"
