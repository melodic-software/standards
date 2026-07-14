// Package suppressionunused supplies a suppression that has no effect.
package suppressionunused

import "strings"

// Normalize returns the pure function result and needs no suppression.
func Normalize(value string) string {
	return strings.ReplaceAll(value, "old", "new") //nolint:staticcheck // Contract fixture suppression is deliberately unused.
}
