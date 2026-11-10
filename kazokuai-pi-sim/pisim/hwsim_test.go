package main

import "testing"

func TestGenlFamilyID(t *testing.T) {
	g, err := openGenl()
	if err != nil {
		t.Skip(err)
	}
	defer g.close()
	id, err := g.familyID("nlctrl")
	if err != nil || id != genlIDCtrl {
		t.Fatalf("nlctrl = %#x, %v; want 0x10", id, err)
	}
	if _, err := g.familyID("NO_SUCH_FAMILY"); err == nil {
		t.Fatal("無い family で失敗しなかった")
	}
}

func TestBuildFilterJumps(t *testing.T) {
	f := buildFilter()
	if f[len(f)-2].k != seccompRetAllow || f[len(f)-1].k != seccompRetUserNotif {
		t.Fatal("最後が ALLOW, USER_NOTIF でない")
	}
	if int(f[1].jf)+2 != len(f)-2 || int(f[3].jf)+4 != len(f)-2 {
		t.Fatal("ALLOW への飛び先が違う")
	}
}
