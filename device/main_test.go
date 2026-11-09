package main

import (
	"strings"
	"testing"
)

func TestRunRequiresWatchedPerson(t *testing.T) {
	err := run(nil)
	if err == nil || !strings.Contains(err.Error(), "--watched-person") {
		t.Fatalf("起動 = %v, want --watched-person が要ると伝えて、受話器を開かない", err)
	}
}
