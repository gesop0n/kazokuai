"""英語の Markdown を plamo-translate で日本語に訳す。

使い方: mise run translate <英語のファイル> <日本語のファイル>

段落ごとに plamo-translate の MCP サーバーへ送る。コードブロック、HTML のタグだけの行、
テンプレートの見出しと値、`Closes #12` のような行は訳さずに残す。
"""

import json
import re
import sys
import urllib.error
import urllib.request

URL = "http://localhost:30000/mcp"

# 訳すと ADR と PR のテンプレートの形が崩れる語。見出し、段落の全体、行の先頭の太字のラベルで残す
KEEP_TERMS = {
    "Status", "Context", "Decision", "Consequences", "Pros", "Cons",
    "Proposed", "Accepted", "Rejected", "Deprecated",
    "Summary", "Evidence", "Merge Danger",
    "Before", "After", "Door", "Blast Radius", "one-way", "two-way",
}

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^(#{1,6}\s+)(.*)$")
HTML_TAG_LINE = re.compile(r"^\s*</?[A-Za-z][^>]*>\s*$")
# GitHub がこの形の行を読んで issue を閉じるので、英語のまま残す
CLOSING_LINE = re.compile(r"^\s*(Closes|Fixes|Resolves) #\d+")
LABEL_LINE = re.compile(r"^(\s*(?:[-*+]\s+|\d+\.\s+)?)\*\*([^*]+):\*\*(\s*)(.*)$")
TABLE_SEPARATOR = re.compile(r"^\|?(\s*:?-+:?\s*\|)+\s*:?-*:?\s*$")


def split_blocks(text):
    """空行で区切った段落と、コードブロックに分ける。(コードブロックかどうか, 中身) の組を返す。"""
    blocks = []
    current = []
    fence = None
    for line in text.splitlines():
        if fence:
            current.append(line)
            if line.strip().startswith(fence):
                blocks.append((True, "\n".join(current)))
                current, fence = [], None
            continue
        match = FENCE.match(line)
        if match:
            if current:
                blocks.append((False, "\n".join(current)))
            current, fence = [line], match.group(1)
            continue
        if line.strip():
            current.append(line)
        elif current:
            blocks.append((False, "\n".join(current)))
            current = []
    if current:
        # 閉じていないコードブロックも訳さない
        blocks.append((fence is not None, "\n".join(current)))
    return blocks


def is_kept_line(line):
    return bool(HTML_TAG_LINE.match(line) or CLOSING_LINE.match(line)) or line.strip() in KEEP_TERMS


def translate_line(line, translate):
    if not line.strip() or is_kept_line(line):
        return line
    heading = HEADING.match(line)
    if heading:
        prefix, body = heading.groups()
        return line if body.strip() in KEEP_TERMS else prefix + translate(body).strip()
    label = LABEL_LINE.match(line)
    if label and label.group(2) in KEEP_TERMS:
        prefix, name, space, rest = label.groups()
        if rest.strip() in KEEP_TERMS or not rest.strip():
            return line
        return f"{prefix}**{name}:**{space}{translate(rest).strip()}"
    indent = line[: len(line) - len(line.lstrip())]
    return indent + translate(line.strip()).strip()


def translate_table(block, translate):
    lines = []
    for line in block.splitlines():
        if TABLE_SEPARATOR.match(line.strip()):
            lines.append(line)
            continue
        cells = line.strip().strip("|").split("|")
        out = []
        for cell in cells:
            text = cell.strip()
            if not text or (text.startswith("`") and text.endswith("`")):
                out.append(f" {text} ")
            else:
                out.append(f" {translate(text).strip()} ")
        lines.append("|" + "|".join(out) + "|")
    return "\n".join(lines)


def translate_block(block, translate):
    lines = block.splitlines()
    if all(line.lstrip().startswith("|") for line in lines):
        return translate_table(block, translate)
    if all(is_kept_line(line) for line in lines):
        return block
    # 見出しと、残す行やラベルを含む段落は、行ごとに訳して残す部分を守る
    if any(HEADING.match(line) or is_kept_line(line) or LABEL_LINE.match(line) for line in lines):
        return "\n".join(translate_line(line, translate) for line in lines)
    return translate(block).strip()


def translate_markdown(text, translate):
    out = []
    for is_code, block in split_blocks(text):
        out.append(block if is_code else translate_block(block, translate))
    return "\n\n".join(out) + "\n"


class PlamoClient:
    def __init__(self, url=URL):
        self.url = url
        self.session_id = None
        self.next_id = 1

    def _post(self, payload):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        request = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=600) as response:
            self.session_id = response.headers.get("Mcp-Session-Id") or self.session_id
            body = response.read().decode()
        messages = [json.loads(line[len("data: "):]) for line in body.splitlines() if line.startswith("data: ")]
        if not messages and body.strip().startswith("{"):
            messages.append(json.loads(body))
        return messages

    def _request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        messages = self._post({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        result = next(m for m in messages if m.get("id") == request_id)
        if "error" in result:
            raise RuntimeError(result["error"])
        return result["result"]

    def connect(self):
        self._request("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "kazokuai-translate", "version": "0"},
        })
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def translate(self, text):
        result = self._request("tools/call", {"name": "plamo-translate", "arguments": {
            "request": {
                "messages": [{"role": "user", "content": text}],
                "source_language": "English",
                "target_language": "Japanese",
            },
            "stream": False,
        }})
        return (result.get("structuredContent") or {}).get("result") or result["content"][0]["text"]


def main(argv):
    if len(argv) != 3:
        sys.exit("使い方: mise run translate <英語のファイル> <日本語のファイル>")
    with open(argv[1]) as f:
        text = f.read()
    client = PlamoClient()
    try:
        client.connect()
    except (urllib.error.URLError, ConnectionError) as error:
        sys.exit(f"plamo-translate のサーバー({URL})につながらない: {error}\n"
                 "訳すのをやめて、人に plamo-translate のサーバーを起動してもらう。")
    translated = translate_markdown(text, client.translate)
    with open(argv[2], "w") as f:
        f.write(translated)


if __name__ == "__main__":
    main(sys.argv)
