#!/usr/bin/env bash
# Publishes a directory of CI logs to the "ci-logs" branch of this repository,
# so the logs can be read with plain git (no Actions API access needed).
#
# Usage: publish-logs.sh <log-dir> <name>
# Needs: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_NUMBER, GITHUB_SHA
set -euo pipefail

SRC="$1"
NAME="$2"
BRANCH=ci-logs
DEST="runs/${GITHUB_RUN_NUMBER}-${NAME}"
URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
TMP="$(mktemp -d)"

git init -q "$TMP"
cd "$TMP"
git config user.name "wesnoth-web-ci"
git config user.email "wesnoth-web-ci@users.noreply.github.com"
git remote add origin "$URL"

for attempt in 1 2 3 4 5; do
	if git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
		git checkout -q -B "$BRANCH" FETCH_HEAD
	else
		git checkout -q --orphan "$BRANCH"
		git rm -rqf . 2>/dev/null || true
		printf '# CI logs\n\nWritten by `web/ci/publish-logs.sh`. One folder per run under `runs/`.\n' > README.md
	fi
	rm -rf "$DEST"
	mkdir -p "$DEST"
	cp -r "$SRC"/. "$DEST"/
	{
		echo "run: ${GITHUB_RUN_NUMBER}"
		echo "name: ${NAME}"
		echo "commit: ${GITHUB_SHA}"
		echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} > "$DEST/RUN_INFO.txt"
	echo "$DEST" > "LATEST-${NAME}"
	git add -A
	git commit -qm "logs: run ${GITHUB_RUN_NUMBER} ${NAME}" || true
	if git push -q origin "HEAD:$BRANCH"; then
		echo "published logs to $BRANCH:$DEST"
		exit 0
	fi
	echo "push failed (attempt $attempt), retrying"
	sleep $((attempt * 5))
done
exit 1
