#!/usr/bin/env python3
"""スナップショットに、秘密の形をした文字列がないかを調べる。

見つかったファイルの名前だけを出す。値は出さない。
.github の workflow は、push の前にこれを実行する。
"""

import os
import re
import sys
from pathlib import Path


def main(argv):
    if len(argv) != 2:
        print("使い方: scan_secrets.py DIRECTORY", file=sys.stderr)
        return 2
    root = Path(argv[1])
    if not root.is_dir():
        print("調べるディレクトリがありません。", file=sys.stderr)
        return 2
    found = scan(root)
    for name in found:
        print(name, file=sys.stderr)
    return 1 if found else 0


def scan(root):
    google, headers, github = patterns()
    found = []
    for path in files(root):
        data = path.read_bytes()
        if secret(data, google, headers, github):
            found.append(path.relative_to(root).as_posix())
    return found


def files(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for name in filenames:
            path = Path(dirpath) / name
            if path.is_symlink() or not path.is_file():
                continue
            found.append(path)
    return sorted(found)


def secret(data, google, headers, github):
    if google.search(data):
        return True
    if any(header in data for header in headers):
        return True
    return any(pattern.search(data) for pattern in github)


def patterns():
    # 接頭辞は実行時に結ぶ。このファイル自身がパターンに一致しないようにする。
    google = re.compile(b"AI" + b"za" + b"[0-9A-Za-z_\\-]{35}")
    begin = b"-----BEGIN "
    headers = [
        begin + tail
        for tail in (
            b"PRIVATE KEY-----",
            b"RSA PRIVATE KEY-----",
            b"OPENSSH PRIVATE KEY-----",
            b"EC PRIVATE KEY-----",
            b"DSA PRIVATE KEY-----",
            b"ENCRYPTED PRIVATE KEY-----",
            b"PGP PRIVATE KEY BLOCK-----",
        )
    ]
    github = [
        re.compile((b"gh" + prefix) + b"[A-Za-z0-9]{36}")
        for prefix in (b"p_", b"o_", b"u_", b"r_")
    ]
    github.append(re.compile(b"gh" + b"s_" + b"[A-Za-z0-9.\\-_]{36,}"))
    github.append(
        re.compile(b"github_" + b"pat_" + b"[A-Za-z0-9]{22}_[A-Za-z0-9]{59}")
    )
    return google, headers, github


if __name__ == "__main__":
    sys.exit(main(sys.argv))
