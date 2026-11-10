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
	// bookingScheduleTries は、保存した予約を予定へ入れるときのやり直しの回数である。
	bookingScheduleTries = 3
	// bookingReleaseTries は、届けられなかった電話の印を外すときのやり直しの回数である。
	bookingReleaseTries = 3
	// bookingOpTimeout は、予定へ入れるときと、印を外すときの 1 回の上限である。
	bookingOpTimeout = 10 * time.Second
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
	// Sent は、電話機に届け終えたかである。かけていても、届く前に失敗したときは false のままである。
	Sent bool `firestore:"sent"`
	// UnknownCallID は、電話機に送ったかどうかが分からない電話の ID である。
	// 送ったあと、届けた印を書く前にプロセスが止まると残る。残っているあいだは、同じ予約で別の電話を始めない。
	UnknownCallID string `firestore:"unknownCallId"`
	// TaskPending は、この番号のタスクがまだ Cloud Tasks に無いとき true である。
	// 保存と直しで立て、タスクを作れたら下ろす。見本の予約は持たないので、起動し直しても登録しない。
	TaskPending bool `firestore:"taskPending"`
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
	// errBookingStale は、タスクの番号が今の番号と違うか、もう届けたあとである。電話はかけない。
	errBookingStale = errors.New("予約の番号が違うか、もうかけた")
	// errReleaseFailed は、届けられなかった電話の印を外せなかったときである。呼んだ側はやり直す。
	errReleaseFailed = errors.New("予約の電話を戻せなかった")
	// errBookingTaskConfig は、本物のプロジェクトなのにキューか URL かサービスアカウントが無い。
	errBookingTaskConfig = errors.New("予約のタスクの設定が無い")
)

// 予定へ入れる前の読み直しと、届ける直前と、印を外す直前を、テストが一時的な失敗に差し替える。
var (
	bookingHookMu        sync.Mutex
	bookingScheduleRead  func(context.Context, *firestore.DocumentRef) (*firestore.DocumentSnapshot, error)
	beforeBookedSend     func(context.Context)
	afterBookedSend      func(context.Context)
	beforeBookingRelease func(context.Context) error
	uncalledBookingsRead func(context.Context) ([]*firestore.DocumentSnapshot, error)
)

func readUncalledBookings(ctx context.Context, store *firestore.Client) ([]*firestore.DocumentSnapshot, error) {
	bookingHookMu.Lock()
	fn := uncalledBookingsRead
	bookingHookMu.Unlock()
	if fn != nil {
		return fn(ctx)
	}
	return store.CollectionGroup(bookingsCollection).Where("called", "==", false).Documents(ctx).GetAll()
}

func readBookingForSchedule(ctx context.Context, ref *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) {
	bookingHookMu.Lock()
	fn := bookingScheduleRead
	bookingHookMu.Unlock()
	if fn != nil {
		return fn(ctx, ref)
	}
	return ref.Get(ctx)
}

// bookingSchedule は、予約の ID と番号で、その時刻に電話を予定へ入れる。
// 予約の ID は見守る方の下で一意なので、見守る方の ID も受け取る。
// demo- のプロジェクトはタイマーである。本物のプロジェクトは Cloud Tasks である。
type bookingSchedule interface {
	Schedule(ctx context.Context, personID, bookingID string, number int64) error
}

type noopSchedule struct{}

func (noopSchedule) Schedule(context.Context, string, string, int64) error { return nil }

// demoSchedule は、バックエンドの中のタイマーで予約の時刻を待つ。
// プロセスが止まるとタイマーは消え、起動したときに、まだかけていない予約と、
// 印を付けたあと送る前に止まった予約を読み直す。
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
	snap, err := readBookingForSchedule(ctx, d.s.bookingRef(personID, bookingID))
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
	if saved.Number != number || saved.Sent || saved.UnknownCallID != "" {
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

// loadUncalledBookings は、まだかけていない予約と、印を付けたあと送る前に止まった予約を読み、タイマーに入れる。
// 起動の前に保存された予約を、動き直したあともかけるためである。
// 一覧の読み込みが失敗したときは、予定へ入れるときと同じようにやり直す。
func (s *server) loadUncalledBookings() {
	// 電話の接続だけを見る起動は Firestore を渡さない。予約は無いので読み直さない。
	if s.firebase.Firestore == nil {
		return
	}
	if s.tryLoadUncalledBookings() {
		return
	}
	s.work.Add(1)
	go func() {
		defer s.work.Done()
		for s.base.Err() == nil {
			if !waitFor(s.base, s, bookingRetryEvery) {
				return
			}
			if s.tryLoadUncalledBookings() {
				return
			}
		}
	}()
}

// tryLoadUncalledBookings は、起動時の予約の一覧を読み、タイマーに入れる。入ったら true を返す。
func (s *server) tryLoadUncalledBookings() bool {
	for try := 1; try <= bookingScheduleTries; try++ {
		if s.base.Err() != nil {
			return false
		}
		ctx, cancel := context.WithTimeout(s.base, bookingOpTimeout)
		err := s.loadUncalledOnce(ctx)
		cancel()
		if err == nil {
			return true
		}
		log.Printf("まだかけていない予約を読めなかった（%d 回目）: %v", try, err)
	}
	return false
}

func (s *server) loadUncalledOnce(ctx context.Context) error {
	docs, err := readUncalledBookings(ctx, s.firebase.Firestore)
	if err != nil {
		return err
	}
	s.scheduleLoaded(docs, func(saved booking, _ map[string]any) bool {
		return !saved.Called
	})
	// かけた印だけが残って、まだ送っていない予約。called == false の一覧には出てこない。
	stuck, err := s.firebase.Firestore.CollectionGroup(bookingsCollection).Where("called", "==", true).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	s.scheduleLoaded(stuck, func(saved booking, raw map[string]any) bool {
		sent, ok := raw["sent"].(bool)
		return saved.Called && ok && !sent && saved.UnknownCallID == ""
	})
	return nil
}

func (s *server) scheduleLoaded(docs []*firestore.DocumentSnapshot, keep func(booking, map[string]any) bool) {
	for _, doc := range docs {
		person := doc.Ref.Parent.Parent
		if person == nil {
			continue
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil || !keep(saved, doc.Data()) {
			continue
		}
		s.scheduleBooking(person.ID, doc.Ref.ID, saved.Number)
	}
}

// loadPendingBookingTasks は、タスクがまだ入っていない予約を読み、登録をやり直す。
// プロセスが止まる前にタスクを作れなかった予約を、起動し直したあとに入れるためである。
// 見本の予約は印が無いので、ここには出てこない。
// bookings の taskPending をコレクショングループで読む。単一フィールドのそのインデックスは自動では作られない。
// infra の google_firestore_field と firebase/firestore.indexes.json に書いてある。
func (s *server) loadPendingBookingTasks() {
	if s.firebase.Firestore == nil {
		return
	}
	ctx, cancel := context.WithTimeout(s.base, 30*time.Second)
	defer cancel()
	docs, err := s.firebase.Firestore.CollectionGroup(bookingsCollection).Where("taskPending", "==", true).Documents(ctx).GetAll()
	if err != nil {
		log.Printf("登録待ちの予約を読めなかった: %v", err)
		return
	}
	for _, doc := range docs {
		person := doc.Ref.Parent.Parent
		if person == nil {
			continue
		}
		var saved booking
		if err := doc.DataTo(&saved); err != nil || !saved.TaskPending {
			continue
		}
		s.scheduleBooking(person.ID, doc.Ref.ID, saved.Number)
	}
}

// scheduleBooking は、予約の ID と番号で電話を予定へ入れる。
// リクエストの context は使わない。読み直しが一時的に失敗しても、その場でやり直し、
// それでも入らなければ、サーバーが止まるまで入れ続ける。
// 編集で番号が進んだあとに予定が無いと、古いタイマーは何もせず、再起動まで電話がかからない。
func (s *server) scheduleBooking(personID, bookingID string, number int64) {
	if s.schedule == nil || s.trySchedule(personID, bookingID, number) {
		return
	}
	s.work.Add(1)
	go func() {
		defer s.work.Done()
		for s.base != nil && s.base.Err() == nil {
			if !waitFor(s.base, s, bookingRetryEvery) {
				return
			}
			if s.trySchedule(personID, bookingID, number) {
				return
			}
		}
	}()
}

// trySchedule は、予約を予定へ入れる。入ったら true を返す。
// サーバーが止まると false を返す。リクエストが切れても、ここは止まらない。
func (s *server) trySchedule(personID, bookingID string, number int64) bool {
	parent := s.base
	if parent == nil {
		parent = context.Background()
	}
	for try := 1; try <= bookingScheduleTries; try++ {
		if parent.Err() != nil {
			return false
		}
		ctx, cancel := context.WithTimeout(parent, bookingOpTimeout)
		err := s.schedule.Schedule(ctx, personID, bookingID, number)
		cancel()
		if err == nil {
			return true
		}
		log.Printf("予約 %s を予定に入れられなかった（%d 回目）: %v", bookingID, try, err)
	}
	return false
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
			data := map[string]any{
				"at":      body.At,
				"message": body.Message,
				"script":  body.Script,
				"number":  number,
				"called":  false,
			}
			if s.wantsBookingTask() {
				data["taskPending"] = true
			}
			return tx.Create(ref, data)
		}
		updates := []firestore.Update{
			{Path: "at", Value: body.At},
			{Path: "message", Value: body.Message},
			{Path: "script", Value: body.Script},
			{Path: "number", Value: number},
		}
		if s.wantsBookingTask() {
			updates = append(updates, firestore.Update{Path: "taskPending", Value: true})
		}
		return tx.Update(ref, updates)
	})
	if err != nil {
		return "", err
	}
	// 予約はもう保存してある。予定へ入れるのに失敗しても、ここではエラーにしない。
	// エラーにすると、アプリが保存し直して、近い予約を 2 件作ってしまう。
	// 入れ直しは scheduleBooking が、リクエストとは別の context で続ける。
	// 本物のプロジェクトでは登録待ちの印が残るので、起動し直しても、その予約だけを入れ直す。
	s.scheduleBooking(personID, ref.ID, number)
	return ref.ID, nil
}

// clearTaskPending は、この番号のタスクが Cloud Tasks に入ったので、登録待ちの印を下ろす。
// 番号が変わっていたら下ろさない。直したあとの番号は、まだタスクが要る。
func (s *server) clearTaskPending(ctx context.Context, personID, bookingID string, number int64) error {
	ref := s.bookingRef(personID, bookingID)
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
		if saved.Number != number || !saved.TaskPending {
			return nil
		}
		return tx.Update(ref, []firestore.Update{{Path: "taskPending", Value: false}})
	})
}

// wantsBookingTask は、このサーバーが Cloud Tasks に予約のタスクを作るかを返す。
// デモのタイマーと、タスクを作らない見本の予約は、登録待ちの印を持たない。
func (s *server) wantsBookingTask() bool {
	_, ok := s.schedule.(*cloudTasksSchedule)
	return ok
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
	// audience が空だと、検証側は aud を見ない。別のサービス向けのトークンでも予約を実行できてしまう。
	if strings.TrimSpace(s.config.TasksAudience) == "" {
		http.Error(w, "OIDC トークンを確かめられなかった", http.StatusUnauthorized)
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
	if audience == "" {
		return "", errors.New("OIDC トークンの audience が設定されていない")
	}
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
	if saved.Number != number || (saved.Called && saved.Sent) {
		return false, nil
	}
	// かけた印が残っている。送ったか分からない電話は残し、別の電話を始めない。
	// 送っていない呼び出し中は外して、この回でかける。
	if saved.Called {
		s.deliverMu.Lock()
		place, retry, err := s.recoverUnsent(personID, bookingID, number)
		s.deliverMu.Unlock()
		if err != nil || !place {
			return retry, err
		}
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
	if errors.Is(err, errPhoneNotConnected) || errors.Is(err, errCallInProgress) || errors.Is(err, errReleaseFailed) {
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
	s.deliverMu.Lock()
	defer s.deliverMu.Unlock()
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
		if rerr := s.releaseBookedCall(personID, bookingID, callID); rerr != nil {
			log.Printf("予約 %s の電話を戻せなかった: %v", bookingID, rerr)
			return errReleaseFailed
		}
		return err
	}
	// 届けた印の前に、送ったか分からない電話の ID を残す。プロセスが止まっても、次のタスクは別の電話を始めない。
	if err := s.rememberUnknownCall(personID, bookingID, callID); err != nil {
		log.Printf("予約 %s の、送ったか分からない電話を覚えられなかった: %v", bookingID, err)
		s.noteDelivered(callID)
	}
	bookingHookMu.Lock()
	after := afterBookedSend
	bookingHookMu.Unlock()
	if after != nil {
		after(ctx)
	}
	if err := s.markBookingSent(personID, bookingID); err != nil {
		log.Printf("予約 %s に届けた印を付けられなかった: %v", bookingID, err)
		s.noteDelivered(callID)
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
	bookingHookMu.Lock()
	hook := beforeBookedSend
	bookingHookMu.Unlock()
	if hook != nil {
		hook(ctx)
	}
	msg := protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: callID}
	if !linked {
		if err := s.phones.send(personID, msg); err != nil {
			return errPhoneNotConnected
		}
		return nil
	}
	return s.sendToLinkedPhone(ctx, personID, phoneID, msg)
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
			{Path: "sent", Value: false},
			{Path: "unknownCallId", Value: ""},
		})
	})
	if err != nil {
		return "", err
	}
	return callRef.ID, nil
}

// releaseBookedCall は、届けられなかった電話の印を外す。
// リクエストの中断やサーバーの停止で context が終わっても、別の context で外し切る。
// 外せないと、かけた印が残って次のタスクは何もしない。
func (s *server) releaseBookedCall(personID, bookingID, callID string) error {
	var last error
	for try := 1; try <= bookingReleaseTries; try++ {
		ctx, cancel := context.WithTimeout(context.Background(), bookingOpTimeout)
		last = s.releaseBooking(ctx, personID, bookingID, callID)
		cancel()
		if last == nil {
			return nil
		}
		log.Printf("予約 %s の電話を戻せなかった（%d 回目）: %v", bookingID, try, last)
	}
	return last
}

// releaseBooking は、届けられなかった電話の印を外し、呼び出し中のままの電話を消す。
func (s *server) releaseBooking(ctx context.Context, personID, bookingID, callID string) error {
	bookingHookMu.Lock()
	hook := beforeBookingRelease
	bookingHookMu.Unlock()
	if hook != nil {
		if err := hook(ctx); err != nil {
			return err
		}
	}
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
				{Path: "sent", Value: false},
				{Path: "unknownCallId", Value: ""},
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
			{Path: "sent", Value: false},
			{Path: "unknownCallId", Value: ""},
		}); err != nil {
			return err
		}
		return tx.Delete(call)
	})
}

// recoverUnsent は、かけた印が残っていて、まだ届けた印が無い予約を扱う。
// deliverMu を持っているときに呼ぶ。
// place が true のときは、送っていない呼び出し中を外してある。呼んだ側がこの回でかける。
// 送ったか分からない電話は残し、別の電話を始めない。
func (s *server) recoverUnsent(personID, bookingID string, number int64) (place bool, retry bool, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), bookingOpTimeout)
	defer cancel()
	doc, err := s.bookingRef(personID, bookingID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return false, false, nil
	}
	if err != nil {
		return false, true, nil
	}
	var saved booking
	if err := doc.DataTo(&saved); err != nil {
		return false, true, nil
	}
	if saved.Number != number {
		return false, false, nil
	}
	if !saved.Called {
		return true, false, nil
	}
	if saved.Sent || s.wasDelivered(saved.CallID) {
		if err := s.markBookingSent(personID, bookingID); err != nil {
			log.Printf("予約 %s に届けた印を付けられなかった: %v", bookingID, err)
		}
		return false, false, nil
	}
	// 呼び出し中の電話からは、送ったかどうかが分からない。ID が残っていれば、別の電話を始めない。
	if saved.UnknownCallID != "" && saved.UnknownCallID == saved.CallID {
		return false, false, nil
	}
	callDoc, err := s.callRef(personID, saved.CallID).Get(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		return false, true, nil
	}
	if err == nil {
		state, _ := callDoc.Data()["state"].(string)
		if state != "" && state != protocol.StateRinging {
			if err := s.markBookingSent(personID, bookingID); err != nil {
				log.Printf("予約 %s に届けた印を付けられなかった: %v", bookingID, err)
			}
			return false, false, nil
		}
	}
	if err := s.releaseBookedCall(personID, bookingID, saved.CallID); err != nil {
		return false, true, nil
	}
	return true, false, nil
}

// markBookingSent は、予約に届けた印を付ける。リクエストが切れても付ける。
func (s *server) markBookingSent(personID, bookingID string) error {
	var last error
	for range bookingReleaseTries {
		ctx, cancel := context.WithTimeout(context.Background(), bookingOpTimeout)
		_, last = s.bookingRef(personID, bookingID).Update(ctx, []firestore.Update{
			{Path: "sent", Value: true},
			{Path: "unknownCallId", Value: ""},
		})
		cancel()
		if last == nil {
			return nil
		}
	}
	return last
}

// rememberUnknownCall は、送ったかどうかが分からない電話の ID を予約に残す。
// 届けた印を書く前にプロセスが止まっても、次のタスクが同じ ID を見て、別の電話を始めないためである。
func (s *server) rememberUnknownCall(personID, bookingID, callID string) error {
	var last error
	for range bookingReleaseTries {
		ctx, cancel := context.WithTimeout(context.Background(), bookingOpTimeout)
		_, last = s.bookingRef(personID, bookingID).Update(ctx, []firestore.Update{{Path: "unknownCallId", Value: callID}})
		cancel()
		if last == nil {
			s.noteDelivered(callID)
			return nil
		}
	}
	return last
}

func (s *server) noteDelivered(callID string) {
	if callID == "" || s.delivered == nil {
		return
	}
	s.delivered[callID] = struct{}{}
}

func (s *server) wasDelivered(callID string) bool {
	if callID == "" || s.delivered == nil {
		return false
	}
	_, ok := s.delivered[callID]
	return ok
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
			{Path: "sent", Value: true},
			{Path: "unknownCallId", Value: ""},
		})
	})
}
