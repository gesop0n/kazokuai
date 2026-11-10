package main

import (
	"errors"
	"fmt"
	"os"
	"syscall"
)

const (
	netlinkGeneric     = 16
	genlIDCtrl         = 0x10
	ctrlCmdGetFamily   = 3
	ctrlAttrFamilyID   = 1
	ctrlAttrFamilyName = 2
	hwsimCmdNewRadio   = 4
	hwsimCmdDelRadio   = 5
	hwsimAttrRadioName = 17
	nlmFRequest        = 0x1
	nlmFAck            = 0x4
	nlmsgError         = 0x2
	hwsimFamilyName    = "MAC80211_HWSIM"
	hwsimRadioPi       = "kazokuai-pi"
	hwsimRadioAP       = "kazokuai-ap"
)

type genl struct {
	fd  int
	seq uint32
}

func openGenl() (*genl, error) {
	fd, err := syscall.Socket(syscall.AF_NETLINK, syscall.SOCK_RAW|syscall.SOCK_CLOEXEC, netlinkGeneric)
	if err != nil {
		return nil, err
	}
	if err := syscall.Bind(fd, &syscall.SockaddrNetlink{Family: syscall.AF_NETLINK}); err != nil {
		syscall.Close(fd)
		return nil, err
	}
	return &genl{fd: fd}, nil
}

func (g *genl) close() { syscall.Close(g.fd) }

func nlattr(typ uint16, data []byte) []byte {
	l := 4 + len(data)
	b := make([]byte, (l+3)&^3)
	le.PutUint16(b[0:], uint16(l))
	le.PutUint16(b[2:], typ)
	copy(b[4:], data)
	return b
}

func nlstring(typ uint16, s string) []byte {
	return nlattr(typ, append([]byte(s), 0))
}

func (g *genl) request(family uint16, cmd, version uint8, attrs ...[]byte) ([]byte, error) {
	g.seq++
	body := []byte{cmd, version, 0, 0}
	for _, a := range attrs {
		body = append(body, a...)
	}
	msg := make([]byte, 16+len(body))
	le.PutUint32(msg[0:], uint32(len(msg)))
	le.PutUint16(msg[4:], family)
	le.PutUint16(msg[6:], nlmFRequest|nlmFAck)
	le.PutUint32(msg[8:], g.seq)
	copy(msg[16:], body)
	if err := syscall.Sendto(g.fd, msg, 0, &syscall.SockaddrNetlink{Family: syscall.AF_NETLINK}); err != nil {
		return nil, err
	}

	var reply []byte
	buf := make([]byte, 65536)
	for {
		n, _, err := syscall.Recvfrom(g.fd, buf, 0)
		if err != nil {
			return nil, err
		}
		for off := 0; off+16 <= n; {
			l := int(le.Uint32(buf[off:]))
			if l < 16 || off+l > n {
				break
			}
			typ := le.Uint16(buf[off+4:])
			seq := le.Uint32(buf[off+8:])
			if seq == g.seq {
				if typ == nlmsgError {
					if e := int32(le.Uint32(buf[off+16:])); e < 0 {
						return reply, syscall.Errno(-e)
					}
					return reply, nil
				}
				reply = append([]byte(nil), buf[off+16:off+l]...)
			}
			off += (l + 3) &^ 3
		}
	}
}

func (g *genl) familyID(name string) (uint16, error) {
	reply, err := g.request(genlIDCtrl, ctrlCmdGetFamily, 1, nlstring(ctrlAttrFamilyName, name))
	if err != nil {
		return 0, err
	}
	for off := 4; off+4 <= len(reply); {
		l := int(le.Uint16(reply[off:]))
		typ := le.Uint16(reply[off+2:])
		if l < 4 {
			break
		}
		if typ == ctrlAttrFamilyID && l >= 6 {
			return le.Uint16(reply[off+4:]), nil
		}
		off += (l + 3) &^ 3
	}
	return 0, errors.New("generic netlink の番号が見つかりません")
}

func hwsimRadio(name string) error {
	g, err := openGenl()
	if err != nil {
		return err
	}
	defer g.close()

	family, err := g.familyID(hwsimFamilyName)
	if err != nil {
		return fmt.Errorf("mac80211_hwsim の netlink: %w", err)
	}
	g.request(family, hwsimCmdDelRadio, 2, nlstring(hwsimAttrRadioName, name))
	if _, err := g.request(family, hwsimCmdNewRadio, 2, nlstring(hwsimAttrRadioName, name)); err != nil {
		return fmt.Errorf("無線 %s を作れません: %w", name, err)
	}
	return nil
}

func hwsimRadioIface(name string) string {
	ents, _ := os.ReadDir("/sys/class/ieee80211/" + name + "/device/net")
	for _, e := range ents {
		if e.Name() != "hwsim0" {
			return e.Name()
		}
	}
	return ""
}
