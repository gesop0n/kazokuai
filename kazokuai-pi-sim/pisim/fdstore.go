package main

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

type fdStore struct {
	mu   sync.Mutex
	n    int
	sock string
}

func newFDStore() *fdStore {
	return &fdStore{sock: os.Getenv("NOTIFY_SOCKET")}
}

func (s *fdStore) notify(state string, fds ...int) error {
	if s.sock == "" {
		return nil
	}
	name := s.sock
	if strings.HasPrefix(name, "@") {
		name = "\x00" + name[1:]
	}

	fd, err := syscall.Socket(syscall.AF_UNIX, syscall.SOCK_DGRAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)

	var oob []byte
	if len(fds) > 0 {
		oob = syscall.UnixRights(fds...)
	}
	return syscall.Sendmsg(fd, []byte(state), oob, &syscall.SockaddrUnix{Name: name}, 0)
}

func (s *fdStore) Keep(fd int) string {
	s.mu.Lock()
	s.n++
	name := fmt.Sprintf("gpio-%d-%d", os.Getpid(), s.n)
	s.mu.Unlock()

	if err := s.notify("FDSTORE=1\nFDNAME="+name, fd); err != nil {
		log.Printf("systemd に預けられませんでした: %v", err)
	}
	return name
}

func (s *fdStore) Drop(name string) {
	if name != "" {
		s.notify("FDSTOREREMOVE=1\nFDNAME=" + name)
	}
}

func inheritedFDs() map[int]string {
	out := map[int]string{}
	if os.Getenv("LISTEN_PID") != strconv.Itoa(os.Getpid()) {
		return out
	}

	n, _ := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	names := strings.Split(os.Getenv("LISTEN_FDNAMES"), ":")
	for i := 0; i < n; i++ {
		fd := 3 + i
		syscall.CloseOnExec(fd)
		name := ""
		if i < len(names) {
			name = names[i]
		}
		out[fd] = name
	}

	os.Unsetenv("LISTEN_PID")
	os.Unsetenv("LISTEN_FDS")
	os.Unsetenv("LISTEN_FDNAMES")
	return out
}
