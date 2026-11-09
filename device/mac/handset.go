// Package mac は、Mac で電話機の代わりをする。受話器の音声は既定のマイクとスピーカー、
// フックは Enter キー、呼び出し音とランプはターミナルの文字である。
//
// macOS の malgo にはエコーキャンセルがないので、イヤホンを付けて使う。
package mac

import "github.com/gesop0n/kazokuai/device/handset"

// OpenHandset は、既定のマイクとスピーカーを受話器として開く。
// マイクは 16 kHz、スピーカーは 24 kHz で、どちらも 1 チャンネルのままである。
// 機器の速さへの変換は malgo に任せる。
func OpenHandset() (*handset.Handset, error) {
	return handset.Open(handset.Options{})
}
