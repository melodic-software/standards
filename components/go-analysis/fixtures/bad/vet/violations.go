// Package vet supplies the suspicious-construct fixture.
package vet

import "fmt"

// Print reports fixture data.
func Print() {
	fmt.Printf("%d", "not a number")
}
