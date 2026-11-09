// 同期で受話器が話す音声を Gemini の音声合成で作り、device/spoken/clips に WAV で書く。
// GEMINI_API_KEY が要る。声はどれも同じ 1 つである。家族が AI に選ぶ声とは別である。
//
//	mise run spoken:clips
package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/device/spoken/clip"
)

// model は、Google の音声合成のドキュメントにある現行のモデルである。
// https://ai.google.dev/gemini-api/docs/speech-generation
const model = "gemini-3.8-flash-tts"

// voice は、すべての音声で使う声である。Kore はドキュメントの prebuilt voice で、Firm と書かれている。
const voice = "Kore"

// style は、読み上げ方である。言葉そのものは Clip.Text で、ここは声の出し方だけを渡す。
const style = "ゆっくり、はっきり、落ち着いた声で読む"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, redact(err))
		os.Exit(1)
	}
}

func run() error {
	key := os.Getenv("GEMINI_API_KEY")
	if key == "" {
		return errors.New("GEMINI_API_KEY が要ります")
	}
	// mise のタスクはリポジトリのルートで動かす。
	if _, err := os.Stat("go.mod"); err != nil {
		return errors.New("リポジトリのルートで動かしてください")
	}
	dir := filepath.Join("device", "spoken", "clips")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	ctx := context.Background()
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  key,
		Backend: genai.BackendGeminiAPI,
	})
	if err != nil {
		return redact(err)
	}

	// gemini-3.8-flash-tts は、1 分に 10 回までである。間を空けて、その中に収める。
	const gap = 7 * time.Second
	for i, c := range clip.Clips() {
		if i > 0 {
			time.Sleep(gap)
		}
		wav, err := synthesize(ctx, client, c.Text)
		if err != nil {
			return fmt.Errorf("%s: %w", c.File, redact(err))
		}
		path := filepath.Join(dir, c.File)
		if err := os.WriteFile(path, wav, 0o644); err != nil {
			return err
		}
		fmt.Fprintf(os.Stderr, "%s を書きました (%d バイト)\n", c.File, len(wav))
	}
	return nil
}

func synthesize(ctx context.Context, client *genai.Client, text string) ([]byte, error) {
	var last error
	for attempt := 0; attempt < 6; attempt++ {
		if attempt > 0 {
			wait := retryWait(last)
			fmt.Fprintf(os.Stderr, "上限に当たったので %s 待ちます\n", wait.Round(time.Second))
			time.Sleep(wait)
		}
		callCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
		wav, err := once(callCtx, client, text)
		cancel()
		if err == nil {
			return wav, nil
		}
		last = err
		if !retryable(err) {
			return nil, err
		}
	}
	return nil, last
}

func retryable(err error) bool {
	s := err.Error()
	return strings.Contains(s, "429") || strings.Contains(s, "RESOURCE_EXHAUSTED")
}

var retryAfter = regexp.MustCompile(`retry in ([0-9.]+)s`)

func retryWait(err error) time.Duration {
	if err != nil {
		if m := retryAfter.FindStringSubmatch(err.Error()); len(m) == 2 {
			if seconds, convErr := strconv.ParseFloat(m[1], 64); convErr == nil && seconds > 0 {
				return time.Duration(seconds*float64(time.Second)) + time.Second
			}
		}
	}
	return 40 * time.Second
}

func once(ctx context.Context, client *genai.Client, text string) ([]byte, error) {
	resp, err := client.Models.GenerateContent(ctx, model, []*genai.Content{{
		Role: genai.RoleUser,
		Parts: []*genai.Part{{
			Text:           text,
			SpeechMetadata: &genai.SpeechMetadata{Style: style},
		}},
	}}, &genai.GenerateContentConfig{
		ResponseModalities: []string{string(genai.ModalityAudio)},
		SpeechConfig: &genai.SpeechConfig{
			VoiceConfig: &genai.VoiceConfig{Voice: voice},
		},
	})
	if err != nil {
		return nil, err
	}
	data, mime, err := audioFrom(resp)
	if err != nil {
		return nil, err
	}
	wav := data
	if !bytes.HasPrefix(data, []byte("RIFF")) {
		if len(data) == 0 || len(data)%2 != 0 {
			return nil, fmt.Errorf("PCM の長さが合いません (形式 %s)", mime)
		}
		wav = clip.WAV(data)
	}
	if _, err := clip.PCM(wav); err != nil {
		return nil, fmt.Errorf("形式 %s: %w", mime, err)
	}
	return wav, nil
}

func audioFrom(resp *genai.GenerateContentResponse) ([]byte, string, error) {
	if resp == nil || len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil {
		return nil, "", errors.New("音声が返りませんでした")
	}
	var text string
	for _, part := range resp.Candidates[0].Content.Parts {
		if part == nil {
			continue
		}
		if part.InlineData != nil && len(part.InlineData.Data) > 0 {
			return part.InlineData.Data, part.InlineData.MIMEType, nil
		}
		if part.Text != "" {
			text = part.Text
		}
	}
	if text != "" {
		return nil, "", fmt.Errorf("音声ではなく文字が返りました: %s", shorten(text))
	}
	return nil, "", errors.New("音声が返りませんでした")
}

func shorten(s string) string {
	r := []rune(s)
	if len(r) > 80 {
		return string(r[:80])
	}
	return s
}

var secret = regexp.MustCompile(`AIza[0-9A-Za-z_-]{10,}`)

func redact(err error) error {
	if err == nil {
		return nil
	}
	s := secret.ReplaceAllString(err.Error(), "[REDACTED]")
	if s == err.Error() {
		return err
	}
	return errors.New(s)
}
