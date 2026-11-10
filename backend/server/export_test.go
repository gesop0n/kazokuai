package server

import (
	"context"

	"cloud.google.com/go/firestore"
)

// StubBookingScheduleRead は、予定に入れるときの予約の読み直しを差し替える。
// テストが一時的な失敗を再現する。nil で元に戻す。
func StubBookingScheduleRead(fn func(context.Context, *firestore.DocumentRef) (*firestore.DocumentSnapshot, error)) {
	bookingHookMu.Lock()
	bookingScheduleRead = fn
	bookingHookMu.Unlock()
}

// StubBeforeBookedSend は、予約の電話を届ける直前に呼ぶ。nil で元に戻す。
func StubBeforeBookedSend(fn func(context.Context)) {
	bookingHookMu.Lock()
	beforeBookedSend = fn
	bookingHookMu.Unlock()
}

// StubAfterBookedWrite は、ソケットへの書き込みが戻った直後に呼ぶ。nil で元に戻す。
// 送ったか分からない電話の ID は、この前に書いてある。
func StubAfterBookedWrite(fn func(context.Context)) {
	bookingHookMu.Lock()
	afterBookedWrite = fn
	bookingHookMu.Unlock()
}

// StubAfterBookedSend は、予約の電話を届けたあと、届けた印を書く前に呼ぶ。nil で元に戻す。
func StubAfterBookedSend(fn func(context.Context)) {
	bookingHookMu.Lock()
	afterBookedSend = fn
	bookingHookMu.Unlock()
}

// StubUncalledBookingsRead は、起動のときにまだかけていない予約を読む処理を差し替える。
// nil で元に戻す。
func StubUncalledBookingsRead(fn func(context.Context) ([]*firestore.DocumentSnapshot, error)) {
	bookingHookMu.Lock()
	uncalledBookingsRead = fn
	bookingHookMu.Unlock()
}

// StubBeforeBookingRelease は、予約の印を外す直前に呼ぶ。エラーを返すとその回は外さない。nil で元に戻す。
func StubBeforeBookingRelease(fn func(context.Context) error) {
	bookingHookMu.Lock()
	beforeBookingRelease = fn
	bookingHookMu.Unlock()
}
