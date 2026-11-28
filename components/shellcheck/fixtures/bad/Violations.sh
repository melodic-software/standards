#!/usr/bin/env bash
echo $1

if [ "$1" = "x" ]; then
  which ls
fi

cat notes.txt | grep foo
