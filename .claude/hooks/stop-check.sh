#!/usr/bin/env bash
# Project-log Stop hook — see CLAUDE.md "Project log (required, dual-write)".
#
# Logic order (first match wins):
#   1. No recent commit (>3 min ago) → pass.
#   2. Latest commit hash already appears in docs/troubleshooting.md or content/logs/ → pass.
#   3. Latest commit fires a POSITIVE TRIGGER (LOC > 200, sensitive path, or keyword in subject)
#      → block, regardless of [no-log] tag. Author judgment is overridden.
#      Escape valve: add a `<!-- override-trigger: HASH SUBJECT — rationale -->` line to
#      docs/troubleshooting.md to acknowledge the trigger was a false positive.
#   4. Commit subject contains [no-log] or [skip-log] AND no trigger fired
#      → auto-append `<!-- skipped: HASH SUBJECT -->` to docs/troubleshooting.md, pass.
#   5. Otherwise → block; require a full dual-write entry OR a [no-log] tag.
#
# The point: positive triggers make the system robust to author-judgment slips.
# Stop hook v3 — adds the positive-trigger layer to v2's hash-sentinel design.

set -uo pipefail

h=$(git log -1 --format=%h 2>/dev/null || true)
s=$(git log -1 --format=%s 2>/dev/null || true)
[ -z "$h" ] && exit 0

recent=$(git log --since="3 minutes ago" --oneline -1 2>/dev/null || true)
[ -z "$recent" ] && exit 0

if grep -rq "$h" docs/troubleshooting.md content/logs/ 2>/dev/null; then
  exit 0
fi

# ---------- Positive triggers ----------
# Trigger 1: total LOC delta > 200 (insertions + deletions across all files)
loc=$(git show --shortstat --format= "$h" 2>/dev/null | awk '
  /insertion|deletion/ {
    ins=0; del=0;
    for (i=1; i<=NF; i++) {
      if ($i ~ /insertion/) ins=$(i-1);
      if ($i ~ /deletion/)  del=$(i-1);
    }
    print ins+del;
    exit
  }
')
loc=${loc:-0}

# Trigger 2: sensitive paths
sensitive_re='^(lib/[^/]*(storage|auth|hooks)|middleware\.|app/\(admin\)|app/api/auth|\.claude/(settings|hooks/)|install/|next\.config|package\.json|tsconfig|migrations?/|prisma/(schema|migrations)|.*\.schema\.)'
touched_sensitive=$(git show --name-only --format= "$h" 2>/dev/null | grep -E "$sensitive_re" | head -3 || true)

# Trigger 3: keywords in commit subject (case-insensitive)
keyword_re='(decision|architecture|fallback|audit|auth|security|migration|dispatcher|ADR-?[0-9]+|refactor|pivot|breaking|deprecat|hidden coupling)'
matched_keyword=$(echo "$s" | grep -iEo "$keyword_re" | head -1 || true)

triggers=()
[ "$loc" -gt 200 ] && triggers+=("diff is $loc LOC (>200 threshold)")
[ -n "$touched_sensitive" ] && triggers+=("touches sensitive path: $(echo "$touched_sensitive" | tr '\n' ' ' | sed 's/ $//')")
[ -n "$matched_keyword" ] && triggers+=("subject contains keyword: $matched_keyword")

triggered=0
[ ${#triggers[@]} -gt 0 ] && triggered=1

trigger_summary=""
if [ "$triggered" = "1" ]; then
  trigger_summary=$(printf -- '  - %s\n' "${triggers[@]}")
fi

has_skip_tag=0
echo "$s" | grep -qE '\[(no|skip)-log\]' && has_skip_tag=1

# ---------- Decision branch ----------

# 3. trigger fired → require entry OR explicit override (never silent skip)
if [ "$triggered" = "1" ]; then
  if [ "$has_skip_tag" = "1" ]; then
    reason="Commit $h ($s) was tagged [no-log] but the positive trigger fired:
$trigger_summary
Author judgment is overridden by these triggers. Per CLAUDE.md, this kind of change must be logged regardless of tag — the [no-log] mechanism is for genuinely routine commits (typos, lint, formatting, dep bumps without behavior change).

Write BOTH:
  1. docs/troubleshooting.md entry (terse Symptom/Cause/Fix/Commit/Pattern, anchored on hash $h)
  2. content/logs/<project>/<date>-<slug>.mdx narrative entry

If you believe this is a false positive, append this line to docs/troubleshooting.md (replace 'reason here' with a real justification — silent overrides are not allowed):

    <!-- override-trigger: $h $s — reason here -->

Then commit. The hash in that line satisfies the next Stop check."
  else
    reason="Commit $h ($s) is not yet logged AND fired the positive trigger:
$trigger_summary
This means the system judges the commit non-trivial regardless of how the message is framed. Write BOTH a docs/troubleshooting.md entry and a content/logs/<project>/<date>-<slug>.mdx narrative entry following the 7 anti-hallucination rules in CLAUDE.md.

If you believe this is a false positive, append this line to docs/troubleshooting.md (with a real reason):

    <!-- override-trigger: $h $s — reason here -->

Then commit."
  fi
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

# 4. no trigger + [no-log] → auto-record skip
if [ "$has_skip_tag" = "1" ]; then
  printf '<!-- skipped: %s %s -->\n' "$h" "$s" >> docs/troubleshooting.md
  exit 0
fi

# 5. default block — require dual-write or [no-log] tag
reason="Recent commit $h ($s) is not yet logged.

Per CLAUDE.md project log rules:
- If NON-TRIVIAL: write BOTH docs/troubleshooting.md entry AND content/logs/<project>/<date>-<slug>.mdx in this same turn (follow the 7 anti-hallucination rules — paste literal symptom, verify cause, use the commit hash above verbatim).
- If ROUTINE (typo / lint / formatting / dep bump without behavior change): append this one line to docs/troubleshooting.md to silence the hook:

    <!-- skipped: $h $s -->

After writing, commit the changes. The next Stop check will see the hash in the file and let the turn end."

jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
