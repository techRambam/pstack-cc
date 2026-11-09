#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "sync.sh: $*" >&2; exit 1; }
locked() { awk -v r="$1" '$1 == r { print $2 }' upstream.lock; }

case $# in
  0) [ -f upstream.lock ] || die "upstream.lock is missing, so pass both refs"
     pstack_ref=$(locked cursor/plugins)
     matt_ref=$(locked mattpocock/skills) ;;
  2) pstack_ref=$1 matt_ref=$2 ;;
  *) die "usage: ./sync.sh [pstack-ref mattpocock-ref]" ;;
esac
[ -n "$pstack_ref" ] && [ -n "$matt_ref" ] || die "upstream.lock has no ref for one of the upstreams"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() {
  git init -q "$tmp/$1"
  git -C "$tmp/$1" fetch -q --depth 1 "https://github.com/$2.git" "$3" || die "fetch of $2 at $3 failed"
  git -C "$tmp/$1" checkout -q FETCH_HEAD || die "checkout of $2 at $3 failed"
}

fetch pstack cursor/plugins "$pstack_ref"
fetch matt mattpocock/skills "$matt_ref"

src="$tmp/pstack/harness/pstack/claude-code"
[ -d "$src" ] || die "cursor/plugins at $pstack_ref has no harness/pstack/claude-code"
out="$tmp/plugins"
mkdir "$out"
cp -R "$src" "$out/pstack"

m="$tmp/matt"
name=$(jq -er .name "$m/.claude-plugin/plugin.json") || die "mattpocock/skills has no .claude-plugin/plugin.json name"
dest="$out/$name"
mkdir -p "$dest/.claude-plugin"
cp "$m/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
cp "$m/LICENSE" "$dest/LICENSE"
jq -er '.skills[]' "$m/.claude-plugin/plugin.json" | while read -r skill; do
  [ -d "$m/$skill" ] || die "mattpocock/skills promotes $skill, which does not exist"
  mkdir -p "$dest/$(dirname "$skill")"
  cp -R "$m/$skill" "$dest/$skill"
done

rm -rf plugins
mv "$out" plugins

pstack_sha=$(git -C "$tmp/pstack" rev-parse HEAD)
matt_sha=$(git -C "$m" rev-parse HEAD)
printf 'cursor/plugins %s\nmattpocock/skills %s\n' "$pstack_sha" "$matt_sha" > upstream.lock

cat > README.md <<EOF
# pstack-cc

This repository is a Claude Code marketplace with two plugins, each copied from upstream.

| Plugin | Upstream | Commit |
| --- | --- | --- |
| \`pstack\` | [cursor/plugins \`harness/pstack/claude-code\`](https://github.com/cursor/plugins/tree/$pstack_sha/harness/pstack/claude-code) | \`$pstack_sha\` |
| \`$name\` | [mattpocock/skills](https://github.com/mattpocock/skills/tree/$matt_sha) | \`$matt_sha\` |

\`./sync.sh main main\` copies the latest upstream \`main\` of both. \`./sync.sh\` with no arguments copies the commits in \`upstream.lock\` again.
EOF

echo "cursor/plugins $pstack_sha"
echo "mattpocock/skills $matt_sha"
