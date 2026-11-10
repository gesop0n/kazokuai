package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

const chipPath = "/dev/gpiochip0"

type sockFilter struct {
	code uint16
	jt   uint8
	jf   uint8
	k    uint32
}

type sockFprog struct {
	len    uint16
	_      [6]byte
	filter *sockFilter
}

const (
	bpfLdWAbs = 0x00 | 0x00 | 0x20
	bpfJeqK   = 0x05 | 0x10 | 0x00
	bpfRetK   = 0x06 | 0x00
)

func buildFilter() []sockFilter {
	n := len(gpioIoctls)
	f := []sockFilter{
		{bpfLdWAbs, 0, 0, seccompDataArchOffset},
		{bpfJeqK, 0, 0, auditArchX86_64},
		{bpfLdWAbs, 0, 0, seccompDataNrOffset},
		{bpfJeqK, 0, 0, sysIoctl},
		{bpfLdWAbs, 0, 0, seccompDataArgsOffset + 8},
	}
	for i, cmd := range gpioIoctls {
		f = append(f, sockFilter{bpfJeqK, uint8(n - i), 0, cmd})
	}
	f = append(f,
		sockFilter{bpfRetK, 0, 0, seccompRetAllow},
		sockFilter{bpfRetK, 0, 0, seccompRetUserNotif},
	)

	allow := len(f) - 2
	f[1].jf = uint8(allow - 2)
	f[3].jf = uint8(allow - 4)
	return f
}

func installFilter() (int, error) {
	f := buildFilter()
	prog := sockFprog{len: uint16(len(f)), filter: &f[0]}
	fd, _, e := syscall.RawSyscall(sysSeccomp, seccompSetModeFilter, seccompFlagNewListener, uintptr(unsafe.Pointer(&prog)))
	if e != 0 {
		return -1, fmt.Errorf("seccomp: %w", e)
	}
	return int(fd), nil
}

type notif struct {
	id   uint64
	pid  int
	nr   int32
	arch uint32
	args [6]uint64
}

var errListenerGone = errors.New("listener gone")

func recvNotif(lfd int) (*notif, error) {
	var buf [sizeSeccompNotif]byte
	for {
		p := pollFd{fd: int32(lfd), events: pollIn}
		_, _, e := syscall.Syscall(syscall.SYS_POLL, uintptr(unsafe.Pointer(&p)), 1, ^uintptr(0))
		if e == syscall.EINTR {
			continue
		}
		if e != 0 {
			return nil, e
		}
		if p.revents&pollIn == 0 {
			if p.revents&pollHup != 0 {
				return nil, errListenerGone
			}
			continue
		}

		_, _, e = syscall.Syscall(syscall.SYS_IOCTL, uintptr(lfd), seccompNotifRecv, uintptr(unsafe.Pointer(&buf[0])))
		if e == syscall.EINTR || e == syscall.ENOENT {
			continue
		}
		if e != 0 {
			return nil, e
		}
		break
	}

	n := &notif{
		id:   le.Uint64(buf[0:]),
		pid:  int(le.Uint32(buf[8:])),
		nr:   int32(le.Uint32(buf[16:])),
		arch: le.Uint32(buf[20:]),
	}
	for i := range n.args {
		n.args[i] = le.Uint64(buf[32+8*i:])
	}
	return n, nil
}

func sendResp(lfd int, id uint64, val int64, errno int, cont bool) {
	var buf [sizeSeccompNotifResp]byte
	le.PutUint64(buf[0:], id)
	le.PutUint64(buf[8:], uint64(val))
	le.PutUint32(buf[16:], uint32(int32(-errno)))
	if cont {
		le.PutUint32(buf[20:], seccompNotifFlagCont)
	}
	syscall.Syscall(syscall.SYS_IOCTL, uintptr(lfd), seccompNotifSend, uintptr(unsafe.Pointer(&buf[0])))
}

func idValid(lfd int, id uint64) bool {
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(lfd), seccompNotifIDValid, uintptr(unsafe.Pointer(&id)))
	return e == 0
}

func addFD(lfd int, id uint64, src int) (int, error) {
	var buf [sizeSeccompNotifAddFD]byte
	le.PutUint64(buf[0:], id)
	le.PutUint32(buf[12:], uint32(src))
	le.PutUint32(buf[20:], oCloexec)
	r, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(lfd), seccompNotifAddFD, uintptr(unsafe.Pointer(&buf[0])))
	if e != 0 {
		return -1, e
	}
	return int(r), nil
}

type iovec struct {
	base uintptr
	len  uint64
}

func readMem(pid int, addr uint64, n int) ([]byte, error) {
	buf := make([]byte, n)
	local := iovec{uintptr(unsafe.Pointer(&buf[0])), uint64(n)}
	remote := iovec{uintptr(addr), uint64(n)}
	r, _, e := syscall.Syscall6(sysProcessVMReadv, uintptr(pid), uintptr(unsafe.Pointer(&local)), 1, uintptr(unsafe.Pointer(&remote)), 1, 0)
	runtime.KeepAlive(buf)
	if e != 0 {
		return nil, e
	}
	if int(r) != n {
		return nil, errors.New("short read")
	}
	return buf, nil
}

func writeMem(pid int, addr uint64, buf []byte) error {
	local := iovec{uintptr(unsafe.Pointer(&buf[0])), uint64(len(buf))}
	remote := iovec{uintptr(addr), uint64(len(buf))}
	r, _, e := syscall.Syscall6(sysProcessVMWritev, uintptr(pid), uintptr(unsafe.Pointer(&local)), 1, uintptr(unsafe.Pointer(&remote)), 1, 0)
	runtime.KeepAlive(buf)
	if e != 0 {
		return e
	}
	if int(r) != len(buf) {
		return errors.New("short write")
	}
	return nil
}

func fdKind(pid, fd int) (isChip bool, pipeIno uint64) {
	target, err := os.Readlink("/proc/" + strconv.Itoa(pid) + "/fd/" + strconv.Itoa(fd))
	if err != nil {
		return false, 0
	}
	if target == chipPath {
		return true, 0
	}
	if rest, ok := strings.CutPrefix(target, "pipe:["); ok {
		if n, err := strconv.ParseUint(strings.TrimSuffix(rest, "]"), 10, 64); err == nil {
			return false, n
		}
	}
	return false, 0
}

type Gpio struct {
	board *Board
}

func (g *Gpio) Serve(lfd int) {
	g.board.addSession(1)
	defer g.board.addSession(-1)
	defer syscall.Close(lfd)

	for {
		n, err := recvNotif(lfd)
		if err != nil {
			return
		}
		g.handle(lfd, n)
	}
}

func (g *Gpio) handle(lfd int, n *notif) {
	if n.nr != sysIoctl {
		sendResp(lfd, n.id, 0, 0, true)
		return
	}

	fd := int(int32(n.args[0]))
	cmd := uint32(n.args[1])
	arg := n.args[2]

	isChip, ino := fdKind(n.pid, fd)
	var req *Request
	if !isChip {
		if ino != 0 {
			req = g.board.requestByIno(ino)
		}
		if req == nil {
			sendResp(lfd, n.id, 0, 0, true)
			return
		}
	}

	errno := func() int {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("ioctl 0x%x の処理で失敗: %v", cmd, r)
			}
		}()
		if isChip {
			return g.chipIoctl(lfd, n, cmd, arg)
		}
		return g.lineIoctl(lfd, n, req, cmd, arg)
	}()
	sendResp(lfd, n.id, 0, errno, false)
}

func (g *Gpio) chipIoctl(lfd int, n *notif, cmd uint32, arg uint64) int {
	switch cmd {
	case gpioGetChipInfo:
		buf := make([]byte, sizeChipInfo)
		copy(buf[0:31], chipName)
		copy(buf[32:63], chipLabel)
		le.PutUint32(buf[64:], numLines)
		return g.write(lfd, n, arg, buf)

	case gpioV2GetLineInfo, gpioV2GetLineInfoWat:
		buf, err := readMem(n.pid, arg, sizeV2LineInfo)
		if err != nil {
			return errnoEFAULT
		}
		if e := g.board.lineInfoV2(int(le.Uint32(buf[64:])), buf); e != 0 {
			return e
		}
		return g.write(lfd, n, arg, buf)

	case gpioV1GetLineInfo, gpioV1GetLineInfoWat:
		buf, err := readMem(n.pid, arg, sizeV1LineInfo)
		if err != nil {
			return errnoEFAULT
		}
		if e := g.board.lineInfoV1(int(le.Uint32(buf[0:])), buf); e != 0 {
			return e
		}
		return g.write(lfd, n, arg, buf)

	case gpioGetLineInfoUnwat:
		return 0

	case gpioV2GetLine:
		buf, err := readMem(n.pid, arg, sizeV2LineReq)
		if err != nil {
			return errnoEFAULT
		}
		num := int(le.Uint32(buf[560:]))
		if num <= 0 || num > maxLinesPerRequest {
			return errnoEINVAL
		}
		offsets := make([]int, num)
		for i := range offsets {
			offsets[i] = int(le.Uint32(buf[4*i:]))
		}
		cfgs, e := parseV2Config(buf[288:288+sizeV2LineConfig], num)
		if e != 0 {
			return e
		}
		return g.open(lfd, n, arg, buf, 588, cstr(buf[256:288]), offsets, cfgs, false, false)

	case gpioV1GetLineHandle:
		buf, err := readMem(n.pid, arg, sizeV1HandleReq)
		if err != nil {
			return errnoEFAULT
		}
		num := int(le.Uint32(buf[356:]))
		if num <= 0 || num > maxLinesPerRequest {
			return errnoEINVAL
		}
		flags := v1ToV2(le.Uint32(buf[256:]))
		offsets := make([]int, num)
		cfgs := make([]lineConfig, num)
		for i := range offsets {
			offsets[i] = int(le.Uint32(buf[4*i:]))
			cfgs[i] = lineConfig{flags: flags, out: int(buf[260+i] & 1), hasOut: flags&v2FlagOutput != 0}
		}
		return g.open(lfd, n, arg, buf, 360, cstr(buf[324:356]), offsets, cfgs, true, false)

	case gpioV1GetLineEvent:
		buf, err := readMem(n.pid, arg, sizeV1EventReq)
		if err != nil {
			return errnoEFAULT
		}
		flags := v1ToV2(le.Uint32(buf[4:]))
		if flags&v2FlagOutput != 0 {
			return errnoEINVAL
		}
		flags |= v2FlagInput
		events := le.Uint32(buf[8:])
		if events&v1EventRequestRising != 0 {
			flags |= v2FlagEdgeRising
		}
		if events&v1EventRequestFalling != 0 {
			flags |= v2FlagEdgeFalling
		}
		offsets := []int{int(le.Uint32(buf[0:]))}
		return g.open(lfd, n, arg, buf, 44, cstr(buf[12:44]), offsets, []lineConfig{{flags: flags}}, true, true)
	}
	return errnoENOTTY
}

func (g *Gpio) lineIoctl(lfd int, n *notif, r *Request, cmd uint32, arg uint64) int {
	switch cmd {
	case gpioV2LineGetValues:
		if r.v1 {
			return errnoENOTTY
		}
		buf, err := readMem(n.pid, arg, sizeV2Values)
		if err != nil {
			return errnoEFAULT
		}
		le.PutUint64(buf[0:], g.board.getValues(r, le.Uint64(buf[8:])))
		return g.write(lfd, n, arg, buf)

	case gpioV2LineSetValues:
		if r.v1 {
			return errnoENOTTY
		}
		buf, err := readMem(n.pid, arg, sizeV2Values)
		if err != nil {
			return errnoEFAULT
		}
		if !idValid(lfd, n.id) {
			return errnoENOENT
		}
		return g.board.setValues(r, le.Uint64(buf[8:]), le.Uint64(buf[0:]))

	case gpioV2LineSetConfig:
		if r.v1 {
			return errnoENOTTY
		}
		buf, err := readMem(n.pid, arg, sizeV2LineConfig)
		if err != nil {
			return errnoEFAULT
		}
		cfgs, e := parseV2Config(buf, len(r.offsets))
		if e != 0 {
			return e
		}
		return g.board.reconfigure(r, cfgs)

	case gpioV1HandleGetValues:
		if !r.v1 {
			return errnoENOTTY
		}
		bits := g.board.getValues(r, ^uint64(0))
		buf := make([]byte, sizeV1HandleData)
		for i := range r.offsets {
			buf[i] = byte(bits >> uint(i) & 1)
		}
		return g.write(lfd, n, arg, buf)

	case gpioV1HandleSetValues:
		if !r.v1 || r.v1Event {
			return errnoENOTTY
		}
		buf, err := readMem(n.pid, arg, sizeV1HandleData)
		if err != nil {
			return errnoEFAULT
		}
		var bits uint64
		for i := range r.offsets {
			if buf[i] != 0 {
				bits |= 1 << uint(i)
			}
		}
		mask := uint64(1)<<uint(len(r.offsets)) - 1
		return g.board.setValues(r, mask, bits)

	case gpioV1HandleSetConfig:
		if !r.v1 || r.v1Event {
			return errnoENOTTY
		}
		buf, err := readMem(n.pid, arg, sizeV1HandleConf)
		if err != nil {
			return errnoEFAULT
		}
		flags := v1ToV2(le.Uint32(buf[0:]))
		cfgs := make([]lineConfig, len(r.offsets))
		for i := range cfgs {
			cfgs[i] = lineConfig{flags: flags, out: int(buf[4+i] & 1), hasOut: flags&v2FlagOutput != 0}
		}
		return g.board.reconfigure(r, cfgs)
	}
	return errnoENOTTY
}

func (g *Gpio) open(lfd int, n *notif, arg uint64, buf []byte, fdOff int, consumer string, offsets []int, cfgs []lineConfig, v1, v1Event bool) int {
	if !idValid(lfd, n.id) {
		return errnoENOENT
	}

	r, rfd, e := g.board.openRequest(n.pid, consumer, offsets, cfgs, v1, v1Event)
	if e != 0 {
		return e
	}

	tfd, err := addFD(lfd, n.id, rfd)
	syscall.Close(rfd)
	if err != nil {
		g.board.mu.Lock()
		g.board.releaseLocked(r)
		delete(g.board.requests, r.ino)
		g.board.mu.Unlock()
		return errnoENOMEM
	}

	le.PutUint32(buf[fdOff:], uint32(int32(tfd)))
	if err := writeMem(n.pid, arg, buf); err != nil {
		return errnoEFAULT
	}
	return 0
}

func (g *Gpio) write(lfd int, n *notif, arg uint64, buf []byte) int {
	if !idValid(lfd, n.id) {
		return errnoENOENT
	}
	if err := writeMem(n.pid, arg, buf); err != nil {
		return errnoEFAULT
	}
	return 0
}

func parseV2Config(buf []byte, num int) ([]lineConfig, int) {
	flags := le.Uint64(buf[0:])
	numAttrs := int(le.Uint32(buf[8:]))
	if numAttrs > 10 {
		return nil, errnoEINVAL
	}

	cfgs := make([]lineConfig, num)
	for i := range cfgs {
		bit := uint64(1) << uint(i)
		c := lineConfig{flags: flags}
		gotFlags, gotOut, gotDebounce := false, false, false

		for a := 0; a < numAttrs; a++ {
			attr := buf[32+24*a:]
			id := le.Uint32(attr[0:])
			val := le.Uint64(attr[8:])
			mask := le.Uint64(attr[16:])
			if mask&bit == 0 {
				continue
			}
			switch id {
			case v2AttrFlags:
				if !gotFlags {
					c.flags = val
					gotFlags = true
				}
			case v2AttrOutputValues:
				if !gotOut {
					c.out = int(val >> uint(i) & 1)
					c.hasOut = true
					gotOut = true
				}
			case v2AttrDebounce:
				if !gotDebounce {
					c.debounceUs = uint32(val)
					gotDebounce = true
				}
			default:
				return nil, errnoEINVAL
			}
		}

		if c.flags&v2FlagOutput != 0 {
			c.hasOut = true
		}
		cfgs[i] = c
	}
	return cfgs, 0
}

func v1ToV2(f uint32) uint64 {
	var o uint64
	for _, m := range []struct {
		v1 uint32
		v2 uint64
	}{
		{v1ReqInput, v2FlagInput},
		{v1ReqOutput, v2FlagOutput},
		{v1ReqActiveLow, v2FlagActiveLow},
		{v1ReqOpenDrain, v2FlagOpenDrain},
		{v1ReqOpenSource, v2FlagOpenSource},
		{v1ReqPullUp, v2FlagPullUp},
		{v1ReqPullDown, v2FlagPullDown},
		{v1ReqBiasDisable, v2FlagBiasDisable},
	} {
		if f&m.v1 != 0 {
			o |= m.v2
		}
	}
	return o
}

func cstr(b []byte) string {
	for i, c := range b {
		if c == 0 {
			return string(b[:i])
		}
	}
	return string(b)
}
