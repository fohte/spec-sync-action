#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d /tmp/spec-sync-action-test.XXXXXX)
trap 'rm -r -- "$test_dir"' EXIT

mkdir "$test_dir/bin"
cat > "$test_dir/bin/gh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$GH_CALL_LOG"
case "$1 $2" in
  'pr list') printf '%s' "${GH_EXISTING_PR:-}" ;;
  'pr create') printf '%s' "$GH_CREATED_PR" ;;
esac
EOF
chmod +x "$test_dir/bin/gh"

export PATH="$test_dir/bin:$PATH"
export BRANCH='spec-sync-example-service'
export TITLE='chore: sync generated code from example/service OpenAPI spec'
export BODY='Regenerated code from the latest example/service OpenAPI spec.'
export GH_CREATED_PR='https://github.com/example/consumer/pull/2'
export GH_CALL_LOG="$test_dir/gh-calls"

assert_line() {
  if ! grep -Fxq -- "$1" "$GH_CALL_LOG"; then
    printf 'Expected gh invocation not found: %s\n' "$1" >&2
    exit 1
  fi
}

assert_no_merge() {
  if grep -Eq '^pr merge ' "$GH_CALL_LOG"; then
    printf 'Unexpected gh merge invocation found.\n' >&2
    exit 1
  fi
}

: > "$GH_CALL_LOG"
export GITHUB_OUTPUT="$test_dir/new-pr-output"
GH_EXISTING_PR='' AUTO_MERGE='true' bash "$script_dir/create-or-update-pr.sh"
assert_line 'pr merge https://github.com/example/consumer/pull/2 --squash --auto'
grep -Fxq -- 'url=https://github.com/example/consumer/pull/2' "$GITHUB_OUTPUT"

: > "$GH_CALL_LOG"
export GITHUB_OUTPUT="$test_dir/existing-pr-output"
GH_EXISTING_PR='https://github.com/example/consumer/pull/1' AUTO_MERGE='true' bash "$script_dir/create-or-update-pr.sh"
assert_line 'pr edit https://github.com/example/consumer/pull/1 --title chore: sync generated code from example/service OpenAPI spec --body Regenerated code from the latest example/service OpenAPI spec.'
assert_line 'pr merge https://github.com/example/consumer/pull/1 --squash --auto'
grep -Fxq -- 'url=https://github.com/example/consumer/pull/1' "$GITHUB_OUTPUT"

: > "$GH_CALL_LOG"
export GITHUB_OUTPUT="$test_dir/disabled-output"
GH_EXISTING_PR='' AUTO_MERGE='false' bash "$script_dir/create-or-update-pr.sh"
assert_no_merge

printf 'PR helper tests passed.\n'
