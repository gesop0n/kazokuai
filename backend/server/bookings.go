package server

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/api/idtoken"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	// bookingsCollection は、見守る方の下に予約を置くサブコレクションである。
	bookingsCollection = "bookings"
	// bookingMinLead は、予約が今よりどれだけ先でなければならないかである。
	bookingMinLead = time.Minute
	// bookingHorizon は、予約が今からどれだけ先までかである。
	// Cloud Tasks は 30 日より先のタスクを作れない。
	bookingHorizon = 30 * 24 * time.Hour
	// bookingGap は、同じ見守る方の予約のあいだに空ける時間である。この時間以内には置けない。
	bookingGap = 10 * time.Minute
	// bookingGiveUp は、予約の時刻から、つながらなかったにするまでの時間である。
	bookingGiveUp = 10 * time.Minute
	// bookingRetryEvery は、電話機がつながっていないときや電話の最中に、やり直すまでの時間である。
	bookingRetryEvery = time.Minute
	// maxBookingBody は、予約の頼みの本文の上限である。伝えたいことと通話内容には十分に大きい。
	maxBookingBody = 16 << 10
)

// booking は、Firestore の予約のドキュメントである。
type booking struct {
	At      time.Time `firestore:"at"`
	Message string    `firestore:"message"`
	Script  string    `firestore:"script"`
	Number  int64     `firestore:"number"`
	Called  bool      `firestore:"called"`
	CallID  string    `firestore:"callId"`
}

// savedBooking は、保存した予約の ID を返すレスポンスである。
type savedBooking struct {
	ID string `json:"id"`
}

var (
	errBookingTooSoon  = errors.New("早すぎる")
	errBookingTooFar   = errors.New("先すぎる")
	errBookingTooClose = errors.New("近くに別の予約がある")
	errBookingNotFound = errors.New("予約が見つからない")
	errBookingCalled   = errors.New("かけたあと")
	// errBookingStale は、タスクの番号が今の番号と違うか、もうかけたあとである。電話はかけない。
	errBookingStale = errors.New("予約の番号が違うか、もうかけた")
)

// bookingSchedule は、予約の ID と番号で、その時刻に電話を予定へ入れる。
// 予約の ID は見守る方の下で一意なので、見守る方の ID も受け取る。
// demo- のプロジェクトはタイマーである。本物のプロジェクトの Cloud Tasks は次の ticket である。
type bookingSchedule interface {
	Schedule(ctx context.Context, personID, bookingID string, number int64) error
}

type noopSchedule struct{}

func (noopSchedule) Schedule(context.Context, string, string, int64) error { return nil }

// demoSchedule は、バックエンドの中のタイマーで予約の時刻を待つ。
// プロセスが止まるとタイマーは消え、起動したときに、まだかけていない予約を読み直す。
type demoSchedule struct {
	s    *server
	mu   sync.Mutex
	runs map[string]struct{}
	wg   sync.WaitGroup
}

func newDemoSchedule(s *server) *demoSchedule {
	return &demoSchedule{s: s, runs: map[string]struct{}{}}
}

func (d *demoSchedule) Schedule(ctx context.Context, personID, bookingID string, number int64) error {
	snap, err := d.s.bookingRef(personID, bookingID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	var saved booking
	if err := snap.DataTo(&saved); err != nil {
		return err
	}
	if saved.Called || saved.Number != number {
		return nil
	}
	key := personID + "/" + bookingID + "/" + strconv.FormatInt(number, 10)
	d.mu.Lock()
	if _, ok := d.runs[key]; ok {
		d.mu.Unlock()
		return nil
	}
	d.runs[key] = struct{}{}
	d.wg.Add(1)
	d.mu.Unlock()
	go func() {
		defer d.wg.Done()
		d.run(personID, bookingID, number, saved.At)
	}()
	return nil
}

func (d *demoSchedule) run(personID, bookingID string, number int64, at time.Time) {
	ctx := d.s.base
	if !waitFor(ctx, d.s, at.Sub(d.s.now())) {
		return
	}
	for {
		retry, err := d.s.fireBooking(ctx, personID, bookingID, number)
		if err != nil {
			log.Printf("予約 %s をかけられなかった: %v", bookingID, err)
			retry = true
		}
		if !retry || ctx.Err() != nil {
			return
		}
		if !waitFor(ctx, d.s, bookingRetryEvery) {
			return
		}
	}
}

// waitFor は、d が経つか、ctx が終わるまで待つ。ctx が終わったら false を返す。
func waitFor(ctx context.Context, s *server, d time.Duration) bool {
	timer := s.newTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.Chan():
		return true
	}
}

// loadUncalledBookings は、まだかけていない予約を読み、タイマーに入れる。
// 起動の前に保存された予約を、動き直したあともかけるためである。
func (s *server) loadUncalledBookings() {
	// 電話の接続だけを見る起動は Firestore を渡さない。予約は無いので読み直さない。
	if s.firebase.Firestore == nil {
		return
	}
	ctx, cancel := context.WithTimeout(s.base, 30*time.Second)
	defer cancel()
	docs, err := s.firebase.Firestore.CollectionGroup(bookingsCollection).Where("called", "==", false).Documents(ctx).GetAll()
	if err != nil {
		log.Printf("まだかけていない予約を読めなかった: %v", err)
		return
	}
	for _, doc := range docs {
		person := doc.Ref.Parent.Parent
		if person == nil {
			continue
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil || saved.Called {
			continue
		}
		if err := s.schedule.Schedule(ctx, person.ID, doc.Ref.ID, saved.Number); err != nil {
			log.Printf("予約 %s を予定に入れられなかった: %v", doc.Ref.ID, err)
		}
	}
}

func (s *server) bookingCol(personID string) *firestore.CollectionRef {
	return s.firebase.Firestore.Collection(watchedPersons).Doc(personID).Collection(bookingsCollection)
}

func (s *server) bookingRef(personID, bookingID string) *firestore.DocumentRef {
	return s.bookingCol(personID).Doc(bookingID)
}

func (s *server) createBooking(w http.ResponseWriter, r *http.Request) {
	s.writeBooking(w, r, "")
}

func (s *server) editBooking(w http.ResponseWriter, r *http.Request) {
	s.writeBooking(w, r, chi.URLParam(r, "booking"))
}

func (s *server) writeBooking(w http.ResponseWriter, r *http.Request, bookingID string) {
	uid, ok := s.familyUID(w, r)
	if !ok {
		return
	}
	body, ok := readBookingBody(w, r)
	if !ok {
		return
	}
	personID, err := findFamilyPerson(r.Context(), s.firebase.Firestore, uid)
	if errors.Is(err, errNotFamily) {
		http.Error(w, "この見守る方の家族ではないので、予約できません", http.StatusForbidden)
		return
	}
	if err != nil {
		log.Printf("家族の見守る方を読めなかった: %v", err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	id, err := s.saveBooking(r.Context(), personID, bookingID, body)
	if writeBookingError(w, err) {
		return
	}
	if err != nil {
		log.Printf("予約を保存できなかった: %v", err)
		http.Error(w, "予約を保存できなかった", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if bookingID == "" {
		w.WriteHeader(http.StatusCreated)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	json.NewEncoder(w).Encode(savedBooking{ID: id})
}

func readBookingBody(w http.ResponseWriter, r *http.Request) (protocol.BookingBody, bool) {
	var body protocol.BookingBody
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBookingBody)).Decode(&body); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return protocol.BookingBody{}, false
	}
	body.Message = strings.TrimSpace(body.Message)
	body.Script = strings.TrimSpace(body.Script)
	if body.Message == "" || body.Script == "" {
		http.Error(w, "伝えたいことと通話内容を入れてください", http.StatusBadRequest)
		return protocol.BookingBody{}, false
	}
	return body, true
}

func writeBookingError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, errBookingTooSoon):
		writeAPIError(w, http.StatusConflict, protocol.BookingTooSoon)
	case errors.Is(err, errBookingTooFar):
		writeAPIError(w, http.StatusConflict, protocol.BookingTooFar)
	case errors.Is(err, errBookingTooClose):
		writeAPIError(w, http.StatusConflict, protocol.BookingTooClose)
	case errors.Is(err, errBookingNotFound):
		writeAPIError(w, http.StatusNotFound, protocol.BookingNotFound)
	case errors.Is(err, errBookingCalled):
		writeAPIError(w, http.StatusConflict, protocol.BookingAlreadyCalled)
	default:
		return false
	}
	return true
}

// saveBooking は、予約を新しく保存するか、bookingID の予約を直して、その ID を返す。
// 直すと番号が 1 つ増える。保存できたら、その ID と番号で電話を予定に入れる。
func (s *server) saveBooking(ctx context.Context, personID, bookingID string, body protocol.BookingBody) (string, error) {
	col := s.bookingCol(personID)
	ref := col.NewDoc()
	if bookingID != "" {
		ref = col.Doc(bookingID)
	}
	var number int64
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		number = 1
		if bookingID != "" {
			doc, err := tx.Get(ref)
			if status.Code(err) == codes.NotFound {
				return errBookingNotFound
			}
			if err != nil {
				return err
			}
			var current booking
			if err := doc.DataTo(&current); err != nil {
				return err
			}
			if current.Called {
				return errBookingCalled
			}
			number = current.Number + 1
		}
		if err := checkBookingTime(s.now(), body.At); err != nil {
			return err
		}
		if err := s.bookingTooClose(tx, col, ref.ID, body.At); err != nil {
			return err
		}
		if bookingID == "" {
			return tx.Create(ref, map[string]any{
				"at":      body.At,
				"message": body.Message,
				"script":  body.Script,
				"number":  number,
				"called":  false,
			})
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "at", Value: body.At},
			{Path: "message", Value: body.Message},
			{Path: "script", Value: body.Script},
			{Path: "number", Value: number},
		})
	})
	if err != nil {
		return "", err
	}
	// 予約はもう保存してある。予定に入れるのに失敗しても、デモでは起動時に読み直す。
	// ここでエラーにすると、アプリが保存し直して、近い予約を 2 件作ってしまう。
	if err := s.schedule.Schedule(ctx, personID, ref.ID, number); err != nil {
		log.Printf("予約 %s を予定に入れられなかった: %v", ref.ID, err)
	}
	return ref.ID, nil
}

// checkBookingTime は、時刻が今から 1 分より先、30 日先までであることを確かめる。
func checkBookingTime(now, at time.Time) error {
	if !at.After(now.Add(bookingMinLead)) {
		return errBookingTooSoon
	}
	if at.After(now.Add(bookingHorizon)) {
		return errBookingTooFar
	}
	return nil
}

// bookingTooClose は、exceptID 以外の予約が at の前後 bookingGap 以内にあれば errBookingTooClose を返す。
func (s *server) bookingTooClose(tx *firestore.Transaction, col *firestore.CollectionRef, exceptID string, at time.Time) error {
	docs, err := tx.Documents(col).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range docs {
		if doc.Ref.ID == exceptID {
			continue
		}
		var other booking
		if err := doc.DataTo(&other); err != nil {
			return err
		}
		gap := at.Sub(other.At)
		if gap < 0 {
			gap = -gap
		}
		if gap <= bookingGap {
			return errBookingTooClose
		}
	}
	return nil
}

// fireBookingTask は、Cloud Tasks が予約の時刻に呼ぶ道である。
// demo- のプロジェクトでは閉じる。タイマーが fireBooking を直接呼ぶ。
func (s *server) fireBookingTask(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(s.config.ProjectID, "demo-") {
		http.NotFound(w, r)
		return
	}
	token, ok := bearerToken(r)
	if !ok {
		http.Error(w, "Authorization ヘッダーに OIDC トークンを Bearer で入れてください", http.StatusUnauthorized)
		return
	}
	check := s.config.CheckBookingOIDC
	if check == nil {
		check = googleBookingOIDC
	}
	email, err := check(r.Context(), token, s.config.TasksAudience)
	if err != nil || email == "" || email != s.config.TasksAccount {
		http.Error(w, "OIDC トークンを確かめられなかった", http.StatusUnauthorized)
		return
	}
	var task protocol.BookingTask
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBookingBody)).Decode(&task); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	if task.WatchedPersonID == "" || task.BookingID == "" || task.Number < 1 {
		http.Error(w, "予約の ID と番号を入れてください", http.StatusBadRequest)
		return
	}
	retry, err := s.fireBooking(r.Context(), task.WatchedPersonID, task.BookingID, task.Number)
	if err != nil {
		log.Printf("予約 %s をかけられなかった: %v", task.BookingID, err)
		http.Error(w, "予約の電話をかけられなかった", http.StatusInternalServerError)
		return
	}
	if retry {
		http.Error(w, "1 分後にやり直してください", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func bearerToken(r *http.Request) (string, bool) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	token = strings.TrimSpace(token)
	return token, ok && token != ""
}

// googleBookingOIDC は、Google が署名した OIDC トークンを確かめ、そのメールアドレスを返す。
// audience はバックエンドの URL である。トークンそのものはログに出さない。
func googleBookingOIDC(ctx context.Context, token, audience string) (string, error) {
	payload, err := idtoken.Validate(ctx, token, audience)
	if err != nil {
		return "", err
	}
	email, _ := payload.Claims["email"].(string)
	verified, _ := payload.Claims["email_verified"].(bool)
	if email == "" || !verified {
		return "", errors.New("OIDC トークンのメールを確かめられなかった")
	}
	return email, nil
}

// fireBooking は、番号が今の番号で、まだかけていなければ、予約の電話を始める。
// 電話機がつながっていないときと、電話の最中は retry を返す。呼んだ側が 1 分後にやり直す。
// 予約の時刻から bookingGiveUp を過ぎていたら、電話を「つながらなかった」として残し、予約を終える。
func (s *server) fireBooking(ctx context.Context, personID, bookingID string, number int64) (retry bool, err error) {
	doc, err := s.bookingRef(personID, bookingID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var saved booking
	if err := doc.DataTo(&saved); err != nil {
		return false, err
	}
	if saved.Number != number || saved.Called {
		return false, nil
	}
	now := s.now()
	if !now.Before(saved.At.Add(bookingGiveUp)) {
		err := s.closeUnreached(ctx, personID, bookingID, number)
		if errors.Is(err, errBookingStale) {
			return false, nil
		}
		return false, err
	}
	if now.Before(saved.At) {
		return true, nil
	}
	err = s.placeBookedCall(ctx, personID, bookingID, number)
	if errors.Is(err, errPhoneNotConnected) || errors.Is(err, errCallInProgress) {
		return true, nil
	}
	if errors.Is(err, errBookingStale) {
		return false, nil
	}
	return false, err
}

// placeBookedCall は、今すぐ通話と同じように電話を作り、電話機に届ける。
// 届ける前にトランザクションで予約へかけた印を付けるので、同じ番号が 2 回到いてもかけるのは 1 回である。
// 届けられなかったときは印を外し、呼んだ側がやり直せるようにする。
func (s *server) placeBookedCall(ctx context.Context, personID, bookingID string, number int64) error {
	phoneID, linked, online, err := s.phoneLine(ctx, personID)
	if err != nil {
		return err
	}
	if !online {
		return errPhoneNotConnected
	}
	callID, err := s.claimBooking(ctx, personID, bookingID, number)
	if err != nil {
		return err
	}
	if err := s.sendBookedCall(ctx, personID, phoneID, linked, callID); err != nil {
		if rerr := s.releaseBooking(ctx, personID, bookingID, callID); rerr != nil {
			log.Printf("予約 %s の電話を戻せなかった: %v", bookingID, rerr)
			return rerr
		}
		return err
	}
	return nil
}

func (s *server) phoneLine(ctx context.Context, personID string) (phoneID string, linked, online bool, err error) {
	phoneID, linked, err = s.linkedPhoneID(ctx, personID)
	if err != nil {
		return "", false, false, err
	}
	if linked {
		return phoneID, true, s.phones.hasPhone(phoneID), nil
	}
	return "", false, s.phones.connected(personID), nil
}

// sendBookedCall は、今すぐ通話と同じように、電話機へ電話をかける指示を送る。
func (s *server) sendBookedCall(ctx context.Context, personID, phoneID string, linked bool, callID string) error {
	msg := protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: callID}
	if !linked {
		if err := s.phones.send(personID, msg); err != nil {
			return errPhoneNotConnected
		}
		return nil
	}
	s.linkMu.Lock()
	defer s.linkMu.Unlock()
	nowID, nowLinked, err := s.linkedPhoneID(ctx, personID)
	if err != nil {
		return err
	}
	if !nowLinked || nowID != phoneID || !s.phones.hasPhone(nowID) {
		return errPhoneNotConnected
	}
	if err := s.phones.sendPhone(nowID, personID, msg); err != nil {
		s.logf("予約の電話を届けられなかった。見守る方: %s、理由: %s", personID, oneLine(s.redact(err.Error())))
		return errPhoneNotConnected
	}
	s.syncs.dropCode(nowID)
	return nil
}

// claimBooking は、番号が一致し、まだかけていなくて、電話の最中でもなければ、
// 呼び出し中の電話を作り、予約にかけた印を付けて、その電話の ID を返す。
func (s *server) claimBooking(ctx context.Context, personID, bookingID string, number int64) (string, error) {
	ref := s.bookingRef(personID, bookingID)
	calls := s.firebase.Firestore.Collection(watchedPersons).Doc(personID).Collection(callsCollection)
	callRef := calls.NewDoc()
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil {
			return err
		}
		if saved.Number != number || saved.Called {
			return errBookingStale
		}
		busy, err := tx.Documents(calls.Where("state", "in", []string{protocol.StateRinging, protocol.StateTalking}).Limit(1)).GetAll()
		if err != nil {
			return err
		}
		if len(busy) > 0 {
			return errCallInProgress
		}
		if err := tx.Create(callRef, map[string]any{
			"state":     protocol.StateRinging,
			"message":   saved.Message,
			"script":    saved.Script,
			"createdAt": s.now(),
		}); err != nil {
			return err
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "called", Value: true},
			{Path: "callId", Value: callRef.ID},
		})
	})
	if err != nil {
		return "", err
	}
	return callRef.ID, nil
}

// releaseBooking は、届けられなかった電話の印を外し、呼び出し中のままの電話を消す。
func (s *server) releaseBooking(ctx context.Context, personID, bookingID, callID string) error {
	ref := s.bookingRef(personID, bookingID)
	call := s.callRef(personID, callID)
	return s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return nil
		}
		if err != nil {
			return err
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil {
			return err
		}
		if !saved.Called || saved.CallID != callID {
			return nil
		}
		callDoc, err := tx.Get(call)
		if status.Code(err) == codes.NotFound {
			return tx.Update(ref, []firestore.Update{
				{Path: "called", Value: false},
				{Path: "callId", Value: ""},
			})
		}
		if err != nil {
			return err
		}
		state, _ := callDoc.Data()["state"].(string)
		if state != protocol.StateRinging {
			return nil
		}
		if err := tx.Update(ref, []firestore.Update{
			{Path: "called", Value: false},
			{Path: "callId", Value: ""},
		}); err != nil {
			return err
		}
		return tx.Delete(call)
	})
}

// closeUnreached は、予約した時刻と伝えたいことと通話内容で、電話を「つながらなかった」として残し、予約を終える。
func (s *server) closeUnreached(ctx context.Context, personID, bookingID string, number int64) error {
	ref := s.bookingRef(personID, bookingID)
	callRef := s.firebase.Firestore.Collection(watchedPersons).Doc(personID).Collection(callsCollection).NewDoc()
	return s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil {
			return err
		}
		if saved.Number != number || saved.Called {
			return errBookingStale
		}
		if err := tx.Create(callRef, map[string]any{
			"state":     protocol.StateFailed,
			"message":   saved.Message,
			"script":    saved.Script,
			"createdAt": saved.At,
		}); err != nil {
			return err
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "called", Value: true},
			{Path: "callId", Value: callRef.ID},
		})
	})
}
