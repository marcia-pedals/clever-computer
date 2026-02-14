#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <owner/repo>"
  exit 1
fi

# shellcheck disable=SC1090
source ~/.zshenv

REPO="$1"
BRANCH="test-integration-$(date +%s)"
CLONE_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$CLONE_DIR"
}
trap cleanup EXIT

echo "=== Test: gh issue create ==="
ISSUE_URL=$(gh issue create --repo "$REPO" --title "Integration test $BRANCH" --body "Automated integration test." | tail -1)
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
echo "Created issue #$ISSUE_NUMBER"

echo ""
echo "=== Test: gh issue close ==="
gh issue close "$ISSUE_NUMBER" --repo "$REPO"
echo "Closed issue #$ISSUE_NUMBER"

echo ""
echo "=== Test: git clone ==="
git clone "https://github.proxy:8443/$REPO.git" "$CLONE_DIR"
echo "Cloned $REPO"

echo ""
echo "=== Test: git push branch ==="
cd "$CLONE_DIR"
git checkout -b "$BRANCH"
echo "integration test $BRANCH" > integration-test.txt
git add integration-test.txt
git commit -m "integration test: $BRANCH"
git push origin "$BRANCH"
echo "Pushed branch $BRANCH"

echo ""
echo "=== Test: gh pr create ==="
PR_URL=$(gh pr create --repo "$REPO" --title "Integration test $BRANCH" --body "Automated integration test." --head "$BRANCH" | tail -1)
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "Created PR #$PR_NUMBER ($PR_URL)"

echo ""
echo "=== Test: gh pr merge ==="
gh pr merge "$PR_NUMBER" --repo "$REPO" --merge --delete-branch
echo "Merged and deleted branch"

echo ""
echo "=== Test: verify branch deleted on origin ==="
git fetch --prune origin
if git branch -r | grep -q "origin/$BRANCH"; then
  echo "FAIL: branch $BRANCH still exists on origin"
  exit 1
fi
echo "Confirmed branch $BRANCH deleted on origin"

echo ""
echo "=== All sandbox tests passed ==="
