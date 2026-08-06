#!/usr/bin/env bash
# Validate and materialize the standards distribution manifest.
set -euo pipefail
export LC_ALL=C

readonly DEFAULT_MANIFEST='distribution/sync-manifest.yml'
readonly CONTROL_RE='[[:cntrl:]]'
export CONTROL_RE

usage() {
  cat <<'EOF'
Usage:
  sync-manifest.sh validate [--source-root DIR] [--manifest PATH]
  sync-manifest.sh matrix   [--source-root DIR] [--manifest PATH] [--targets CSV]
  sync-manifest.sh plan     [--source-root DIR] [--manifest PATH] [--targets CSV]
  sync-manifest.sh mappings [--source-root DIR] [--manifest PATH] --target OWNER/REPO
  sync-manifest.sh apply    [--source-root DIR] [--manifest PATH] --target OWNER/REPO --target-root DIR

Commands:
  validate  Validate the schema, catalog, sources, and adoption graph.
  matrix    Emit only the filtered GitHub Actions matrix JSON.
  plan      Print the filtered, human-readable dry-run plan.
  mappings  Print Markdown bullets for one target's managed mappings.
  apply     Copy one target's managed components and reproduce Git modes.

PATH is relative to source-root. --targets is a comma-separated exact
allowlist; empty selects every target in manifest order.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_safe_repo_path() {
  local path="$1" segment
  local -a segments
  [[ -n "$path" ]] || return 1
  [[ "$path" != /* ]] || return 1
  [[ ! "$path" =~ ^[A-Za-z]: ]] || return 1
  [[ "$path" != *\\* ]] || return 1
  [[ "${path: -1}" != / ]] || return 1
  [[ "$path" != *'//'* ]] || return 1
  if printf '%s' "$path" | grep -q "$CONTROL_RE"; then return 1; fi
  IFS='/' read -r -a segments <<<"$path"
  for segment in "${segments[@]}"; do
    [[ -n "$segment" && "$segment" != '.' && "$segment" != '..' ]] || return 1
    [[ "$segment" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ "${segment,,}" != '.git' ]] || return 1
  done
}

canonical_git_root() {
  local requested="$1" physical git_root
  [[ -d "$requested" ]] || die "Git root does not exist: $requested"
  physical="$(cd -- "$requested" && pwd -P)"
  git_root="$(git -C "$physical" rev-parse --show-toplevel 2>/dev/null)" ||
    die "not a Git worktree: $requested"
  git_root="$(cd -- "$git_root" && pwd -P)"
  [[ "$physical" == "$git_root" ]] ||
    die "path must be the Git worktree root (got $physical, root is $git_root)"
  printf '%s' "$physical"
}

# Emit mode/object/stage for index entries whose recorded path is exactly the
# supplied literal path. A directory-shaped pathspec may also select descendants.
exact_index_entries() {
  local root="$1" path="$2" line metadata recorded mode object stage index_output
  index_output="$(mktemp "${TMPDIR:-/tmp}/standards-index.XXXXXX")" || return 1
  if ! git -C "$root" --literal-pathspecs -c core.quotePath=false \
    ls-files --stage -z -- "$path" >"$index_output"; then
    rm -f -- "$index_output"
    return 1
  fi
  while IFS= read -r -d '' line; do
    [[ "$line" == *$'\t'* ]] || continue
    metadata="${line%%$'\t'*}"
    recorded="${line#*$'\t'}"
    [[ "$recorded" == "$path" ]] || continue
    read -r mode object stage <<<"$metadata"
    printf '%s %s %s\n' "$mode" "$object" "$stage"
  done <"$index_output"
  rm -f -- "$index_output"
}

read_exact_index_entries() {
  local root="$1" path="$2" output
  INDEX_ENTRIES=()
  # exact_index_entries checks each fallible command and intentionally runs as
  # the condition whose status is propagated here.
  # shellcheck disable=SC2310
  output="$(exact_index_entries "$root" "$path")" ||
    die "could not inspect Git index path: $path"
  [[ -z "$output" ]] || mapfile -t INDEX_ENTRIES <<<"$output"
}

tracked_regular_mode() {
  local root="$1" path="$2" purpose="$3" mode object stage worktree_object
  local -a entries
  read_exact_index_entries "$root" "$path"
  entries=("${INDEX_ENTRIES[@]}")
  [[ "${#entries[@]}" -eq 1 ]] ||
    die "$purpose must be exactly one tracked stage-0 file: $path"
  read -r mode object stage <<<"${entries[0]}"
  [[ "$stage" == 0 ]] || die "$purpose is unmerged in the Git index: $path"
  case "$mode" in
  100644 | 100755) ;;
  *) die "$purpose must be a regular Git file (mode is $mode): $path" ;;
  esac
  [[ ! "$object" =~ ^0+$ ]] || die "$purpose has no indexed object yet: $path"
  [[ -f "$root/$path" && ! -L "$root/$path" ]] ||
    die "$purpose must exist as a non-symlink regular worktree file: $path"
  worktree_object="$(git -C "$root" hash-object --no-filters -- "$path")" ||
    die "could not hash $purpose worktree file: $path"
  [[ "$worktree_object" == "$object" ]] ||
    die "$purpose worktree bytes differ from the indexed object: $path"
  printf '%s' "$mode"
}

yq_assert() {
  local expression="$1" message="$2"
  yq eval --exit-status "$expression" "$MANIFEST_ABS" >/dev/null 2>&1 ||
    die "$message"
}

assert_sorted_unique() {
  local label="$1"
  shift
  local value previous='' first=true
  local -A seen=()
  for value in "$@"; do
    [[ -z "${seen[$value]+present}" ]] || die "$label contains duplicate '$value'"
    seen["$value"]=1
    if [[ "$first" == false && "$previous" > "$value" ]]; then
      die "$label must be sorted ('$previous' appears before '$value')"
    fi
    first=false
    previous="$value"
  done
}

validate_record_keys() {
  local label="$1" required="$2" optional_csv="$3"
  shift 3
  local -a optional_keys=()
  [[ -z "$optional_csv" ]] || IFS=',' read -r -a optional_keys <<<"$optional_csv"
  local key opt found=false is_optional
  for key in "$@"; do
    if [[ "$key" == "$required" ]]; then
      found=true
      continue
    fi
    is_optional=false
    for opt in "${optional_keys[@]+"${optional_keys[@]}"}"; do
      [[ "$key" != "$opt" ]] || {
        is_optional=true
        break
      }
    done
    [[ "$is_optional" == true ]] || die "$label contains unknown key '$key'"
  done
  [[ "$found" == true ]] || die "$label is missing required key '$required'"
}

declare -a COMPONENT_NAMES=() TARGET_NAMES=()
declare -A COMPONENT_EXISTS=() TARGET_EXISTS=()
declare -A FILES_BY_COMPONENT=() SOURCE_MODES=() REQUIRES_BY_COMPONENT=()
declare -A MANAGED_BY_TARGET=() LOCAL_BY_TARGET=() VISIT_STATE=()
declare -A AUTOMERGE_BY_TARGET=()
declare -a VISIT_PATH=()

# Structural facts for every component and target, read in one yq pass each
# instead of one pass per record. Two yq behaviors shape the row design:
#
#   * Traversing an absent key materializes it, so a bare `.value.requires`
#     probe would make a later `keys` report a key the manifest never declared.
#     Every descent is gated behind `has(...)`.
#   * `@tsv` does not escape embedded tabs or newlines, so a path containing one
#     would split its own row and desynchronize the stream. Payload rows are
#     emitted only for records that already satisfy the control-character check,
#     and the shell reports that violation from the boolean columns below before
#     it reads any payload.
#
# Each row is `kind<TAB>record-name<TAB>value...`. Record names are proven free
# of control characters before either pass runs, so the first two columns always
# frame correctly.
# The $-prefixed names below are yq's own binding variables, not shell
# parameters, so the expressions are deliberately single-quoted.
# shellcheck disable=SC2016
readonly COMPONENT_ROW_EXPRESSION='.components | to_entries[] | (
  ["ctag", .key, (.value | tag)],
  (select((.value | tag) == "!!map") | . as $c | (
    ($c.value | keys[] | ["ckey", $c.key, .]),
    (select($c.value | has("files")) | . as $h | (
      ["cftag", $h.key, ($h.value.files | tag), (($h.value.files | length) > 0)],
      (select(($h.value.files | tag) == "!!map") | . as $f | (
        ["cfstr", $f.key,
          ($f.value.files | [to_entries[] | (.key, .value) | (tag == "!!str")] | all),
          ($f.value.files | [to_entries[] | (.key, .value) | select(tag == "!!str") | (test(strenv(CONTROL_RE)) | not)] | all)],
        (select($f.value.files | [to_entries[] | (.key, .value) | (tag == "!!str")] | all)
          | select($f.value.files | [to_entries[] | (.key, .value) | (test(strenv(CONTROL_RE)) | not)] | all)
          | . as $g | ($g.value.files | to_entries[] | ["cfile", $g.key, .key, .value])))))),
    (select($c.value | has("requires")) | . as $q | (
      ["crtag", $q.key, ($q.value.requires | tag), (($q.value.requires | length) > 0)],
      (select(($q.value.requires | tag) == "!!seq") | . as $r | (
        ["crstr", $r.key,
          ($r.value.requires | [.[] | (tag == "!!str")] | all),
          ($r.value.requires | [.[] | select(tag == "!!str") | (test(strenv(CONTROL_RE)) | not)] | all)],
        (select($r.value.requires | [.[] | (tag == "!!str")] | all)
          | select($r.value.requires | [.[] | (test(strenv(CONTROL_RE)) | not)] | all)
          | . as $s | ($s.value.requires[] | ["creq", $s.key, .]))))))
  ))
) | @tsv'

# shellcheck disable=SC2016 # yq binding variables; see COMPONENT_ROW_EXPRESSION.
readonly TARGET_ROW_EXPRESSION='.targets | to_entries[] | (
  ["ttag", .key, (.value | tag)],
  (select((.value | tag) == "!!map") | . as $t | (
    ($t.value | keys[] | ["tkey", $t.key, .]),
    (select($t.value | has("managed")) | . as $m | (
      ["tmtag", $m.key, ($m.value.managed | tag), (($m.value.managed | length) > 0)],
      (select(($m.value.managed | tag) == "!!seq") | . as $n | (
        ["tmstr", $n.key,
          ($n.value.managed | [.[] | (tag == "!!str")] | all),
          ($n.value.managed | [.[] | select(tag == "!!str") | (test(strenv(CONTROL_RE)) | not)] | all)],
        (select($n.value.managed | [.[] | (tag == "!!str")] | all)
          | select($n.value.managed | [.[] | (test(strenv(CONTROL_RE)) | not)] | all)
          | . as $o | ($o.value.managed[] | ["tman", $o.key, .])))))),
    (select($t.value | has("locally-owned")) | . as $l | (
      ["tltag", $l.key, ($l.value["locally-owned"] | tag), (($l.value["locally-owned"] | length) > 0)],
      (select(($l.value["locally-owned"] | tag) == "!!seq") | . as $p | (
        ["tlstr", $p.key,
          ($p.value["locally-owned"] | [.[] | (tag == "!!str")] | all),
          ($p.value["locally-owned"] | [.[] | select(tag == "!!str") | (test(strenv(CONTROL_RE)) | not)] | all)],
        (select($p.value["locally-owned"] | [.[] | (tag == "!!str")] | all)
          | select($p.value["locally-owned"] | [.[] | (test(strenv(CONTROL_RE)) | not)] | all)
          | . as $q | ($q.value["locally-owned"][] | ["tloc", $q.key, .])))))),
    (select($t.value | has("automerge")) | . as $a | (
      ["tam", $a.key, ($a.value.automerge | tag)],
      (select(($a.value.automerge | tag) == "!!bool") | . as $b | ["tamv", $b.key, $b.value.automerge])))
  ))
) | @tsv'

declare -A COMPONENT_TAG=() COMPONENT_KEY_ROWS=() COMPONENT_FILES_SHAPE=()
declare -A COMPONENT_FILES_STRINGS=() COMPONENT_FILE_ROWS=()
declare -A COMPONENT_REQUIRES_SHAPE=() COMPONENT_REQUIRES_STRINGS=()
declare -A COMPONENT_REQUIRE_ROWS=()
declare -A TARGET_TAG=() TARGET_KEY_ROWS=() TARGET_MANAGED_SHAPE=()
declare -A TARGET_MANAGED_STRINGS=() TARGET_MANAGED_ROWS=()
declare -A TARGET_LOCAL_SHAPE=() TARGET_LOCAL_STRINGS=() TARGET_LOCAL_ROWS=()
declare -A TARGET_AUTOMERGE_SHAPE=() TARGET_AUTOMERGE_VALUE=()

# A failed pass must not degrade into an empty stream: every loop below would
# then find nothing to reject and the command would report a valid manifest.
# The expected record count is asserted against the names read separately.
load_manifest_rows() {
  local expression="$1" label="$2" expected="$3" rows row kind name rest record_count=0
  rows="$(yq eval -r "$expression" "$MANIFEST_ABS")" ||
    die "could not read the $label catalog from the manifest"
  # Tab is an IFS *whitespace* character, so `IFS=$'\t' read` merges runs of
  # tabs and strips trailing ones: an empty column would disappear and the next
  # value would slide into its place. A path may legitimately be the empty
  # string — and must still be rejected as unsafe rather than silently become
  # its neighbour — so every row is split verbatim. Each emitted kind carries at
  # least three columns, so a row with fewer is a corrupt stream, not a value.
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    [[ "$row" == *$'\t'*$'\t'* ]] ||
      die "internal error: malformed manifest row '$row'"
    kind="${row%%$'\t'*}"
    rest="${row#*$'\t'}"
    name="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    case "$kind" in
    ctag)
      COMPONENT_TAG["$name"]="$rest"
      record_count=$((record_count + 1))
      ;;
    ckey) COMPONENT_KEY_ROWS["$name"]+="$rest"$'\n' ;;
    cftag) COMPONENT_FILES_SHAPE["$name"]="$rest" ;;
    cfstr) COMPONENT_FILES_STRINGS["$name"]="$rest" ;;
    cfile) COMPONENT_FILE_ROWS["$name"]+="$rest"$'\n' ;;
    crtag) COMPONENT_REQUIRES_SHAPE["$name"]="$rest" ;;
    crstr) COMPONENT_REQUIRES_STRINGS["$name"]="$rest" ;;
    creq) COMPONENT_REQUIRE_ROWS["$name"]+="$rest"$'\n' ;;
    ttag)
      TARGET_TAG["$name"]="$rest"
      record_count=$((record_count + 1))
      ;;
    tkey) TARGET_KEY_ROWS["$name"]+="$rest"$'\n' ;;
    tmtag) TARGET_MANAGED_SHAPE["$name"]="$rest" ;;
    tmstr) TARGET_MANAGED_STRINGS["$name"]="$rest" ;;
    tman) TARGET_MANAGED_ROWS["$name"]+="$rest"$'\n' ;;
    tltag) TARGET_LOCAL_SHAPE["$name"]="$rest" ;;
    tlstr) TARGET_LOCAL_STRINGS["$name"]="$rest" ;;
    tloc) TARGET_LOCAL_ROWS["$name"]+="$rest"$'\n' ;;
    tam) TARGET_AUTOMERGE_SHAPE["$name"]="$rest" ;;
    tamv) TARGET_AUTOMERGE_VALUE["$name"]="$rest" ;;
    *) die "internal error: unrecognized manifest row kind '$kind'" ;;
    esac
  done <<<"$rows"
  [[ "$record_count" -eq "$expected" ]] ||
    die "manifest $label pass reported $record_count records, expected $expected"
}

# Split a stored row into fields without letting a value's own tabs create
# extra ones: the caller names exactly the columns the row kind carries.
read_row_fields() {
  local row="$1"
  shift
  IFS=$'\t' read -r "$@" <<<"$row"
}

# Emit an accumulated row block as ROW_VALUES, mirroring read_exact_index_entries'
# global-output idiom so the script keeps working on Bash 4.0 (no namerefs).
declare -a ROW_VALUES=()
read_row_values() {
  local text="$1"
  ROW_VALUES=()
  [[ -n "$text" ]] || return 0
  mapfile -t ROW_VALUES <<<"${text%$'\n'}"
}

visit_component() {
  local component="$1" dependency cycle
  case "${VISIT_STATE[$component]-}" in
  done) return 0 ;;
  visiting)
    cycle="$(
      IFS=' -> '
      printf '%s' "${VISIT_PATH[*]}"
    )"
    die "component dependency cycle: $cycle -> $component"
    ;;
  *) ;;
  esac
  VISIT_STATE["$component"]=visiting
  VISIT_PATH+=("$component")
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    visit_component "$dependency"
  done <<<"${REQUIRES_BY_COMPONENT[$component]-}"
  unset 'VISIT_PATH[${#VISIT_PATH[@]}-1]'
  VISIT_STATE["$component"]='done'
}

validate_manifest() {
  local root_key component key source destination existing_destination mode dependency target selected_component
  local has_requires has_local has_automerge automerge_value
  local files_tag files_nonempty files_strings files_control file_row
  local requires_tag requires_nonempty requires_strings requires_control
  local managed_tag managed_nonempty managed_strings managed_control
  local local_tag local_nonempty local_strings local_control automerge_tag
  local -a root_keys component_keys file_sources file_rows dependencies target_keys managed locally_owned
  local -A destination_owner=() selected=()

  yq eval-all --exit-status '[.] | length == 1' "$MANIFEST_ABS" >/dev/null 2>&1 ||
    die 'manifest must be valid, single-document YAML'
  yq_assert 'tag == "!!map"' 'manifest root must be a mapping'
  yq_assert \
    '[.. | select(tag == "!!map") | ((keys | length) == (keys | unique | length))] | all' \
    'manifest contains a duplicate mapping key'

  mapfile -t root_keys < <(yq eval -r 'keys[]' "$MANIFEST_ABS")
  for root_key in "${root_keys[@]}"; do
    case "$root_key" in
    version | components | targets) ;;
    *) die "manifest root contains unknown key '$root_key'" ;;
    esac
  done
  for root_key in version components targets; do
    yq_assert "has(\"$root_key\")" "manifest root is missing '$root_key'"
  done
  yq_assert '(.version | tag == "!!int") and (.version == 2)' \
    'manifest version must be the integer 2'
  yq_assert '(.components | tag == "!!map") and (.components | length > 0)' \
    'components must be a non-empty mapping'
  yq_assert '(.targets | tag == "!!map") and (.targets | length > 0)' \
    'targets must be a non-empty mapping'
  yq_assert '.components | [to_entries[].key | tag == "!!str"] | all' \
    'component names must be strings'
  yq_assert ".components | [to_entries[].key | (test(\"$CONTROL_RE\") | not)] | all" \
    'component names may not contain control characters'
  yq_assert '.targets | [to_entries[].key | tag == "!!str"] | all' \
    'target names must be strings'
  yq_assert ".targets | [to_entries[].key | (test(\"$CONTROL_RE\") | not)] | all" \
    'target names may not contain control characters'

  mapfile -t COMPONENT_NAMES < <(yq eval -r '.components | keys[]' "$MANIFEST_ABS")
  assert_sorted_unique 'component names' "${COMPONENT_NAMES[@]}"
  for component in "${COMPONENT_NAMES[@]}"; do
    [[ "$component" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] ||
      die "invalid component name '$component' (expected lowercase kebab-case)"
    COMPONENT_EXISTS["$component"]=1
  done

  load_manifest_rows "$COMPONENT_ROW_EXPRESSION" component "${#COMPONENT_NAMES[@]}"
  for component in "${COMPONENT_NAMES[@]}"; do
    [[ "${COMPONENT_TAG[$component]-}" == '!!map' ]] ||
      die "component '$component' must be a mapping"
    read_row_values "${COMPONENT_KEY_ROWS[$component]-}"
    component_keys=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
    validate_record_keys "component '$component'" files requires \
      "${component_keys[@]+"${component_keys[@]}"}"
    has_requires=false
    for key in "${component_keys[@]+"${component_keys[@]}"}"; do
      [[ "$key" == requires ]] && has_requires=true
    done

    read_row_fields "${COMPONENT_FILES_SHAPE[$component]-}" files_tag files_nonempty
    [[ "$files_tag" == '!!map' && "$files_nonempty" == true ]] ||
      die "component '$component' files must be a non-empty mapping"
    read_row_fields "${COMPONENT_FILES_STRINGS[$component]-}" files_strings files_control
    [[ "$files_strings" == true ]] ||
      die "component '$component' file sources and destinations must be strings"
    [[ "$files_control" == true ]] ||
      die "component '$component' file paths may not contain control characters"
    read_row_values "${COMPONENT_FILE_ROWS[$component]-}"
    file_rows=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
    file_sources=()
    for file_row in "${file_rows[@]+"${file_rows[@]}"}"; do
      file_sources+=("${file_row%%$'\t'*}")
    done
    assert_sorted_unique "component '$component' file sources" \
      "${file_sources[@]+"${file_sources[@]}"}"
    FILES_BY_COMPONENT["$component"]=''
    for file_row in "${file_rows[@]+"${file_rows[@]}"}"; do
      source="${file_row%%$'\t'*}"
      destination="${file_row#*$'\t'}"
      # Predicate calls intentionally run in conditions; the function contains
      # no errexit-dependent commands.
      # shellcheck disable=SC2310
      if ! is_safe_repo_path "$source"; then
        die "component '$component' has unsafe source path '$source'"
      fi
      # shellcheck disable=SC2310
      if ! is_safe_repo_path "$destination"; then
        die "component '$component' has unsafe destination path '$destination'"
      fi
      # A source MAY back multiple components: one canonical file fanning out
      # to per-destination components (e.g. path-detection) is the manifest's
      # own answer to consumers with different layouts. Destinations stay
      # globally unique below — that is the write-conflict invariant.
      [[ -z "${destination_owner[$destination]+present}" ]] ||
        die "destination '$destination' is owned by both '${destination_owner[$destination]}' and '$component'"
      for existing_destination in "${!destination_owner[@]}"; do
        if [[ "$destination" == "$existing_destination/"* ||
          "$existing_destination" == "$destination/"* ]]; then
          die "destination '$destination' in '$component' has a file/directory conflict with '$existing_destination' in '${destination_owner[$existing_destination]}'"
        fi
      done
      destination_owner["$destination"]="$component"
      mode="$(tracked_regular_mode "$SOURCE_ROOT" "$source" "component '$component' source")"
      SOURCE_MODES["$source"]="$mode"
      FILES_BY_COMPONENT["$component"]+="$source"$'\t'"$destination"$'\n'
    done

    REQUIRES_BY_COMPONENT["$component"]=''
    if [[ "$has_requires" == true ]]; then
      read_row_fields "${COMPONENT_REQUIRES_SHAPE[$component]-}" \
        requires_tag requires_nonempty
      [[ "$requires_tag" == '!!seq' && "$requires_nonempty" == true ]] ||
        die "component '$component' requires must be a non-empty sequence"
      read_row_fields "${COMPONENT_REQUIRES_STRINGS[$component]-}" \
        requires_strings requires_control
      [[ "$requires_strings" == true ]] ||
        die "component '$component' dependencies must be strings"
      [[ "$requires_control" == true ]] ||
        die "component '$component' dependencies may not contain control characters"
      read_row_values "${COMPONENT_REQUIRE_ROWS[$component]-}"
      dependencies=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
      assert_sorted_unique "component '$component' dependencies" \
        "${dependencies[@]+"${dependencies[@]}"}"
      for dependency in "${dependencies[@]+"${dependencies[@]}"}"; do
        [[ -n "${COMPONENT_EXISTS[$dependency]+present}" ]] ||
          die "component '$component' requires unknown component '$dependency'"
        [[ "$dependency" != "$component" ]] ||
          die "component '$component' may not require itself"
        REQUIRES_BY_COMPONENT["$component"]+="$dependency"$'\n'
      done
    fi
  done

  VISIT_STATE=()
  VISIT_PATH=()
  for component in "${COMPONENT_NAMES[@]}"; do visit_component "$component"; done

  mapfile -t TARGET_NAMES < <(yq eval -r '.targets | keys[]' "$MANIFEST_ABS")
  assert_sorted_unique 'target names' "${TARGET_NAMES[@]}"
  for target in "${TARGET_NAMES[@]}"; do
    [[ "$target" =~ ^[a-z0-9][a-z0-9-]*\/[a-z0-9._-]+$ ]] ||
      die "invalid target repository '$target' (expected lowercase owner/repo)"
    TARGET_EXISTS["$target"]=1
  done

  load_manifest_rows "$TARGET_ROW_EXPRESSION" target "${#TARGET_NAMES[@]}"
  for target in "${TARGET_NAMES[@]}"; do
    [[ "${TARGET_TAG[$target]-}" == '!!map' ]] ||
      die "target '$target' must be a mapping"
    read_row_values "${TARGET_KEY_ROWS[$target]-}"
    target_keys=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
    validate_record_keys "target '$target'" managed "locally-owned,automerge" \
      "${target_keys[@]+"${target_keys[@]}"}"
    has_local=false
    has_automerge=false
    for key in "${target_keys[@]+"${target_keys[@]}"}"; do
      [[ "$key" == locally-owned ]] && has_local=true
      [[ "$key" == automerge ]] && has_automerge=true
    done

    read_row_fields "${TARGET_MANAGED_SHAPE[$target]-}" managed_tag managed_nonempty
    [[ "$managed_tag" == '!!seq' && "$managed_nonempty" == true ]] ||
      die "target '$target' managed must be a non-empty sequence"
    read_row_fields "${TARGET_MANAGED_STRINGS[$target]-}" managed_strings managed_control
    [[ "$managed_strings" == true ]] ||
      die "target '$target' managed entries must be strings"
    [[ "$managed_control" == true ]] ||
      die "target '$target' managed entries may not contain control characters"
    read_row_values "${TARGET_MANAGED_ROWS[$target]-}"
    managed=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
    assert_sorted_unique "target '$target' managed components" \
      "${managed[@]+"${managed[@]}"}"

    locally_owned=()
    if [[ "$has_local" == true ]]; then
      read_row_fields "${TARGET_LOCAL_SHAPE[$target]-}" local_tag local_nonempty
      [[ "$local_tag" == '!!seq' && "$local_nonempty" == true ]] ||
        die "target '$target' locally-owned must be a non-empty sequence when present"
      read_row_fields "${TARGET_LOCAL_STRINGS[$target]-}" local_strings local_control
      [[ "$local_strings" == true ]] ||
        die "target '$target' locally-owned entries must be strings"
      [[ "$local_control" == true ]] ||
        die "target '$target' locally-owned entries may not contain control characters"
      read_row_values "${TARGET_LOCAL_ROWS[$target]-}"
      locally_owned=("${ROW_VALUES[@]+"${ROW_VALUES[@]}"}")
      assert_sorted_unique "target '$target' locally-owned components" \
        "${locally_owned[@]+"${locally_owned[@]}"}"
    fi

    # Absent means true: automerge is opt-out policy-as-data, so a target that
    # never mentions the key keeps the fleet-default armed behavior.
    automerge_value=true
    if [[ "$has_automerge" == true ]]; then
      read_row_fields "${TARGET_AUTOMERGE_SHAPE[$target]-}" automerge_tag
      [[ "$automerge_tag" == '!!bool' ]] ||
        die "target '$target' automerge must be a boolean"
      automerge_value="${TARGET_AUTOMERGE_VALUE[$target]-}"
    fi
    AUTOMERGE_BY_TARGET["$target"]="$automerge_value"

    selected=()
    MANAGED_BY_TARGET["$target"]=''
    LOCAL_BY_TARGET["$target"]=''
    for selected_component in "${managed[@]}"; do
      [[ -n "${COMPONENT_EXISTS[$selected_component]+present}" ]] ||
        die "target '$target' manages unknown component '$selected_component'"
      selected["$selected_component"]=1
      MANAGED_BY_TARGET["$target"]+="$selected_component"$'\n'
    done
    for selected_component in "${locally_owned[@]+"${locally_owned[@]}"}"; do
      [[ -n "${COMPONENT_EXISTS[$selected_component]+present}" ]] ||
        die "target '$target' locally owns unknown component '$selected_component'"
      [[ -z "${selected[$selected_component]+present}" ]] ||
        die "target '$target' lists '$selected_component' as both managed and locally-owned"
      selected["$selected_component"]=1
      LOCAL_BY_TARGET["$target"]+="$selected_component"$'\n'
    done

    # A locally-owned implementation may satisfy a managed component's required
    # capability, but its own internal dependency closure remains downstream's.
    for selected_component in "${managed[@]}"; do
      while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        [[ -n "${selected[$dependency]+present}" ]] ||
          die "target '$target' manages '$selected_component' but does not select required '$dependency'"
      done <<<"${REQUIRES_BY_COMPONENT[$selected_component]-}"
    done
  done
}

select_targets() {
  local filter="$1" rest token target done=false
  local -A requested=()
  SELECTED_TARGETS=()
  if [[ -z "$filter" ]]; then
    SELECTED_TARGETS=("${TARGET_NAMES[@]}")
    return
  fi
  rest="$filter"
  while [[ "$done" == false ]]; do
    if [[ "$rest" == *,* ]]; then
      token="${rest%%,*}"
      rest="${rest#*,}"
    else
      token="$rest"
      done=true
    fi
    token="$(trim "$token")"
    [[ -n "$token" ]] || die 'targets filter contains an empty repository name'
    [[ -n "${TARGET_EXISTS[$token]+present}" ]] ||
      die "targets filter names unknown manifest target '$token'"
    [[ -z "${requested[$token]+present}" ]] ||
      die "targets filter contains duplicate '$token'"
    requested["$token"]=1
  done
  for target in "${TARGET_NAMES[@]}"; do
    [[ -n "${requested[$target]+present}" ]] && SELECTED_TARGETS+=("$target")
  done
  return 0
}

emit_matrix() {
  local target owner repo separator=''
  printf '{"include":['
  for target in "${SELECTED_TARGETS[@]}"; do
    owner="${target%%/*}"
    repo="${target:${#owner}+1}"
    printf '%s{"repo":"%s","repo_owner":"%s","repo_name":"%s","automerge":%s}' \
      "$separator" "$target" "$owner" "$repo" "${AUTOMERGE_BY_TARGET[$target]}"
    separator=','
  done
  printf ']}\n'
}

emit_managed_mappings() {
  local target="$1" component source destination mode
  while IFS= read -r component; do
    [[ -n "$component" ]] || continue
    while IFS=$'\t' read -r source destination; do
      [[ -n "$source" ]] || continue
      mode="${SOURCE_MODES[$source]}"
      printf -- "- **%s**: \`%s\` → \`%s\` (mode \`%s\`)\n" \
        "$component" "$source" "$destination" "$mode"
    done <<<"${FILES_BY_COMPONENT[$component]}"
  done <<<"${MANAGED_BY_TARGET[$target]}"
}

emit_plan() {
  local target component source destination mode
  printf 'Distribution plan:\n'
  for target in "${SELECTED_TARGETS[@]}"; do
    printf '## %s\n' "$target"
    printf '  automerge: %s\n' "${AUTOMERGE_BY_TARGET[$target]}"
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      printf '  managed %s:\n' "$component"
      while IFS=$'\t' read -r source destination; do
        [[ -n "$source" ]] || continue
        mode="${SOURCE_MODES[$source]}"
        printf '    %s %s -> %s\n' "$mode" "$source" "$destination"
      done <<<"${FILES_BY_COMPONENT[$component]}"
    done <<<"${MANAGED_BY_TARGET[$target]}"
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      printf '  locally-owned %s (not modified)\n' "$component"
    done <<<"${LOCAL_BY_TARGET[$target]-}"
  done
}

verify_target_identity() {
  local target_root="$1" expected="$2" output url identity
  local -a urls
  output="$(git -C "$target_root" remote get-url --all origin 2>/dev/null)" ||
    die "target checkout has no readable origin remote: $expected"
  urls=()
  [[ -z "$output" ]] || mapfile -t urls <<<"$output"
  [[ "${#urls[@]}" -eq 1 ]] ||
    die "target checkout must have exactly one origin URL: $expected"
  url="${urls[0]}"
  if [[ "$url" =~ ^https://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(\.git)?/?$ ]]; then
    identity="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github\.com:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(\.git)?$ ]]; then
    identity="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^ssh://git@github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(\.git)?$ ]]; then
    identity="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    die "target origin is not an approved GitHub repository URL: $url"
  fi
  identity="${identity%.git}"
  [[ "${identity,,}" == "$expected" ]] ||
    die "target origin identifies '$identity', expected '$expected'"
}

preflight_destination() {
  local target_root="$1" destination="$2" parent prefix='' segment path mode object stage
  local -a segments entries
  parent="${destination%/*}"
  [[ "$parent" != "$destination" ]] || parent=''
  if [[ -n "$parent" ]]; then
    IFS='/' read -r -a segments <<<"$parent"
    for segment in "${segments[@]}"; do
      prefix="${prefix:+$prefix/}$segment"
      path="$target_root/$prefix"
      [[ ! -L "$path" ]] || die "destination parent is a symlink: $prefix"
      [[ ! -e "$path" || -d "$path" ]] ||
        die "destination parent is not a directory: $prefix"
      read_exact_index_entries "$target_root" "$prefix"
      entries=("${INDEX_ENTRIES[@]}")
      [[ "${#entries[@]}" -eq 0 ]] ||
        die "destination parent is a tracked non-directory entry: $prefix"
    done
  fi
  path="$target_root/$destination"
  [[ ! -L "$path" ]] || die "destination is a symlink: $destination"
  read_exact_index_entries "$target_root" "$destination"
  entries=("${INDEX_ENTRIES[@]}")
  [[ "${#entries[@]}" -le 1 ]] ||
    die "destination has multiple Git index entries: $destination"
  if [[ -e "$path" ]]; then
    [[ -f "$path" ]] || die "destination exists but is not a regular file: $destination"
    [[ "${#entries[@]}" -eq 1 ]] ||
      die "refusing to overwrite untracked destination: $destination"
    read -r mode object stage <<<"${entries[0]}"
    [[ "$stage" == 0 && ("$mode" == 100644 || "$mode" == 100755) ]] ||
      die "existing destination is not a tracked stage-0 regular file: $destination"
  elif [[ "${#entries[@]}" -ne 0 ]]; then
    die "tracked destination is missing from the worktree: $destination"
  fi
}

apply_target() {
  local target="$1" target_root="$2" component source destination mode index
  local -a components sources=() destinations=() modes=()
  target_root="$(canonical_git_root "$target_root")"
  verify_target_identity "$target_root" "$target"
  mapfile -t components < <(
    while IFS= read -r component; do
      [[ -n "$component" ]] && printf '%s\n' "$component"
    done <<<"${MANAGED_BY_TARGET[$target]}"
  )
  # Validate all destinations before the first mutation. A later I/O error stops
  # the workflow before PR creation, so no partial component update is published.
  for component in "${components[@]}"; do
    while IFS=$'\t' read -r source destination; do
      [[ -n "$source" ]] || continue
      preflight_destination "$target_root" "$destination"
      sources+=("$source")
      destinations+=("$destination")
      modes+=("${SOURCE_MODES[$source]}")
    done <<<"${FILES_BY_COMPONENT[$component]}"
  done
  for index in "${!sources[@]}"; do
    source="${sources[$index]}"
    destination="${destinations[$index]}"
    mode="${modes[$index]}"
    mkdir -p -- "$target_root/$(dirname -- "$destination")"
    cp -- "$SOURCE_ROOT/$source" "$target_root/$destination"
    case "$mode" in
    100644) chmod 0644 "$target_root/$destination" ;;
    100755) chmod 0755 "$target_root/$destination" ;;
    *) die "internal error: unsupported validated mode '$mode'" ;;
    esac
    printf 'synced %s -> %s (%s)\n' "$source" "$destination" "$mode"
  done
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}
COMMAND="$1"
shift
case "$COMMAND" in
validate | matrix | plan | mappings | apply) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  die "unknown command '$COMMAND'"
  ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
MANIFEST="$DEFAULT_MANIFEST"
TARGETS_FILTER=''
TARGET=''
TARGET_ROOT=''
while [[ $# -gt 0 ]]; do
  case "$1" in
  --source-root)
    [[ $# -ge 2 ]] || die '--source-root requires a value'
    SOURCE_ROOT="$2"
    shift 2
    ;;
  --manifest)
    [[ $# -ge 2 ]] || die '--manifest requires a value'
    MANIFEST="$2"
    shift 2
    ;;
  --targets)
    [[ $# -ge 2 ]] || die '--targets requires a value'
    TARGETS_FILTER="$2"
    shift 2
    ;;
  --target)
    [[ $# -ge 2 ]] || die '--target requires a value'
    TARGET="$2"
    shift 2
    ;;
  --target-root)
    [[ $# -ge 2 ]] || die '--target-root requires a value'
    TARGET_ROOT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument '$1'" ;;
  esac
done

require_command git
require_command yq
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || die 'Bash 4 or newer is required'
yq_version="$(yq --version 2>/dev/null || true)"
[[ "$yq_version" =~ version[[:space:]]+v?4\. ]] ||
  die "Mike Farah yq v4 is required (got: ${yq_version:-unknown})"
SOURCE_ROOT="$(canonical_git_root "$SOURCE_ROOT")"
# Intentional predicate; see validation calls above.
# shellcheck disable=SC2310
if ! is_safe_repo_path "$MANIFEST"; then die "unsafe manifest path '$MANIFEST'"; fi
tracked_regular_mode "$SOURCE_ROOT" "$MANIFEST" manifest >/dev/null
MANIFEST_ABS="$SOURCE_ROOT/$MANIFEST"

case "$COMMAND" in
validate)
  [[ -z "$TARGETS_FILTER" && -z "$TARGET" && -z "$TARGET_ROOT" ]] ||
    die 'validate does not accept --targets, --target, or --target-root'
  ;;
matrix | plan)
  [[ -z "$TARGET" && -z "$TARGET_ROOT" ]] ||
    die "$COMMAND does not accept --target or --target-root"
  ;;
mappings)
  [[ -z "$TARGETS_FILTER" && -z "$TARGET_ROOT" ]] ||
    die 'mappings does not accept --targets or --target-root'
  [[ -n "$TARGET" ]] || die 'mappings requires --target OWNER/REPO'
  ;;
apply)
  [[ -z "$TARGETS_FILTER" ]] || die 'apply does not accept --targets'
  [[ -n "$TARGET" ]] || die 'apply requires --target OWNER/REPO'
  [[ -n "$TARGET_ROOT" ]] || die 'apply requires --target-root DIR'
  ;;
*) die "internal error: unsupported command '$COMMAND'" ;;
esac

validate_manifest
case "$COMMAND" in
validate)
  printf 'Manifest valid: %d components, %d targets\n' \
    "${#COMPONENT_NAMES[@]}" "${#TARGET_NAMES[@]}"
  ;;
matrix)
  declare -a SELECTED_TARGETS=()
  select_targets "$TARGETS_FILTER"
  emit_matrix
  ;;
plan)
  declare -a SELECTED_TARGETS=()
  select_targets "$TARGETS_FILTER"
  emit_plan
  ;;
mappings)
  [[ -n "${TARGET_EXISTS[$TARGET]+present}" ]] || die "unknown manifest target '$TARGET'"
  emit_managed_mappings "$TARGET"
  ;;
apply)
  [[ -n "${TARGET_EXISTS[$TARGET]+present}" ]] || die "unknown manifest target '$TARGET'"
  apply_target "$TARGET" "$TARGET_ROOT"
  ;;
*) die "internal error: unsupported command '$COMMAND'" ;;
esac
