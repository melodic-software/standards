package example

import "strings"

// Normalize exercises a justified, narrow analyzer suppression.
func Normalize(value string) {
	strings.ReplaceAll(value, "old", "new") //nolint:staticcheck // Contract fixture intentionally discards the pure result.
}
