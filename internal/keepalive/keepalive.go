// Package keepalive は、WebSocket へ一定の間隔で ping を送る。
// 電話機とバックエンドが、半分切れた接続を同じ基準で閉じる。
package keepalive

import (
	"context"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// pingTimeout は、pong を待つ時間である。これを過ぎたら、半分切れた接続とみる。
const pingTimeout = time.Second

// Run は、ctx が終わるまで ping を送る。返事が無ければ接続を閉じる。
// clk が nil なら、実時間で待つ。
func Run(ctx context.Context, clk clock.Clock, conn *websocket.Conn) {
	if clk == nil {
		clk = clock.Real{}
	}
	for {
		timer := clk.NewTimer(protocol.PingInterval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.Chan():
		}
		if ctx.Err() != nil {
			return
		}
		pingCtx, cancel := context.WithTimeout(ctx, pingTimeout)
		err := conn.Ping(pingCtx)
		cancel()
		if err != nil {
			conn.CloseNow()
			return
		}
	}
}
