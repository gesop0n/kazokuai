package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	numLines  = 58
	chipName  = "gpiochip0"
	chipLabel = "pinctrl-bcm2711"
)

const (
	dirIn = iota
	dirOut
)

const (
	pullNone = iota
	pullUp
	pullDown
)

const (
	drivePushPull = iota
	driveOpenDrain
	driveOpenSource
)

var bcm2711Names = [numLines]string{
	"ID_SDA", "ID_SCL", "GPIO2", "GPIO3", "GPIO4", "GPIO5", "GPIO6", "GPIO7",
	"GPIO8", "GPIO9", "GPIO10", "GPIO11", "GPIO12", "GPIO13", "GPIO14", "GPIO15",
	"GPIO16", "GPIO17", "GPIO18", "GPIO19", "GPIO20", "GPIO21", "GPIO22", "GPIO23",
	"GPIO24", "GPIO25", "GPIO26", "GPIO27", "RGMII_MDIO", "RGMIO_MDC", "CTS0", "RTS0",
	"TXD0", "RXD0", "SD1_CLK", "SD1_CMD", "SD1_DATA0", "SD1_DATA1", "SD1_DATA2", "SD1_DATA3",
	"PWM0_MISO", "PWM1_MOSI", "STATUS_LED_G_CLK", "SPIFLASH_CE_N", "SDA0", "SCL0", "RGMII_RXCLK", "RGMII_RXCTL",
	"RGMII_RXD0", "RGMII_RXD1", "RGMII_RXD2", "RGMII_RXD3", "RGMII_TXCLK", "RGMII_TXCTL", "RGMII_TXD0", "RGMII_TXD1",
	"RGMII_TXD2", "RGMII_TXD3",
}

type Line struct {
	offset int
	dir    int
	out    int
	drive  int
	pull   int
	level  int
	owner  *Request
	idx    int
}

type Request struct {
	id       int
	ino      uint64
	wfd      int
	v1       bool
	v1Event  bool
	pid      int
	comm     string
	consumer string
	offsets  []int
	flags    []uint64
	debounce []time.Duration
	deb      []int
	timers   []*time.Timer
	seq      uint32
	lineSeq  []uint32
	dead     bool
}

type Board struct {
	mu       sync.Mutex
	cfg      Config
	lines    [numLines]*Line
	requests map[uint64]*Request
	nextID   int

	hookLifted bool
	keysDown   map[byte]bool

	audio    *Audio
	sessions int
	changed  chan struct{}
	onHook   func(lifted bool)
}

func NewBoard(cfg Config, audio *Audio) *Board {
	b := &Board{
		cfg:      cfg,
		requests: map[uint64]*Request{},
		keysDown: map[byte]bool{},
		audio:    audio,
		changed:  make(chan struct{}, 1),
	}
	for i := range b.lines {
		l := &Line{offset: i, dir: dirIn}
		switch {
		case i <= 8:
			l.pull = pullUp
			l.level = 1
		case i <= 27:
			l.pull = pullDown
		}
		b.lines[i] = l
	}
	b.recomputeLocked(monoNow())
	return b
}

func (b *Board) notify() {
	select {
	case b.changed <- struct{}{}:
	default:
	}
}

func (b *Board) SetHook(lifted bool) {
	b.mu.Lock()
	if b.hookLifted == lifted {
		b.mu.Unlock()
		return
	}
	b.hookLifted = lifted
	b.recomputeLocked(monoNow())
	onHook := b.onHook
	b.mu.Unlock()

	b.notify()
	if onHook != nil {
		onHook(lifted)
	}
}

func (b *Board) HookLifted() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.hookLifted
}

func (b *Board) SetKey(k byte, down bool) {
	if _, _, ok := b.cfg.keyPos(k); !ok {
		return
	}

	b.mu.Lock()
	if b.keysDown[k] == down {
		b.mu.Unlock()
		return
	}
	if down {
		b.keysDown[k] = true
	} else {
		delete(b.keysDown, k)
	}
	b.recomputeLocked(monoNow())
	b.mu.Unlock()

	b.notify()
}

func (b *Board) hookClosed() bool {
	return b.hookLifted == b.cfg.LiftedWhenClosed
}

type netGroup struct{ low, high, pullUp, pullDown bool }

func (b *Board) recomputeLocked(now int64) {
	const gnd = numLines

	parent := make([]int, numLines+1)
	for i := range parent {
		parent[i] = i
	}
	find := func(x int) int {
		for parent[x] != x {
			parent[x] = parent[parent[x]]
			x = parent[x]
		}
		return x
	}
	connect := func(a, c int) {
		if a < 0 || c < 0 || a > numLines || c > numLines {
			return
		}
		parent[find(a)] = find(c)
	}

	if b.hookClosed() {
		connect(b.cfg.HookGPIO, gnd)
	}
	for k := range b.keysDown {
		if r, c, ok := b.cfg.keyPos(k); ok {
			connect(b.cfg.Rows[r], b.cfg.Cols[c])
		}
	}

	groups := map[int]*netGroup{}
	groupOf := func(x int) *netGroup {
		root := find(x)
		g := groups[root]
		if g == nil {
			g = &netGroup{}
			groups[root] = g
		}
		return g
	}

	groupOf(gnd).low = true
	for _, l := range b.lines {
		g := groupOf(l.offset)
		if l.dir == dirOut {
			switch l.drive {
			case drivePushPull:
				if l.out == 0 {
					g.low = true
				} else {
					g.high = true
				}
			case driveOpenDrain:
				if l.out == 0 {
					g.low = true
				}
			case driveOpenSource:
				if l.out == 1 {
					g.high = true
				}
			}
		}
		switch l.pull {
		case pullUp:
			g.pullUp = true
		case pullDown:
			g.pullDown = true
		}
	}

	for _, l := range b.lines {
		g := groupOf(l.offset)
		level := l.level
		switch {
		case g.low:
			level = 0
		case g.high:
			level = 1
		case g.pullUp && !g.pullDown:
			level = 1
		case g.pullDown:
			level = 0
		}
		if level != l.level {
			l.level = level
			b.levelChangedLocked(l, now)
		}
	}
}

func (b *Board) levelChangedLocked(l *Line, now int64) {
	if l.offset == b.cfg.RingerGPIO && b.audio != nil {
		b.audio.Edge(now, l.level)
	}
	if r := l.owner; r != nil && l.dir == dirIn {
		b.physChangedLocked(r, l.idx)
	}
	b.notify()
}

func (b *Board) physChangedLocked(r *Request, i int) {
	l := b.lines[r.offsets[i]]
	if r.debounce[i] <= 0 {
		b.setDebouncedLocked(r, i, l.level)
		return
	}

	if r.timers[i] != nil {
		r.timers[i].Stop()
	}
	r.timers[i] = time.AfterFunc(r.debounce[i], func() {
		b.mu.Lock()
		defer b.mu.Unlock()
		if !r.dead {
			b.setDebouncedLocked(r, i, b.lines[r.offsets[i]].level)
		}
	})
}

func (b *Board) setDebouncedLocked(r *Request, i int, level int) {
	if r.deb[i] == level {
		return
	}
	r.deb[i] = level

	flags := r.flags[i]
	logical := level
	if flags&v2FlagActiveLow != 0 {
		logical ^= 1
	}

	id := uint32(v2EventFalling)
	wanted := flags&v2FlagEdgeFalling != 0
	if logical == 1 {
		id = v2EventRising
		wanted = flags&v2FlagEdgeRising != 0
	}
	if !wanted {
		return
	}

	clock := clockMonotonic
	if flags&v2FlagClockRT != 0 {
		clock = clockRealtime
	}
	ts := clockNs(clock)
	r.seq++
	r.lineSeq[i]++

	var buf []byte
	if r.v1 {
		buf = make([]byte, sizeV1EventData)
		le.PutUint64(buf[0:], uint64(ts))
		le.PutUint32(buf[8:], id)
	} else {
		buf = make([]byte, sizeV2Event)
		le.PutUint64(buf[0:], uint64(ts))
		le.PutUint32(buf[8:], id)
		le.PutUint32(buf[12:], uint32(r.offsets[i]))
		le.PutUint32(buf[16:], r.seq)
		le.PutUint32(buf[20:], r.lineSeq[i])
	}
	syscall.Write(r.wfd, buf)
}

func (b *Board) reapLocked() {
	for ino, r := range b.requests {
		if !pipeHasReader(r.wfd) {
			b.releaseLocked(r)
			delete(b.requests, ino)
		}
	}
}

func (b *Board) releaseLocked(r *Request) {
	if r.dead {
		return
	}
	r.dead = true
	for i, off := range r.offsets {
		if r.timers[i] != nil {
			r.timers[i].Stop()
		}
		if l := b.lines[off]; l.owner == r {
			l.owner = nil
		}
	}
	syscall.Close(r.wfd)
	b.notify()
}

type lineConfig struct {
	flags      uint64
	out        int
	hasOut     bool
	debounceUs uint32
}

func validFlags(f uint64) bool {
	has := func(mask uint64) bool { return f&mask != 0 }

	if has(v2FlagInput) && has(v2FlagOutput) {
		return false
	}
	if has(v2FlagEdgeRising|v2FlagEdgeFalling) && !has(v2FlagInput) {
		return false
	}
	if has(v2FlagOpenDrain|v2FlagOpenSource) && !has(v2FlagOutput) {
		return false
	}
	if has(v2FlagOpenDrain) && has(v2FlagOpenSource) {
		return false
	}

	bias := 0
	for _, x := range []uint64{v2FlagPullUp, v2FlagPullDown, v2FlagBiasDisable} {
		if has(x) {
			bias++
		}
	}
	if bias > 1 {
		return false
	}
	if bias == 1 && !has(v2FlagInput|v2FlagOutput) {
		return false
	}

	return !(has(v2FlagClockRT) && has(v2FlagClockHTE))
}

func (b *Board) applyLocked(r *Request, i int, c lineConfig) {
	l := b.lines[r.offsets[i]]
	r.flags[i] = c.flags
	r.debounce[i] = time.Duration(c.debounceUs) * time.Microsecond

	f := c.flags
	switch {
	case f&v2FlagOutput != 0:
		l.dir = dirOut
		switch {
		case f&v2FlagOpenDrain != 0:
			l.drive = driveOpenDrain
		case f&v2FlagOpenSource != 0:
			l.drive = driveOpenSource
		default:
			l.drive = drivePushPull
		}
		if c.hasOut {
			v := c.out
			if f&v2FlagActiveLow != 0 {
				v ^= 1
			}
			l.out = v
		}
	case f&v2FlagInput != 0:
		l.dir = dirIn
	}

	switch {
	case f&v2FlagPullUp != 0:
		l.pull = pullUp
	case f&v2FlagPullDown != 0:
		l.pull = pullDown
	case f&v2FlagBiasDisable != 0:
		l.pull = pullNone
	}
}

func (b *Board) openRequest(pid int, consumer string, offsets []int, cfgs []lineConfig, v1, v1Event bool) (*Request, int, int) {
	if len(offsets) == 0 || len(offsets) > maxLinesPerRequest {
		return nil, -1, errnoEINVAL
	}
	seen := map[int]bool{}
	for i, off := range offsets {
		if off < 0 || off >= numLines || seen[off] || !validFlags(cfgs[i].flags) {
			return nil, -1, errnoEINVAL
		}
		seen[off] = true
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	for _, off := range offsets {
		if b.lines[off].owner != nil {
			b.reapLocked()
			break
		}
	}
	for _, off := range offsets {
		if b.lines[off].owner != nil {
			return nil, -1, errnoEBUSY
		}
	}

	var p [2]int
	if err := syscall.Pipe2(p[:], syscall.O_CLOEXEC); err != nil {
		return nil, -1, errnoENOMEM
	}
	syscall.SetNonblock(p[1], true)
	var st syscall.Stat_t
	syscall.Fstat(p[1], &st)

	b.nextID++
	n := len(offsets)
	r := &Request{
		id:       b.nextID,
		ino:      st.Ino,
		wfd:      p[1],
		v1:       v1,
		v1Event:  v1Event,
		pid:      pid,
		comm:     procComm(pid),
		consumer: consumer,
		offsets:  offsets,
		flags:    make([]uint64, n),
		debounce: make([]time.Duration, n),
		deb:      make([]int, n),
		timers:   make([]*time.Timer, n),
		lineSeq:  make([]uint32, n),
	}
	for i, off := range offsets {
		l := b.lines[off]
		l.owner = r
		l.idx = i
		b.applyLocked(r, i, cfgs[i])
	}
	b.recomputeLocked(monoNow())
	for i, off := range offsets {
		r.deb[i] = b.lines[off].level
	}
	b.requests[r.ino] = r
	b.notify()
	return r, p[0], 0
}

func (b *Board) reconfigure(r *Request, cfgs []lineConfig) int {
	for _, c := range cfgs {
		if !validFlags(c.flags) {
			return errnoEINVAL
		}
	}

	b.mu.Lock()
	defer b.mu.Unlock()
	if r.dead {
		return errnoEBADF
	}
	for i := range r.offsets {
		if r.timers[i] != nil {
			r.timers[i].Stop()
		}
		b.applyLocked(r, i, cfgs[i])
	}
	b.recomputeLocked(monoNow())
	for i, off := range r.offsets {
		r.deb[i] = b.lines[off].level
	}
	b.notify()
	return 0
}

func (b *Board) getValues(r *Request, mask uint64) uint64 {
	b.mu.Lock()
	defer b.mu.Unlock()

	var bits uint64
	for i, off := range r.offsets {
		if mask&(1<<uint(i)) == 0 {
			continue
		}
		l := b.lines[off]
		v := r.deb[i]
		if l.dir == dirOut {
			v = l.out
		}
		if r.flags[i]&v2FlagActiveLow != 0 {
			v ^= 1
		}
		if v == 1 {
			bits |= 1 << uint(i)
		}
	}
	return bits
}

func (b *Board) setValues(r *Request, mask, bits uint64) int {
	b.mu.Lock()
	defer b.mu.Unlock()

	for i, off := range r.offsets {
		if mask&(1<<uint(i)) != 0 && b.lines[off].dir != dirOut {
			return errnoEPERM
		}
	}
	for i, off := range r.offsets {
		if mask&(1<<uint(i)) == 0 {
			continue
		}
		v := int(bits >> uint(i) & 1)
		if r.flags[i]&v2FlagActiveLow != 0 {
			v ^= 1
		}
		b.lines[off].out = v
	}
	b.recomputeLocked(monoNow())
	return 0
}

func (b *Board) lineInfoV2(off int, buf []byte) int {
	if off < 0 || off >= numLines {
		return errnoEINVAL
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	clear(buf)
	l := b.lines[off]
	copy(buf[0:31], bcm2711Names[off])
	le.PutUint32(buf[64:], uint32(off))

	direction := uint64(v2FlagInput)
	if l.dir == dirOut {
		direction = v2FlagOutput
	}
	flags := direction

	if r := l.owner; r != nil {
		copy(buf[32:63], r.consumer)
		flags = r.flags[l.idx] | v2FlagUsed
		if flags&(v2FlagInput|v2FlagOutput) == 0 {
			flags |= direction
		}
		if d := r.debounce[l.idx]; d > 0 {
			le.PutUint32(buf[68:], 1)
			le.PutUint32(buf[80:], v2AttrDebounce)
			le.PutUint32(buf[88:], uint32(d/time.Microsecond))
		}
	}
	le.PutUint64(buf[72:], flags)
	return 0
}

func (b *Board) lineInfoV1(off int, buf []byte) int {
	if off < 0 || off >= numLines {
		return errnoEINVAL
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	clear(buf)
	l := b.lines[off]
	le.PutUint32(buf[0:], uint32(off))

	var flags uint32
	if l.dir == dirOut {
		flags |= v1InfoIsOut
	}
	if r := l.owner; r != nil {
		flags |= v1InfoKernel
		f := r.flags[l.idx]
		for _, m := range []struct {
			v2 uint64
			v1 uint32
		}{
			{v2FlagActiveLow, v1InfoActiveLow},
			{v2FlagOpenDrain, v1InfoOpenDrain},
			{v2FlagOpenSource, v1InfoOpenSource},
			{v2FlagPullUp, v1InfoPullUp},
			{v2FlagPullDown, v1InfoPullDown},
			{v2FlagBiasDisable, v1InfoBiasDisable},
		} {
			if f&m.v2 != 0 {
				flags |= m.v1
			}
		}
		copy(buf[40:71], r.consumer)
	}
	le.PutUint32(buf[4:], flags)
	copy(buf[8:39], bcm2711Names[off])
	return 0
}

func (b *Board) requestByIno(ino uint64) *Request {
	b.mu.Lock()
	defer b.mu.Unlock()
	r := b.requests[ino]
	if r == nil || r.dead {
		return nil
	}
	return r
}

func (b *Board) addSession(delta int) {
	b.mu.Lock()
	b.sessions += delta
	b.mu.Unlock()
	b.notify()
}

type LineView struct {
	GPIO  int    `json:"gpio"`
	Role  string `json:"role"`
	Dir   string `json:"dir"`
	Level int    `json:"level"`
	Pull  string `json:"pull"`
	Owner string `json:"owner"`
}

type StateView struct {
	T        string     `json:"t"`
	HookUp   bool       `json:"hook_up"`
	Keys     string     `json:"keys"`
	Lines    []LineView `json:"lines"`
	Ringer   RingerView `json:"ringer"`
	Sessions int        `json:"sessions"`
	Audio    string     `json:"audio"`
	Config   string     `json:"config"`
	Network  string     `json:"network"`
}

func (b *Board) Snapshot() StateView {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.reapLocked()

	var keys []string
	for k := range b.keysDown {
		keys = append(keys, string(k))
	}
	sort.Strings(keys)

	s := StateView{T: "state", HookUp: b.hookLifted, Keys: strings.Join(keys, ""), Sessions: b.sessions}

	add := func(gpio int, role string) {
		if gpio < 0 || gpio >= numLines {
			return
		}
		l := b.lines[gpio]
		v := LineView{GPIO: gpio, Role: role, Level: l.level, Dir: "入力"}
		if l.dir == dirOut {
			v.Dir = "出力"
		}
		v.Pull = [...]string{"なし", "上", "下"}[l.pull]
		if r := l.owner; r != nil {
			v.Owner = fmt.Sprintf("%s[%d]", r.comm, r.pid)
		}
		s.Lines = append(s.Lines, v)
	}
	add(b.cfg.HookGPIO, "フック")
	for i, g := range b.cfg.Rows {
		add(g, fmt.Sprintf("キー行 R%d", i+1))
	}
	for i, g := range b.cfg.Cols {
		add(g, fmt.Sprintf("キー列 C%d", i+1))
	}
	add(b.cfg.RingerGPIO, "本体スピーカー")

	if b.audio != nil {
		s.Ringer = b.audio.View()
		s.Audio = b.audio.Status()
	}
	s.Config = b.cfg.Summary()
	return s
}

var monoBase = time.Now()

func monoNow() int64 { return int64(time.Since(monoBase)) }

func clockNs(clock int) int64 {
	var ts syscall.Timespec
	syscall.Syscall(sysClockGettime, uintptr(clock), uintptr(unsafe.Pointer(&ts)), 0)
	return ts.Nano()
}

func procComm(pid int) string {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/comm", pid))
	if err != nil {
		return "?"
	}
	return strings.TrimSpace(string(b))
}

type pollFd struct {
	fd      int32
	events  int16
	revents int16
}

const (
	pollIn  = 0x1
	pollOut = 0x4
	pollErr = 0x8
	pollHup = 0x10
)

func pipeHasReader(w int) bool {
	p := pollFd{fd: int32(w), events: pollOut}
	syscall.Syscall(syscall.SYS_POLL, uintptr(unsafe.Pointer(&p)), 1, 0)
	return p.revents&pollErr == 0
}
