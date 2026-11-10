package server

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"

	taskspb "cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"github.com/googleapis/gax-go/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// CloudTasksClient は、Cloud Tasks にタスクを 1 つ作る。*cloudtasks.Client が満たす。
// テストは偽のクライアントを渡し、頼んだタスクの時刻、名前、宛先、audience、サービスアカウントを確かめる。
type CloudTasksClient interface {
	CreateTask(ctx context.Context, req *taskspb.CreateTaskRequest, opts ...gax.CallOption) (*taskspb.Task, error)
}

// cloudTasksSchedule は、予約の保存と直しのたびに Cloud Tasks のタスクを 1 つ作る。
// 名前は予約の ID と番号、時刻は予約の時刻である。古いタスクは消さない。番号が違えば、届いてもかけない。
type cloudTasksSchedule struct {
	s        *server
	client   CloudTasksClient
	queue    string
	audience string
	account  string
}

func (c *cloudTasksSchedule) Schedule(ctx context.Context, personID, bookingID string, number int64) error {
	if c.client == nil || c.queue == "" || c.audience == "" || c.account == "" {
		return errBookingTaskConfig
	}
	snap, err := readBookingForSchedule(ctx, c.s.bookingRef(personID, bookingID))
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
	body, err := json.Marshal(protocol.BookingTask{
		WatchedPersonID: personID,
		BookingID:       bookingID,
		Number:          number,
	})
	if err != nil {
		return err
	}
	_, err = c.client.CreateTask(ctx, &taskspb.CreateTaskRequest{
		Parent: c.queue,
		Task: &taskspb.Task{
			Name:         c.queue + "/tasks/" + bookingID + "-" + strconv.FormatInt(number, 10),
			ScheduleTime: timestamppb.New(saved.At),
			MessageType: &taskspb.Task_HttpRequest{
				HttpRequest: &taskspb.HttpRequest{
					HttpMethod: taskspb.HttpMethod_POST,
					Url:        strings.TrimRight(c.audience, "/") + protocol.BookingTaskPath,
					Headers:    map[string]string{"Content-Type": "application/json"},
					Body:       body,
					AuthorizationHeader: &taskspb.HttpRequest_OidcToken{
						OidcToken: &taskspb.OidcToken{
							ServiceAccountEmail: c.account,
							Audience:            c.audience,
						},
					},
				},
			},
		},
	})
	// 入れ直しが同じ名前をもう一度作ると、既にある。タスクは入っているので、ここでは成功にする。
	if status.Code(err) == codes.AlreadyExists {
		return nil
	}
	return err
}
