// Package suppressionreason supplies an unexplained suppression.
package suppressionreason

import "strings"

// Normalize omits the suppression reason.
func Normalize(value string) {
	strings.ReplaceAll(value, "old", "new") //nolint:staticcheck
}
