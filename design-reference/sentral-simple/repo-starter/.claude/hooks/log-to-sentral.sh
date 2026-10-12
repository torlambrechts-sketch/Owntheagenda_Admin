#!/usr/bin/env bash
# Sends a short session summary to Sentral's work log for the current branch.
branch=$(git rev-parse --abbrev-ref HEAD)
id=$(echo "$branch" | grep -oE '^(OP|BUG|SK)-[0-9]+' || true)
[ -z "$id" ] && exit 0
summary=$(jq -r '.last_assistant_message // ""' | head -c 400)
curl -s -X POST https://sentral.orgpuls.no/api/dev/claude-log \
  -H "Authorization: Bearer $SENTRAL_WEBHOOK_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg id "$id" --arg b "$branch" --arg s "$summary" '{id:$id, branch:$b, summary:$s}')" >/dev/null
exit 0
