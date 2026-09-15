//go:build windows

package main

import (
	"os"
	"path/filepath"
	"testing"
)

// A Windows C++ workspace can contain both a Visual Studio solution and CMake
// configuration. Detection is read-only: this test uses a fake MSVC layout and
// verifies no solution, CMake, or compiler process needs to be started.
func TestWindowsMSVCAndCMakeDiscovery(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"CMakeLists.txt", "sample.sln", "main.cpp"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte{}, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	programFiles := t.TempDir()
	compiler := filepath.Join(programFiles, "Microsoft Visual Studio", "2022", "BuildTools", "VC", "Tools", "MSVC", "14.0", "bin", "Hostx64", "x64", "cl.exe")
	if err := os.MkdirAll(filepath.Dir(compiler), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(compiler, nil, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ProgramFiles", programFiles)
	t.Setenv("ProgramFiles(x86)", "")

	m := newLSPManager(root, false)
	s := m.Setup("main.cpp").MSVC
	if s == nil || !s.VisualStudio || !s.CMake {
		t.Fatalf("Setup().MSVC = %#v, want Visual Studio and CMake metadata", s)
	}
	if !s.Available {
		t.Fatalf("Setup().MSVC = %#v, want the fake MSVC compiler to be found", s)
	}
}
