#!/usr/bin/env bash
# Single-run pull-request contract: title, do-not-merge label, issue linkage.
#
# One composite step, so a consumer needs exactly one required check
# (`ci-status`). Every check reads the LIVE pull request from the API rather than the event
# payload, so `edited`, `labeled` and `unlabeled` runs see current state.
set -euo pipefail

: "${REPOSITORY:?REPOSITORY is required}"
: "${TYPES:?TYPES is required}"

PR_NUMBER="${PR_NUMBER:-}"
REQUIRE_SCOPE="${REQUIRE_SCOPE:-false}"
DO_NOT_MERGE_LABEL="${DO_NOT_MERGE_LABEL:-do-not-merge}"
EXEMPT_AUTHORS="${EXEMPT_AUTHORS:-}"
LINKAGE_LABEL="${LINKAGE_LABEL:-needs-issue-linkage}"
LINKAGE_MODE="${LINKAGE_MODE:-advisory}"

# Stable HTML marker on the advisory comment: the upsert finds its own previous
# comment by this string, so a re-run edits rather than posting a second one.
LINKAGE_MARKER='<!-- pr-contract:linkage -->'

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
gh_stdout="$scratch/gh-stdout"
gh_stderr="$scratch/gh-stderr"

emit_output() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${name}=${value}" >>"$GITHUB_OUTPUT"
  fi
}

# Every annotation below quotes attacker-controlled text: the PR title, the PR
# body, the author login. GitHub's documented escaping for workflow-command data
# is `%` -> `%25`, CR -> `%0D`, LF -> `%0A`; without it a title carrying a
# newline can close the annotation and inject a second workflow command.
# `%` first, or the escapes introduced by the others get double-escaped.
escape_annotation() {
  local text="$1"
  text="${text//'%'/%25}"
  text="${text//$'\r'/%0D}"
  text="${text//$'\n'/%0A}"
  printf '%s' "$text"
}

# Every value below is interpolated into a `gh api` path. Validate before the
# first call rather than trusting the caller's expression.
require_pattern() {
  local name="$1" value="$2" pattern="$3" shape="$4"
  if [[ ! "$value" =~ $pattern ]]; then
    echo "::error::pr-contract: ${name} must be ${shape}, got: $(escape_annotation "$value")"
    exit 1
  fi
}

# Percent-encode a label so it reaches the DELETE path as one segment. `@uri`
# encodes UTF-8 bytes, so an emoji or non-ASCII label survives.
# shellcheck disable=SC2329 # invoked from remove_linkage_label, itself reached through best_effort.
url_encode() {
  jq -rn --arg text "$1" '$text|@uri'
}

case "$LINKAGE_MODE" in
advisory | enforce) ;;
*)
  echo "::error::pr-contract: linkage-mode must be 'advisory' or 'enforce', got: ${LINKAGE_MODE}"
  exit 1
  ;;
esac

case "$REQUIRE_SCOPE" in
true | false) ;;
*)
  echo "::error::pr-contract: require-scope must be 'true' or 'false', got: ${REQUIRE_SCOPE}"
  exit 1
  ;;
esac

# Step 0 — no pull request in this event. The composite is a pull-request gate;
# a push, schedule or workflow_dispatch run must report skipped, not fail.
if [[ -z "${PR_NUMBER//[[:space:]]/}" ]]; then
  echo '::notice::pr-contract: no pull request in this event; nothing to check'
  emit_output title skipped
  emit_output do-not-merge skipped
  emit_output linkage skipped
  exit 0
fi

# Only the two values that reach an API path unencoded. The labels are
# deliberately NOT validated: GitHub labels may legally contain spaces and
# colons (`do not merge`, `status: blocked`), and neither one is ever
# interpolated raw — the blocking label is compared with `grep -qxF`, the
# linkage label travels in a JSON body built by `jq --arg`, and the only path
# it reaches is percent-encoded below.
require_pattern repository "$REPOSITORY" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' 'OWNER/REPO'
require_pattern pr-number "$PR_NUMBER" '^[0-9]+$' 'a positive integer'

# gh_api <method> <path> [extra args...]
# Captures stdout and stderr; sets GH_HTTP_STATUS from gh's "(HTTP nnn)" tail
# when the call failed. Returns gh's exit status.
GH_HTTP_STATUS=""
gh_api() {
  local method="$1" path="$2"
  shift 2
  local status=0
  : >"$gh_stdout"
  : >"$gh_stderr"
  GH_HTTP_STATUS=""
  # `set +e` around the call: a failed API read is classified by the caller,
  # not aborted by errexit.
  set +e
  gh api -X "$method" "$path" "$@" >"$gh_stdout" 2>"$gh_stderr"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    GH_HTTP_STATUS="$(sed -n 's/.*(HTTP \([0-9][0-9]*\)).*/\1/p' "$gh_stderr" | head -n1)"
  fi
  return "$status"
}

# Best-effort write: a refused or missing write surfaces as a ::notice:: and
# never changes the exit code. The advisory comment and label are convenience,
# not the gate.
best_effort() {
  local description="$1"
  shift
  if "$@"; then
    return 0
  fi
  local detail="${GH_HTTP_STATUS:-unknown}"
  echo "::notice::pr-contract: ${description} was refused (HTTP ${detail}); continuing without it"
  return 0
}

# ---------------------------------------------------------------------------
# Step 1 — fetch the pull request once.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2310 # gh_api handles its own errexit; the caller classifies the status.
if ! gh_api GET "repos/${REPOSITORY}/pulls/${PR_NUMBER}"; then
  cat "$gh_stderr" >&2
  echo "::error::pr-contract: could not read repos/${REPOSITORY}/pulls/${PR_NUMBER} (HTTP ${GH_HTTP_STATUS:-unknown})"
  exit 1
fi
pr_json="$scratch/pr.json"
cp -- "$gh_stdout" "$pr_json"

pr_title="$(jq -r '.title // ""' <"$pr_json")"
pr_author="$(jq -r '.user.login // ""' <"$pr_json")"
jq -r '.body // ""' <"$pr_json" >"$scratch/body.txt"
jq -r '(.labels // []) | .[].name' <"$pr_json" >"$scratch/labels.txt"

# ---------------------------------------------------------------------------
# Step 2 — title against Conventional Commits with the caller's type list.
# ---------------------------------------------------------------------------
types_list="$(printf '%s' "$TYPES" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true)"
if [[ -z "$types_list" ]]; then
  echo "::error::pr-contract: types is empty; list at least one allowed Conventional Commits type"
  exit 1
fi
types_alternation="$(printf '%s' "$types_list" | paste -sd '|' -)"
types_human="${types_alternation//|/, }"

# `: +`, not `: `: the conventional-commits parser tolerates more than one space
# after the colon.
# shellcheck disable=SC2016 # the backticks are Markdown code spans in a message, not command substitution.
if [[ "$REQUIRE_SCOPE" == true ]]; then
  title_regex="^(${types_alternation})\([^)]+\)!?: +[^[:space:]]"
  scope_hint='a scope is REQUIRED, e.g. `feat(api): add the widget endpoint`'
else
  title_regex="^(${types_alternation})(\([^)]+\))?!?: +[^[:space:]]"
  scope_hint='an optional scope may follow the type, e.g. `feat(api): add the widget endpoint`'
fi

title_result=pass
if [[ ! "$pr_title" =~ $title_regex ]]; then
  title_result=fail
  echo "::error::pr-contract: the PR title does not follow Conventional Commits: \"$(escape_annotation "$pr_title")\". Expected \"<type>: <subject>\" with a non-empty subject; allowed types: ${types_human}. ${scope_hint} A breaking change marks the type with \"!\"."
fi

# ---------------------------------------------------------------------------
# Step 3 — do-not-merge label.
# ---------------------------------------------------------------------------
do_not_merge_result=pass
if grep -qxF -- "$DO_NOT_MERGE_LABEL" "$scratch/labels.txt"; then
  do_not_merge_result=fail
  echo "::error::pr-contract: this PR carries the '${DO_NOT_MERGE_LABEL}' label; remove it to merge."
fi

# ---------------------------------------------------------------------------
# Step 4 — issue linkage.
#
# The body must
# carry a native closing keyword, an explicit non-closing `Refs:`/`Relates to:`
# marker, or a no-issue opt-out, AND four non-empty contract sections. A negated
# closing reference fails outright and is never excused by a valid marker
# elsewhere, because GitHub's own parser is negation-blind and closes the issue
# on merge regardless of the disclaimer.
#
# The analyzer masks rendered HTML comments, fenced and indented code blocks,
# and inline code spans before matching, so a PR template's commented-out
# example cannot satisfy the gate.
# ---------------------------------------------------------------------------
analyze_body() {
  awk '
# Whitespace includes newlines: section content is joined before trimming, so a
# section holding only blank lines must trim to the empty string.
function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}

function run_length(s, ch,   n) {
  n = 0
  while (substr(s, n + 1, 1) == ch) n++
  return n
}

# A backtick run of the same length later on this line closes an inline span.
# The upstream implementation also scans following lines; a multi-line inline
# span in a PR body is not a shape this gate needs to model.
function has_closing_run(s, start, ticks,   col, stop) {
  col = start
  while (col <= length(s)) {
    if (substr(s, col, 1) != "`") {
      col++
      continue
    }
    stop = col + 1
    while (substr(s, stop, 1) == "`") stop++
    if (stop - col == ticks) return 1
    col = stop
  }
  return 0
}

function negation_trigger(line, keyword_index,   preceding, cut, i, ch, tail, count, words, first, word, lower) {
  preceding = substr(line, 1, keyword_index - 1)
  cut = 0
  for (i = length(preceding); i >= 1; i--) {
    ch = substr(preceding, i, 1)
    if (ch == "." || ch == "!" || ch == "?" || ch == ";" || ch == ",") {
      cut = i
      break
    }
  }
  tail = substr(preceding, cut + 1)
  # U+2019 RIGHT SINGLE QUOTATION MARK, written as its UTF-8 bytes so the source
  # of this action stays plain ASCII: normalize a typographic apostrophe to the
  # straight one so "doesn<U+2019>t close #N" is detected like "doesn'"'"'t".
  gsub("\342\200\231", "'"'"'", tail)
  count = 0
  while (match(tail, /[A-Za-z][A-Za-z'"'"']*/)) {
    count++
    words[count] = substr(tail, RSTART, RLENGTH)
    tail = substr(tail, RSTART + RLENGTH)
  }
  first = (count > 5) ? count - 4 : 1
  for (i = first; i <= count; i++) {
    word = words[i]
    lower = tolower(word)
    # Correlative "not only ... but" is affirmative, not a disclaimer.
    if (lower == "not" && i < count && tolower(words[i + 1]) == "only") continue
    if (lower == "not" || lower == "never" || lower == "no" || lower == "without" ||
        lower == "deliberately" || lower == "intentionally") return word
    if (tolower(substr(word, length(word) - 2)) == "n'"'"'t") return word
  }
  return ""
}

function scan_line(line,   indent, rest, lower, offset, chunk, start, len, before, after, text, trigger) {
  indent = 0
  while (substr(line, indent + 1, 1) == " ") indent++
  if (indent <= 3) {
    rest = tolower(substr(line, indent + 1))
    if (rest ~ /^(refs|relates[ \t]+to):[ \t]*([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+[ \t]*$/) {
      has_non_closing = 1
    }
  }
  lower = tolower(line)
  offset = 0
  while (1) {
    chunk = substr(lower, offset + 1)
    if (!match(chunk, /(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[ \t]*:?[ \t]*([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/)) break
    start = offset + RSTART
    len = RLENGTH
    offset = start + len - 1
    before = (start > 1) ? substr(lower, start - 1, 1) : ""
    after = substr(lower, start + len, 1)
    # Word-boundary equivalent of the upstream /\b...\b/ anchors.
    if (before ~ /[a-z0-9_]/) continue
    if (after ~ /[a-z0-9_]/) continue
    text = substr(line, start, len)
    trigger = negation_trigger(line, start)
    if (trigger != "") {
      if (!(text in negated_trigger)) {
        negated_count++
        negated_order[negated_count] = text
        negated_trigger[text] = trigger
      }
    } else {
      has_closing = 1
    }
  }
}

function section_report(name,   i, trimmed, start, hashes, next_char, tail, content) {
  start = 0
  for (i = 1; i <= line_count; i++) {
    trimmed = tolower(trim(masked[i]))
    if (trimmed ~ ("^##[ \t]+" tolower(name) "$")) {
      start = i
      break
    }
  }
  if (start == 0) {
    print "section-missing\t" name
    return
  }
  content = ""
  for (i = start + 1; i <= line_count; i++) {
    trimmed = trim(masked[i])
    hashes = run_length(trimmed, "#")
    if (hashes >= 1 && hashes <= 6) {
      next_char = substr(trimmed, hashes + 1, 1)
      tail = trim(substr(trimmed, hashes + 1))
      # Only a heading at the same or higher level ends the section, so a
      # nested subsection counts as this section content.
      if ((next_char == " " || next_char == "\t") && tail != "" && hashes <= 2) break
    }
    content = content masked[i] "\n"
  }
  if (trim(content) == "") print "section-empty\t" name
}

BEGIN {
  line_count = 0
  comment_open = 0
  inline_ticks = 0
  fence_char = ""
  fence_len = 0
  has_closing = 0
  has_non_closing = 0
  negated_count = 0
}

{
  line = $0
  sub(/\r$/, "", line)

  if (!comment_open && inline_ticks == 0) {
    indent = 0
    while (substr(line, indent + 1, 1) == " ") indent++
    rest = substr(line, indent + 1)
    marker_char = substr(rest, 1, 1)
    marker_run = 0
    if (marker_char == "`" || marker_char == "~") marker_run = run_length(rest, marker_char)
    is_marker = (indent <= 3 && marker_run >= 3)
    info = is_marker ? substr(rest, marker_run + 1) : ""

    if (fence_char != "") {
      masked[++line_count] = ""
      if (is_marker && marker_char == fence_char && marker_run >= fence_len && info ~ /^[ \t]*$/) {
        fence_char = ""
        fence_len = 0
      }
      next
    }
    if (is_marker && !(marker_char == "`" && index(info, "`") > 0)) {
      fence_char = marker_char
      fence_len = marker_run
      masked[++line_count] = ""
      next
    }
    if (substr(line, 1, 4) == "    " || substr(line, 1, 1) == "\t") {
      masked[++line_count] = ""
      next
    }
  }

  rendered = ""
  index_position = 1
  line_length = length(line)
  while (index_position <= line_length) {
    if (comment_open) {
      close_at = index(substr(line, index_position), "-->")
      if (close_at == 0) {
        index_position = line_length + 1
        continue
      }
      comment_open = 0
      index_position = index_position + close_at - 1 + 3
      continue
    }
    character = substr(line, index_position, 1)
    if (character == "`") {
      stop = index_position + 1
      while (substr(line, stop, 1) == "`") stop++
      ticks = stop - index_position
      was_inline = (inline_ticks != 0)
      if (!was_inline && has_closing_run(line, stop, ticks)) {
        inline_ticks = ticks
      } else if (inline_ticks == ticks) {
        inline_ticks = 0
      }
      if (!was_inline && inline_ticks == 0) rendered = rendered substr(line, index_position, stop - index_position)
      index_position = stop
      continue
    }
    if (inline_ticks == 0 && substr(line, index_position, 4) == "<!--") {
      comment_open = 1
      index_position += 4
      continue
    }
    if (inline_ticks == 0) rendered = rendered character
    index_position++
  }
  masked[++line_count] = rendered
}

END {
  section_report("Summary")
  section_report("Fix")
  section_report("Verification")
  section_report("Related")

  body = ""
  for (i = 1; i <= line_count; i++) {
    scan_line(masked[i])
    body = body masked[i] "\n"
  }
  for (i = 1; i <= negated_count; i++) {
    print "negated\t" negated_order[i] "\t" negated_trigger[negated_order[i]]
  }
  if (has_closing) print "closing"
  if (has_non_closing) print "non-closing"
  if (tolower(body) ~ /(^|[^a-z0-9_])no (linked|related) issue([^a-z0-9_]|$)/) print "no-issue"
}
'
}

section_guidance() {
  case "$1" in
  Summary) echo 'Describe what this PR changes and why, in a sentence or two.' ;;
  Fix) echo 'State the concrete change and how it addresses the problem.' ;;
  Verification) echo 'Record concrete evidence the change works (commands, gates, output).' ;;
  Related) echo 'List related PRs, ADRs, or decision-log entries this PR does not close.' ;;
  *) echo 'Fill this section in.' ;;
  esac
}

linkage_result=pass
linkage_errors=()

is_exempt_author=false
if [[ -n "${EXEMPT_AUTHORS//[[:space:]]/}" && -n "$pr_author" ]]; then
  while IFS= read -r candidate; do
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate%"${candidate##*[![:space:]]}"}"
    [[ -n "$candidate" ]] || continue
    # Exact-login equality only, never a `*[bot]` pattern, so an unknown future
    # bot is not silently skipped on this gate.
    if [[ "$candidate" == "$pr_author" ]]; then
      is_exempt_author=true
      break
    fi
    # `printf '%s\n'` (not '%s'): without the trailing newline `read` drops the
    # last list entry, which silently un-exempts the final author.
  done < <(printf '%s\n' "$EXEMPT_AUTHORS" | tr ',' '\n')
fi

if [[ "$is_exempt_author" == true ]]; then
  linkage_result=exempt
  echo "::notice::pr-contract: PR author \"$(escape_annotation "$pr_author")\" matches an exempt-authors entry; skipping the issue-linkage check."
else
  analysis="$scratch/analysis.txt"
  analyze_body <"$scratch/body.txt" >"$analysis"

  while IFS=$'\t' read -r kind name _rest; do
    case "$kind" in
    section-missing)
      linkage_errors+=("Missing a \"## ${name}\" section. $(section_guidance "$name")")
      ;;
    section-empty)
      linkage_errors+=("The \"## ${name}\" section is empty.")
      ;;
    *) ;;
    esac
  done <"$analysis"

  negated_quoted=""
  while IFS=$'\t' read -r kind text trigger; do
    [[ "$kind" == negated ]] || continue
    if [[ -n "$negated_quoted" ]]; then
      negated_quoted+=", "
    fi
    negated_quoted+="\"${text}\" (trigger \"${trigger}\")"
  done <"$analysis"

  if [[ -n "$negated_quoted" ]]; then
    linkage_errors+=("Negated closing reference (${negated_quoted}). GitHub's linkage parser ignores the surrounding words, so this still registers a closing reference and still auto-closes the issue when this PR merges. Remove the closing keyword and use \"Refs: #N\" (or \"Relates to: #N\") on its own line instead.")
  fi

  if ! grep -qx 'closing' "$analysis" &&
    ! grep -qx 'non-closing' "$analysis" &&
    ! grep -qx 'no-issue' "$analysis"; then
    linkage_errors+=('Missing a native closing keyword (Closes/Fixes/Resolves #N). If this PR references an issue it must not close, put "Refs: #N" (or "Relates to: #N") on its own line. If it relates to no GitHub issue at all, state "No linked issue" (or "No related issue:") in the body instead.')
  fi

  if [[ ${#linkage_errors[@]} -gt 0 ]]; then
    linkage_result=fail
  fi
fi

# ---------------------------------------------------------------------------
# Step 5 — advisory outcome: one marker comment, upserted, plus the label.
# ---------------------------------------------------------------------------
find_marker_comment() {
  # shellcheck disable=SC2310 # gh_api handles its own errexit; the caller classifies the status.
  if ! gh_api GET "repos/${REPOSITORY}/issues/${PR_NUMBER}/comments" --paginate --slurp; then
    return 1
  fi
  # Bot-authored only, newest first. On a public repository anyone can comment,
  # so a stranger who plants the marker would otherwise capture the upsert and
  # the gate would edit their comment instead of posting its own. `--slurp`
  # wraps every page in one outer array, so `max_by` sees all pages at once
  # rather than printing one id per page.
  jq -r --arg marker "$LINKAGE_MARKER" \
    '[ .[][] | select((.user.type // "") == "Bot" and ((.body // "") | contains($marker))) ] | (max_by(.id).id // empty)' \
    <"$gh_stdout"
}

# shellcheck disable=SC2329 # invoked indirectly through best_effort.
upsert_marker_comment() {
  local body="$1" comment_id=""
  # shellcheck disable=SC2310 # find_marker_comment reports the read failure through its status.
  if ! comment_id="$(find_marker_comment)"; then
    return 1
  fi
  jq -n --arg body "$body" '{body: $body}' >"$scratch/comment-payload.json"
  if [[ -n "$comment_id" ]]; then
    gh_api PATCH "repos/${REPOSITORY}/issues/comments/${comment_id}" --input "$scratch/comment-payload.json"
  else
    gh_api POST "repos/${REPOSITORY}/issues/${PR_NUMBER}/comments" --input "$scratch/comment-payload.json"
  fi
}

# shellcheck disable=SC2329 # invoked indirectly through best_effort.
add_linkage_label() {
  jq -n --arg label "$LINKAGE_LABEL" '{labels: [$label]}' >"$scratch/label-payload.json"
  gh_api POST "repos/${REPOSITORY}/issues/${PR_NUMBER}/labels" --input "$scratch/label-payload.json"
}

# shellcheck disable=SC2329 # invoked indirectly through best_effort.
remove_linkage_label() {
  # Percent-encoded so the label stays one path segment.
  gh_api DELETE "repos/${REPOSITORY}/issues/${PR_NUMBER}/labels/$(url_encode "$LINKAGE_LABEL")"
}

if [[ "$linkage_result" == fail ]]; then
  for message in "${linkage_errors[@]}"; do
    if [[ "$LINKAGE_MODE" == enforce ]]; then
      # The linkage messages quote body text (a negated closing reference and
      # its trigger word), so they are escaped like the title.
      echo "::error::pr-contract: $(escape_annotation "$message")"
    else
      echo "::warning::pr-contract: $(escape_annotation "$message")"
    fi
  done

  {
    printf '%s\n\n' "$LINKAGE_MARKER"
    printf '%s\n\n' '**PR body contract — issue linkage**'
    printf '%s\n\n' 'This PR body does not yet satisfy the issue-linkage contract:'
    for message in "${linkage_errors[@]}"; do
      printf -- '- %s\n' "$message"
    done
    printf '\n%s\n' 'Edit the body and this comment updates itself on the next run.'
  } >"$scratch/comment-body.md"

  best_effort 'upserting the linkage comment' upsert_marker_comment "$(cat "$scratch/comment-body.md")"
  best_effort 'adding the linkage label' add_linkage_label
else
  if [[ "$linkage_result" == pass ]]; then
    echo 'pr-contract: the PR body satisfies the issue-linkage contract.'
  fi
  # Never delete the marker comment: editing it keeps the audit trail of what
  # the gate said and why it stopped saying it.
  {
    printf '%s\n\n' "$LINKAGE_MARKER"
    printf '%s\n\n' '**PR body contract — issue linkage**'
    printf '%s\n' 'This PR body conforms to the issue-linkage contract. Nothing to do.'
  } >"$scratch/comment-body.md"

  # shellcheck disable=SC2310 # a failed read simply means there is no comment to update.
  if [[ -n "$(find_marker_comment 2>/dev/null || true)" ]]; then
    best_effort 'updating the linkage comment' upsert_marker_comment "$(cat "$scratch/comment-body.md")"
  fi
  if grep -qxF -- "$LINKAGE_LABEL" "$scratch/labels.txt"; then
    best_effort 'removing the linkage label' remove_linkage_label
  fi
fi

# ---------------------------------------------------------------------------
# Step 6 — outputs and the single exit decision.
#
# Every check runs before any exit so all three outputs are always emitted; an
# early exit on the title would leave `linkage` unset for the caller.
# ---------------------------------------------------------------------------
emit_output title "$title_result"
emit_output do-not-merge "$do_not_merge_result"
emit_output linkage "$linkage_result"

exit_code=0
if [[ "$title_result" == fail ]]; then
  exit_code=1
fi
if [[ "$do_not_merge_result" == fail ]]; then
  exit_code=1
fi
if [[ "$linkage_result" == fail && "$LINKAGE_MODE" == enforce ]]; then
  exit_code=1
fi
if [[ "$linkage_result" == fail && "$LINKAGE_MODE" == advisory ]]; then
  echo '::notice::pr-contract: issue linkage is advisory in this repository; the step does not fail on it.'
fi

exit "$exit_code"
