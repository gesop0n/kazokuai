package server_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	taskspb "cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"github.com/googleapis/gax-go/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 予約のタスクを入れるキュー。名前はプロジェクト、リージョン、キューの ID から組む。
const taskQueue = "projects/kazokuai-prod/locations/asia-northeast1/queues/bookings"

var errTaskRejected = errors.New("キューがタスクを受け取らなかった")

func TestCloudTasksSchedule(t *testing.T) {
	at := time.Date(2026, 11, 10, 4, 30, 0, 0, time.UTC)
	later := time.Date(2026, 11, 10, 5, 0, 0, 0, time.UTC)

	t.Run("保存すると、予約の時刻に ID と番号のタスクを 1 つ頼む", func(t *testing.T) {
		fake := &fakeCloudTasks{}
		srv := newCloudTasksServer(t, clocktest.New(bookingNow), fake)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))

		req := onlyTask(t, fake)
		assertBookingTask(t, req, taskQueue+"/tasks/"+id+"-1", at, person, id, 1)
	})

	t.Run("直すと、新しい時刻と番号のタスクを足し、前のタスクも残る", func(t *testing.T) {
		fake := &fakeCloudTasks{}
		srv := newCloudTasksServer(t, clocktest.New(bookingNow), fake)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))

		edited := postBooking(t, srv.URL, protocol.BookingPath+"/"+id, token, later, "薬の確認", "ハナさん、お薬は飲みましたか。")
		if edited.status != http.StatusOK {
			t.Fatalf("直す = %d %s", edited.status, edited.body)
		}

		reqs := fake.requests()
		if len(reqs) != 2 {
			t.Fatalf("タスク = %d 件, want 保存と直しで 2 件", len(reqs))
		}
		assertBookingTask(t, reqs[0], taskQueue+"/tasks/"+id+"-1", at, person, id, 1)
		assertBookingTask(t, reqs[1], taskQueue+"/tasks/"+id+"-2", later, person, id, 2)
	})

	t.Run("タスクを作れなくても、予約の保存は届いている", func(t *testing.T) {
		fake := &fakeCloudTasks{err: errTaskRejected}
		srv := newCloudTasksServer(t, clocktest.New(bookingNow), fake)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))

		if bookingData(t, person, id)["number"] != int64(1) {
			t.Fatal("タスクが作れなくても、予約は残る")
		}
		// 保存の中で 3 回入れ直す。そのあとは、サーバーが止まるまで 1 分ごとに続ける。
		if len(fake.requests()) != 3 {
			t.Fatalf("タスク = %d 件, want 3 件頼んで失敗する", len(fake.requests()))
		}
	})

	t.Run("タスクを作れないままサーバーが止まると、起動し直したあと、その予約だけを登録する", func(t *testing.T) {
		forgetPendingBookingTasks(t)
		failing := &fakeCloudTasks{err: errTaskRejected}
		first, firstHandler := openCloudTasksServer(t, clocktest.New(bookingNow), failing)
		person, token := registerHanako(t, first.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, first.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))
		if len(failing.requests()) != 3 {
			t.Fatalf("止める前のタスク = %d 件, want 3 件頼んで失敗する", len(failing.requests()))
		}
		// demo:seed の見本と同じく、タスクを作らずに予約を置く。登録待ちの印は無い。
		sample, _, err := emulators.Firestore.Collection("watchedPersons").Doc(person).Collection("bookings").Add(t.Context(), map[string]any{
			"at":      later,
			"message": "見本",
			"script":  "見本の通話です。",
			"number":  int64(1),
			"called":  false,
		})
		if err != nil {
			t.Fatal(err)
		}

		firstHandler.Stop()
		first.Close()

		ready := &fakeCloudTasks{}
		second, secondHandler := openCloudTasksServer(t, clocktest.New(bookingNow), ready)
		for _, got := range ready.requests() {
			if got.GetTask().GetName() == taskQueue+"/tasks/"+sample.ID+"-1" {
				t.Fatal("見本の予約を登録した")
			}
		}
		req := onlyTask(t, ready)
		assertBookingTask(t, req, taskQueue+"/tasks/"+id+"-1", at, person, id, 1)

		secondHandler.Stop()
		second.Close()

		again := &fakeCloudTasks{}
		openCloudTasksServer(t, clocktest.New(bookingNow), again)
		if len(again.requests()) != 0 {
			t.Fatalf("登録済みの予約と見本を、もう一度登録した: %d 件", len(again.requests()))
		}
	})

	t.Run("同じ名前のタスクが既にあれば、入れ直しはしない", func(t *testing.T) {
		fake := &fakeCloudTasks{err: status.Error(codes.AlreadyExists, "既にある")}
		srv := newCloudTasksServer(t, clocktest.New(bookingNow), fake)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))

		if bookingData(t, person, id)["number"] != int64(1) {
			t.Fatal("タスクが既にあっても、予約は残る")
		}
		onlyTask(t, fake)
	})
}

func newCloudTasksServer(t *testing.T, clk *clocktest.Clock, tasks server.CloudTasksClient) *httptest.Server {
	t.Helper()
	// 前のテストが残した登録待ちを、このサーバーの起動で入れ直さない。
	forgetPendingBookingTasks(t)
	srv, _ := openCloudTasksServer(t, clk, tasks)
	return srv
}

func openCloudTasksServer(t *testing.T, clk *clocktest.Clock, tasks server.CloudTasksClient) (*httptest.Server, *server.Handler) {
	t.Helper()
	handler := server.New(server.Config{
		ProjectID:     "kazokuai-prod",
		PhoneSecret:   protocol.DevPhoneSecret,
		TasksAudience: taskAudience,
		TasksAccount:  taskAccount,
		TasksQueue:    taskQueue,
		Tasks:         tasks,
	}, emulators, nil, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

// forgetPendingBookingTasks は、登録待ちの印が残った予約を消す。
// 前のテストの予約を、次のサーバーの起動で入れ直さないためである。
func forgetPendingBookingTasks(t *testing.T) {
	t.Helper()
	docs, err := emulators.Firestore.CollectionGroup("bookings").Where("taskPending", "==", true).Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, doc := range docs {
		if _, err := doc.Ref.Delete(t.Context()); err != nil {
			t.Fatal(err)
		}
	}
}

func assertBookingTask(t *testing.T, req *taskspb.CreateTaskRequest, name string, at time.Time, person, id string, number int64) {
	t.Helper()
	if req.GetParent() != taskQueue {
		t.Fatalf("キュー = %s, want %s", req.GetParent(), taskQueue)
	}
	task := req.GetTask()
	if task.GetName() != name {
		t.Fatalf("名前 = %s, want %s", task.GetName(), name)
	}
	if got := task.GetScheduleTime().AsTime(); !got.Equal(at) {
		t.Fatalf("時刻 = %s, want %s", got, at)
	}
	httpReq := task.GetHttpRequest()
	if httpReq.GetUrl() != taskAudience+protocol.BookingTaskPath {
		t.Fatalf("宛先 = %s, want %s", httpReq.GetUrl(), taskAudience+protocol.BookingTaskPath)
	}
	if httpReq.GetHttpMethod() != taskspb.HttpMethod_POST {
		t.Fatalf("メソッド = %s, want POST", httpReq.GetHttpMethod())
	}
	if httpReq.GetHeaders()["Content-Type"] != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", httpReq.GetHeaders()["Content-Type"])
	}
	oidc := httpReq.GetOidcToken()
	if oidc.GetAudience() != taskAudience {
		t.Fatalf("audience = %s, want %s", oidc.GetAudience(), taskAudience)
	}
	if oidc.GetServiceAccountEmail() != taskAccount {
		t.Fatalf("サービスアカウント = %s, want %s", oidc.GetServiceAccountEmail(), taskAccount)
	}
	var body protocol.BookingTask
	if err := json.Unmarshal(httpReq.GetBody(), &body); err != nil {
		t.Fatalf("本文を読めなかった: %v", err)
	}
	want := protocol.BookingTask{WatchedPersonID: person, BookingID: id, Number: number}
	if body != want {
		t.Fatalf("本文 = %+v, want %+v", body, want)
	}
}

func onlyTask(t *testing.T, fake *fakeCloudTasks) *taskspb.CreateTaskRequest {
	t.Helper()
	reqs := fake.requests()
	if len(reqs) != 1 {
		t.Fatalf("タスク = %d 件, want 1 件", len(reqs))
	}
	return reqs[0]
}

// fakeCloudTasks は、CreateTask に渡された頼みを順に残す。
type fakeCloudTasks struct {
	mu   sync.Mutex
	reqs []*taskspb.CreateTaskRequest
	err  error
}

func (f *fakeCloudTasks) CreateTask(_ context.Context, req *taskspb.CreateTaskRequest, _ ...gax.CallOption) (*taskspb.Task, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reqs = append(f.reqs, req)
	if f.err != nil {
		return nil, f.err
	}
	return req.GetTask(), nil
}

func (f *fakeCloudTasks) requests() []*taskspb.CreateTaskRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]*taskspb.CreateTaskRequest, len(f.reqs))
	copy(out, f.reqs)
	return out
}
