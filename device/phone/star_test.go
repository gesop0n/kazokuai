package phone_test

import (
	"strings"
	"testing"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/device/spoken"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestStarWithTheHandsetUpStartsTalkingWithoutRinging(t *testing.T) {
	r := newCodeRig(t, starOK)
	r.lift()
	r.press("*")

	waitUntil(t, "会話が始まらなかった", r.phone.micOpen)
	if r.phone.isRinging() || r.phone.ringCount() != 0 {
		t.Fatal("呼び出し音を鳴らした")
	}
	if !r.phone.isLit() {
		t.Fatal("ランプが点かなかった")
	}
	session := r.gemini.waitForSession(t, 1)
	waitUntil(t, "始まりの合図を送らなかった", func() bool {
		return sessionHas(session, protocol.StartCue)
	})
	if got := r.backend.askedCall(); got != "call-from-star" {
		t.Fatalf("トークンの電話 = %q, want call-from-star", got)
	}
	if got := r.backend.startCount(); got != 1 {
		t.Fatalf("電話を頼んだ回数 = %d, want 1", got)
	}
}

func TestStarWhileDownDuringACallAndWhileSpeakingDoesNothing(t *testing.T) {
	t.Run("受話器が置かれている", func(t *testing.T) {
		r := newCodeRig(t, starOK)
		r.press("*")
		r.quiet()
		if got := r.backend.startCount(); got != 0 {
			t.Fatalf("電話を頼んだ回数 = %d, want 0", got)
		}
		if r.phone.micOpen() || r.phone.ringCount() != 0 {
			t.Fatal("置いた受話器で会話を始めた")
		}
	})

	t.Run("電話の最中", func(t *testing.T) {
		r := newCodeRig(t, starOK)
		r.send(protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: "call-1"})
		waitUntil(t, "呼び出し音が鳴らなかった", r.phone.isRinging)
		r.press("*")
		r.quiet()
		if got := r.backend.startCount(); got != 0 {
			t.Fatalf("電話の最中に電話を頼んだ: %d", got)
		}
		if !r.phone.isRinging() || r.phone.micOpen() {
			t.Fatal("電話の最中の「＊」で進み方が変わった")
		}
	})

	t.Run("認証コードを話している", func(t *testing.T) {
		r := newCodeRig(t, codeOK)
		r.lift()
		r.press("#")
		r.waitAudio(codePCM(t))
		before := r.phone.hushCount()
		r.press("*")
		r.quiet()
		if r.phone.hushCount() != before {
			t.Fatal("認証コードを話しているあいだに音声を止めた")
		}
		if got := r.backend.startCount(); got != 0 {
			t.Fatalf("認証コードを話しているあいだに電話を頼んだ: %d", got)
		}
		if r.phone.micOpen() || r.phone.ringCount() != 0 {
			t.Fatal("認証コードを話しているあいだに会話を始めた")
		}
	})
}

func TestRefusedStarPlaysTheFailedSentence(t *testing.T) {
	r := newCodeRig(t, starRefuse)
	r.lift()
	r.press("*")
	r.waitAudio(spoken.Failed())
	r.wantText(failedSentence + "\n")
	if r.phone.micOpen() || r.phone.ringCount() != 0 {
		t.Fatal("断られたのに会話を始めた")
	}
}

func TestUnreachableStarPlaysTheOfflineSentence(t *testing.T) {
	r := newCodeRig(t, starOffline)
	r.lift()
	r.press("*")
	r.waitAudio(spoken.Offline())
	r.wantText(offlineSentence + "\n")
	if r.phone.micOpen() || r.phone.ringCount() != 0 {
		t.Fatal("届かないのに会話を始めた")
	}
}

func sessionHas(s *fakeSession, want string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, item := range s.clientSent {
		in, ok := item.(genai.LiveClientContentInput)
		if !ok {
			continue
		}
		for _, turn := range in.Turns {
			for _, part := range turn.Parts {
				if part != nil && strings.Contains(part.Text, want) {
					return true
				}
			}
		}
	}
	return false
}
