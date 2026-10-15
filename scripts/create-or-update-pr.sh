#!/usr/bin/env bash
set -euo pipefail

existing_pr=$(gh pr list --head "$BRANCH" --state open --json url --jq 'map(.url)[0] // ""')
if [[ -n "$existing_pr" ]]; then
  gh pr edit "$existing_pr" --title "$TITLE" --body "$BODY"
  url=$existing_pr
else
  url=$(gh pr create --title "$TITLE" --body "$BODY" --head "$BRANCH")
fi

echo "url=${url}" >> "$GITHUB_OUTPUT"

if [[ "$AUTO_MERGE" == 'true' ]]; then
  gh pr merge "$url" --squash --auto
fi
