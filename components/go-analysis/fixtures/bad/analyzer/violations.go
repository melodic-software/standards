// Package analyzer supplies focused violations for the enabled analyzers.
package analyzer

import (
	"os"
	"strings"
)

// DiscardError ignores an error result.
func DiscardError() {
	os.Chdir(".")
}

// Ineffective assigns a value that is overwritten before it is observed.
func Ineffective() int {
	value := 1
	value = 2
	return value
}

// Normalize discards the result of a pure function.
func Normalize(value string) {
	strings.ReplaceAll(value, "old", "new")
}

func unused() {}
