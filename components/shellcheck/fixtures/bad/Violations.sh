#!/usr/bin/env bash
# Bad fixture: intentional violations the ruleset must flag. Excluded from the
# repo's own self-lint.
echo $1

if [ "$1" = "x" ]; then
  which ls
fi

cat notes.txt | grep foo
