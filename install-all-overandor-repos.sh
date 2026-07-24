#!/usr/bin/env bash
set -Eeuo pipefail

OWNER="${OWNER:-overandor}"
WORKFLOW_PATH=".github/workflows/snap2txt.yml"
ENGINE_REF="1d9b7a71b7245f98c85cd9c8619ddf124d0d8db2"
MODE="${1:---dry-run}"

case "$MODE" in
  --dry-run|--apply) ;;
  *) echo "Usage: $0 [--dry-run|--apply]" >&2; exit 2 ;;
esac

command -v gh >/dev/null || { echo "GitHub CLI required" >&2; exit 1; }
gh auth status >/dev/null

WORKFLOW=$(cat <<EOF
name: Snap2Text after every push

on:
  push:
    branches-ignore:
      - snap2txt
  workflow_dispatch:

permissions:
  contents: write

jobs:
  snapshot:
    uses: overandor/hf-spaces-snap2txt/.github/workflows/repository-snap2txt.yml@${ENGINE_REF}
EOF
)

encode() { printf '%s' "$1" | base64 | tr -d '\n'; }
encoded="$(encode "$WORKFLOW")"

mapfile -t repos < <(
  gh repo list "$OWNER" --limit 1000 \
    --json nameWithOwner,isArchived,isFork,isEmpty \
    --jq '.[] | select((.isArchived|not) and (.isFork|not) and (.isEmpty|not)) | .nameWithOwner'
)

installed=0
updated=0
skipped=0
failed=0

for repo in "${repos[@]}"; do
  if [[ "$repo" == "$OWNER/hf-spaces-snap2txt" ]]; then
    echo "SKIP control repo  $repo"
    ((skipped+=1))
    continue
  fi

  if [[ "$MODE" == "--dry-run" ]]; then
    echo "WOULD INSTALL      $repo/$WORKFLOW_PATH"
    continue
  fi

  sha="$(gh api "/repos/$repo/contents/$WORKFLOW_PATH" --jq '.sha' 2>/dev/null || true)"

  if [[ -n "$sha" ]]; then
    if gh api --method PUT "/repos/$repo/contents/$WORKFLOW_PATH" \
      -f message='ci: update Snap2Text workflow' \
      -f content="$encoded" \
      -f sha="$sha" >/dev/null; then
      echo "UPDATED            $repo"
      ((updated+=1))
    else
      echo "FAILED             $repo" >&2
      ((failed+=1))
    fi
  else
    if gh api --method PUT "/repos/$repo/contents/$WORKFLOW_PATH" \
      -f message='ci: snapshot repository after every push' \
      -f content="$encoded" >/dev/null; then
      echo "INSTALLED          $repo"
      ((installed+=1))
    else
      echo "FAILED             $repo" >&2
      ((failed+=1))
    fi
  fi
done

echo
echo "Repositories scanned: ${#repos[@]}"
echo "Installed:           $installed"
echo "Updated:             $updated"
echo "Skipped:             $skipped"
echo "Failed:              $failed"

if [[ "$MODE" == "--dry-run" ]]; then
  echo
  echo "Apply with: ./install-all-overandor-repos.sh --apply"
fi

(( failed == 0 ))
