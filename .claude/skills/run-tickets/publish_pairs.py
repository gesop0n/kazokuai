"""Upload the app–mock pairs to the pr-images branch, for a PR body to show them.

uv run --with pillow python3 publish_pairs.py <ticket> <shots-dir> <id>...

For each screen id, this scales <shots-dir>/<id>.png to WIDTH pixels wide and
puts it at <ticket>/<id>.png on the pr-images branch of the repository that gh
points at. The branch shares no history with main, so the images stay out of
main. The first run creates it. This prints one Markdown image line per id.
"""

import base64
import io
import json
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image

BRANCH = "pr-images"
WIDTH = 1000


def gh(*args: str, body: dict | None = None) -> dict:
    cmd = ["gh", "api", *args]
    with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
        if body is not None:
            # The images are too large for command-line arguments
            json.dump(body, f)
            f.flush()
            cmd += ["--input", f.name]
        out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {out.stderr.strip()}")
    return json.loads(out.stdout) if out.stdout.strip() else {}


def exists(path: str) -> str | None:
    out = subprocess.run(["gh", "api", path, "--jq", ".sha"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def create_branch(repo: str) -> None:
    readme = "Images that PR bodies show. This branch shares no history with main.\n"
    blob = gh(f"repos/{repo}/git/blobs", "-X", "POST", body={"content": readme, "encoding": "utf-8"})
    tree = gh(f"repos/{repo}/git/trees", "-X", "POST",
              body={"tree": [{"path": "README.md", "mode": "100644", "type": "blob", "sha": blob["sha"]}]})
    commit = gh(f"repos/{repo}/git/commits", "-X", "POST",
                body={"message": "PR の本文に載せる画像の置き場を作る", "tree": tree["sha"], "parents": []})
    gh(f"repos/{repo}/git/refs", "-X", "POST", body={"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})


def scaled(path: pathlib.Path) -> bytes:
    image = Image.open(path).convert("RGB")
    if image.width > WIDTH:
        image = image.resize((WIDTH, round(image.height * WIDTH / image.width)))
    out = io.BytesIO()
    image.save(out, "PNG", optimize=True)
    return out.getvalue()


def main() -> None:
    ticket, shots, ids = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3:]
    repo = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
                          capture_output=True, text=True, check=True).stdout.strip()
    if exists(f"repos/{repo}/branches/{BRANCH}") is None:
        create_branch(repo)
    for screen_id in ids:
        pair = shots / f"{screen_id}.png"
        if not pair.exists():
            print(f"{screen_id}: no pair at {pair}", file=sys.stderr)
            continue
        path = f"{ticket}/{screen_id}.png"
        body = {"message": f"#{ticket} の {screen_id} の見比べ", "branch": BRANCH,
                "content": base64.b64encode(scaled(pair)).decode()}
        sha = exists(f"repos/{repo}/contents/{path}?ref={BRANCH}")
        if sha:
            body["sha"] = sha
        gh(f"repos/{repo}/contents/{path}", "-X", "PUT", body=body)
        print(f"![{screen_id}](https://github.com/{repo}/blob/{BRANCH}/{path}?raw=true)")


if __name__ == "__main__":
    main()
