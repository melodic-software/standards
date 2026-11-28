# shellcheck shell=bash

chp::_record_violation() {
  printf '%s:%s:%s\n' "$1" "$2" "$3"
  violations=$((violations + 1))
}

chp::_scan_comment_line() {
  local lineno="${1%%:*}"
  local line="${1#*:}"

  if [[ "$line" =~ (^|[^[:alnum:]_])(FIXME|HACK)([^[:alnum:]_]|$) ]]; then
    chp::_record_violation "$lineno" warning-marker "${BASH_REMATCH[2]}"
    return
  fi
  shopt -u nocasematch
  if [[ "$line" =~ (^|[^[:alnum:]_])XXX([^[:alnum:]_]|$) ]]; then
    shopt -s nocasematch
    chp::_record_violation "$lineno" warning-marker XXX
    return
  fi
  shopt -s nocasematch
  if [[ "$line" =~ (^|[^[:alnum:]_])TODO([^[:alnum:]_]|$) ]]; then
    chp::_record_violation "$lineno" warning-marker TODO
    return
  fi

  if [[ "$line" =~ cc-issue ]]; then
    chp::_record_violation "$lineno" tracker-ref cc-issue
    return
  fi

  # GitHub closing keywords only close an issue when paired with a #number, so the # is required:
  # https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
  if [[ "$line" =~ (^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref closing-keyword
    return
  fi

  if [[ "$line" =~ (^|[^[:alnum:]_])(issues?|tracked)[[:space:]]*:?[[:space:]]*#?[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref issue-reference
    return
  fi

  # '_' stays in the owner class: Enterprise Managed User logins end in '_SHORTCODE':
  # https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/iam-configuration-reference/username-considerations-for-external-authentication
  if [[ "$line" =~ (^|[^[:alnum:]_/.-])[A-Za-z0-9_-]+/[A-Za-z0-9._-]+#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref repo-issue
    return
  fi

  if [[ "$line" =~ (^|[^[:alnum:]_])GH-[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref gh-reference
    return
  fi

  if [[ "$line" =~ (^|[^[:alnum:]_])PR[[:space:]]*#[0-9]+ ]]; then
    chp::_record_violation "$lineno" tracker-ref pr-reference
    return
  fi
}

chp::scan_text() {
  local content="$1"
  local entry violations=0
  local nocase_was=0

  if shopt -q nocasematch; then
    nocase_was=1
  else
    shopt -s nocasematch
  fi

  local comment_re='^[[:space:]]*(//|#|/\*|\*|<!--)'
  if [[ "$content" != *$'\n'* ]]; then
    if [[ "$content" =~ $comment_re ]]; then
      chp::_scan_comment_line "1:$content"
    fi
  else
    while IFS= read -r entry; do
      chp::_scan_comment_line "$entry"
    done < <(awk '/^[[:space:]]*(\/\/|#|\/\*|\*|<!--)/ { print NR ":" $0 }' <<<"$content")
  fi

  if [[ $nocase_was -eq 0 ]]; then
    shopt -u nocasematch
  fi
  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
