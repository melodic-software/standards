// Package suppressionblanket supplies an invalid blanket suppression.
package suppressionblanket

import "strings"

// Normalize omits the suppressed linter name.
func Normalize(value string) {
	strings.ReplaceAll(value, "old", "new") //nolint // Contract fixture has a reason but no linter name.
}
