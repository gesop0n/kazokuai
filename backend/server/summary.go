package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	summaryMade    = "作れた"
	summaryNotMade = "作れなかった"
	// summaryAttempts は、generateContent を試す回数である。
	summaryAttempts = 3
	// summaryTimeout は、まとめを作る全体の上限である。
	summaryTimeout = 2 * time.Minute
)

// summaryDraft は、Gemini に作らせるまとめである。JSON Schema はこの構造体から作る。
type summaryDraft struct {
	Headline string         `json:"headline" firestore:"headline"`
	Quote    summaryQuote   `json:"quote" firestore:"quote"`
	Meal     summaryToday   `json:"meal" firestore:"meal"`
	Sleep    summaryToday   `json:"sleep" firestore:"sleep"`
	Health   summaryToday   `json:"health" firestore:"health"`
	Topic    string         `json:"topic" firestore:"topic" schema:"enum=体調,enum=話し相手,enum=操作案内"`
	Points   []summaryPoint `json:"points" firestore:"points"`
}

// summaryQuote は、本人の言葉と、受話器を上げてからの時刻である。
type summaryQuote struct {
	Text     string `json:"text" firestore:"text"`
	OffsetMs int64  `json:"offsetMs" firestore:"offsetMs"`
}

// summaryToday は、今日の様子の 1 項目である。
// Status が「話していない」のときは、話した様子と本人の言葉を空にする。
type summaryToday struct {
	Status     string `json:"status" firestore:"status" schema:"enum=話した,enum=話していない"`
	Said       string `json:"said" firestore:"said"`
	Quote      string `json:"quote" firestore:"quote"`
	Concerning bool   `json:"concerning" firestore:"concerning"`
}

// summaryPoint は、時刻付きの詳細のまとめの 1 点である。
type summaryPoint struct {
	Text     string `json:"text" firestore:"text"`
	OffsetMs int64  `json:"offsetMs" firestore:"offsetMs"`
}

// summarySchema は、summaryDraft から作った JSON Schema である。
var summarySchema = schemaOf(summaryDraft{})

// summaryInstruction は、まとめを作る Gemini への指示である。
const summaryInstruction = `あなたは、見守る方と AI の電話から、家族に向けたまとめを作ります。

# 本人の言葉
- 本人の言葉は、見守る方の発話から一字一句そのまま抜き出してください。
- 言い換えたり、AI の言葉を本人の言葉にしたりしないでください。

# 気になる
- 気になるは、見守る方が自分で、困っていることやいつもと違うことを話したときだけ付けてください。
- それ以外は、気になるにしないでください。

# 判断
- 医学的な判断はしないでください。
- 症状の重さや、病名の見当を書かないでください。

# 話していないこと
- 食事、睡眠、体調のうち、話に出なかった項目は「話していない」としてください。
- 話していない項目は、話した様子と本人の言葉を空にしてください。

# 話の種類
- 体調、話し相手、操作案内のどれか 1 つを選んでください。

# 時刻
- 時刻は、受話器を上げてからのミリ秒です。会話に書いてある時刻を使ってください。
`

// makeSummary は、保存した電話のまとめを裏で作り、結果をその電話に書く。
func (s *server) makeSummary(callID string, report protocol.CallReport) {
	ctx, cancel := context.WithTimeout(context.Background(), summaryTimeout)
	defer cancel()
	ref := s.firebase.Firestore.Collection(watchedPersons).Doc(s.config.WatchedPerson).Collection(callsCollection).Doc(callID)
	var last error
	for attempt := 1; attempt <= summaryAttempts; attempt++ {
		if attempt > 1 && s.config.SummaryRetryWait > 0 {
			timer := time.NewTimer(s.config.SummaryRetryWait)
			select {
			case <-ctx.Done():
				last = ctx.Err()
				timer.Stop()
				s.markSummaryNotMade(ref, last)
				return
			case <-timer.C:
			}
		}
		err := s.summarizeOnce(ctx, ref, report)
		if err == nil {
			return
		}
		last = err
		log.Printf("まとめを作れなかった（%d回目）: %v", attempt, err)
	}
	s.markSummaryNotMade(ref, last)
}

func (s *server) summarizeOnce(ctx context.Context, ref *firestore.DocumentRef, report protocol.CallReport) error {
	if s.summarizer == nil {
		return errors.New("まとめを作る Gemini がない")
	}
	response, err := s.summarizer.GenerateContent(ctx, s.summaryModel(), summaryContents(report), summaryConfig())
	if err != nil {
		return err
	}
	text := response.Text()
	if strings.TrimSpace(text) == "" {
		return errors.New("Gemini の応答にまとめがなかった")
	}
	var draft summaryDraft
	if err := json.Unmarshal([]byte(text), &draft); err != nil {
		return fmt.Errorf("まとめの JSON を読めなかった: %w", err)
	}
	dropUnmatchedQuotes(&draft, report.Utterances)
	if draft.Points == nil {
		draft.Points = []summaryPoint{}
	}
	_, err = ref.Update(ctx, []firestore.Update{
		{Path: "summaryState", Value: summaryMade},
		{Path: "summary", Value: draft},
	})
	if err != nil {
		return err
	}
	log.Printf("電話のまとめを保存しました: %s", ref.ID)
	return nil
}

func (s *server) markSummaryNotMade(ref *firestore.DocumentRef, cause error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, err := ref.Update(ctx, []firestore.Update{
		{Path: "summaryState", Value: summaryNotMade},
	})
	if err != nil {
		log.Printf("まとめを作れなかったと記録できなかった: %v（原因: %v）", err, cause)
		return
	}
	log.Printf("まとめを作れなかった: %v", cause)
}

func (s *server) summaryModel() string {
	if s.config.SummaryModel != "" {
		return s.config.SummaryModel
	}
	return DefaultSummaryModel
}

func summaryContents(report protocol.CallReport) []*genai.Content {
	var b strings.Builder
	b.WriteString("次の電話の会話から、家族に向けたまとめを作ってください。\n\n# 会話\n")
	if len(report.Utterances) == 0 {
		b.WriteString("（発話はない）\n")
	}
	for _, utterance := range report.Utterances {
		fmt.Fprintf(&b, "%s（受話器を上げてから %d ミリ秒）: %s\n", utterance.Speaker, utterance.OffsetMs, utterance.Text)
	}
	return []*genai.Content{genai.NewContentFromText(b.String(), genai.RoleUser)}
}

func summaryConfig() *genai.GenerateContentConfig {
	return &genai.GenerateContentConfig{
		SystemInstruction:  genai.NewContentFromText(summaryInstruction, genai.RoleUser),
		ResponseMIMEType:   "application/json",
		ResponseJsonSchema: summarySchema,
	}
}

// dropUnmatchedQuotes は、見守る方の発話にそのまま含まれない本人の言葉を空にする。
// かぎかっこと前後の空白は、比べるときだけ除く。
func dropUnmatchedQuotes(draft *summaryDraft, utterances []protocol.Utterance) {
	var watched []string
	for _, utterance := range utterances {
		if utterance.Speaker == protocol.SpeakerWatched {
			watched = append(watched, utterance.Text)
		}
	}
	if !quoteAppears(draft.Quote.Text, watched) {
		draft.Quote.Text = ""
	}
	for _, item := range []*summaryToday{&draft.Meal, &draft.Sleep, &draft.Health} {
		if !quoteAppears(item.Quote, watched) {
			item.Quote = ""
		}
	}
}

func quoteAppears(quote string, utterances []string) bool {
	needle := normalizeQuote(quote)
	if needle == "" {
		return true
	}
	for _, utterance := range utterances {
		if strings.Contains(normalizeQuote(utterance), needle) {
			return true
		}
	}
	return false
}

func normalizeQuote(text string) string {
	text = strings.Map(func(r rune) rune {
		switch r {
		case '「', '」', '『', '』':
			return -1
		default:
			return r
		}
	}, text)
	return strings.Trim(text, " \t\n\r\u3000")
}
