import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "submit.yml"
SCRIPT = ROOT / "scripts" / "submit_snapshot.sh"
SCAN = ROOT / "scripts" / "scan_secrets.py"
PUBLISH = ROOT / "docs" / "publish.md"
LICENSE = ROOT / "LICENSE"

MESSAGE = "README を更新"
# 秘密の形ではない。値を出していないことの印にだけ使う。
TOKEN = "test-submission-token"


class SubmitSnapshotTest(unittest.TestCase):
    def test_workflow_is_manual_checks_first_and_hides_the_token(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        trigger = workflow.split("on:", 1)[1].split("permissions:", 1)[0]
        self.assertIn("workflow_dispatch", trigger)
        for forbidden in ("pull_request", "push", "schedule", "workflow_call"):
            self.assertNotIn(forbidden, trigger, forbidden)
        self.assertIn("refs/heads/main", workflow)
        self.assertIn("main 以外の ref では写しません。", workflow)
        check = workflow.index("mise run check")
        refuse = workflow.index("main 以外の ref では写しません。")
        copy = workflow.rindex("submit_snapshot.sh")
        self.assertLess(refuse, check)
        self.assertLess(check, copy)
        self.assertIn("Devfest-Hackathon-2026/df-2026-t086", workflow)
        self.assertIn("secrets.SUBMISSION_TOKEN", workflow)
        self.assertNotIn("echo $SUBMISSION_TOKEN", workflow)
        self.assertNotIn('echo "$SUBMISSION_TOKEN"', workflow)
        self.assertNotIn("set -x", workflow)
        self.assertIn("SUBMISSION_MESSAGE: ${{ inputs.message }}", workflow)
        self.assertNotIn("run: bash scripts/submit_snapshot.sh ${{", workflow)

        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("git archive HEAD", script)
        self.assertLess(
            script.index('rm -rf "$dest/.github/workflows"'),
            script.index("scan_secrets.py"),
        )
        self.assertIn("LICENSE", script)
        self.assertIn(".git", script)
        self.assertIn("scan_secrets.py", script)
        self.assertLess(script.index("scan_secrets.py"), script.index("push origin"))
        self.assertNotIn("set -x", script)
        self.assertNotIn("echo $SUBMISSION_TOKEN", script)
        self.assertNotIn('echo "$SUBMISSION_TOKEN"', script)
        self.assertIn("SUBMISSION_TOKEN がありません", script)
        self.assertIn("gh secret set SUBMISSION_TOKEN --repo gesop0n/kazokuai", script)

    def test_missing_token_fails_with_a_clear_message(self):
        env = clean_env()
        result = run_script("check-token", env)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("SUBMISSION_TOKEN がありません", result.stderr)
        self.assertIn("gh secret set SUBMISSION_TOKEN --repo gesop0n/kazokuai", result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_present_token_is_not_printed(self):
        env = clean_env()
        env["SUBMISSION_TOKEN"] = TOKEN
        result = run_script("check-token", env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(TOKEN, result.stdout)
        self.assertNotIn(TOKEN, result.stderr)

    def test_scan_names_a_file_with_a_fake_key_and_hides_the_value(self):
        google = google_api_key()
        private = private_key_header()
        github = github_token()
        fine = fine_grained_token()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root / "google.txt", "note\n" + google + "\n")
            write(root / "nested" / "private.pem", private + "\n")
            write(root / "github.txt", github + "\n")
            write(root / "fine.txt", fine + "\n")
            write(root / "ok.txt", "plain\n")
            result = run_scan(root)
            self.assertEqual(result.returncode, 1, result.stderr)
            for name in ("google.txt", "nested/private.pem", "github.txt", "fine.txt"):
                self.assertIn(name, result.stderr, name)
            self.assertNotIn("ok.txt", result.stderr)
            combined = result.stdout + result.stderr
            for value in (google, private, github, fine):
                self.assertNotIn(value, combined)

    def test_scan_accepts_a_clean_snapshot(self):
        planted = google_api_key()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root / "readme.txt", "公開の手順です。\n")
            write(root / "near.txt", near_misses())
            git_dir = root / ".git"
            git_dir.mkdir()
            write(git_dir / "config", planted + "\n")
            result = run_scan(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            combined = result.stdout + result.stderr
            self.assertNotIn(planted, combined)
            self.assertNotIn("config", combined)
            self.assertNotIn("near.txt", combined)

    def test_sync_replaces_tracked_files_and_keeps_license_and_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, bare, dest = repos(root)
            init_repo(
                source,
                {
                    "README.md": "from source\n",
                    "LICENSE": "source license\n",
                    "keep/nested.txt": "nested\n",
                },
            )
            write(source / "untracked.txt", "nope\n")
            init_repo(
                dest,
                {
                    "README.md": "old\n",
                    "LICENSE": "submission license\n",
                    "obsolete.txt": "gone\n",
                },
            )
            publish(dest, bare)
            old = rev(bare, "main")
            result = run_sync(source, dest)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(TOKEN, result.stdout + result.stderr)
            self.assertEqual(blob(bare, "main", "README.md"), "from source\n")
            self.assertEqual(blob(bare, "main", "keep/nested.txt"), "nested\n")
            self.assertEqual(blob(bare, "main", "LICENSE"), "submission license\n")
            self.assertIsNone(blob(bare, "main", "obsolete.txt"))
            self.assertIsNone(blob(bare, "main", "untracked.txt"))
            self.assertEqual(rev(bare, "main^"), old)
            self.assertEqual(subject(bare), MESSAGE)
            self.assertEqual(log_format(bare, "%an"), "github-actions[bot]")
            self.assertEqual(
                log_format(bare, "%ae"),
                "41898282+github-actions[bot]@users.noreply.github.com",
            )

    def test_sync_refuses_without_a_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, bare, dest = repos(Path(tmp))
            init_repo(source, {"README.md": "from source\n"})
            init_repo(dest, {"LICENSE": "submission license\n"})
            publish(dest, bare)
            old = rev(bare, "main")
            result = run_sync(source, dest, message=None)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SUBMISSION_MESSAGE", result.stderr)
            self.assertEqual(rev(bare, "main"), old)

    def test_sync_omits_github_workflows(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, bare, dest = repos(root)
            init_repo(
                source,
                {
                    "README.md": "from source\n",
                    "LICENSE": "source license\n",
                    ".github/workflows/submit.yml": "name: submit\n",
                    ".github/CODEOWNERS": "owned\n",
                },
            )
            init_repo(
                dest,
                {
                    "README.md": "old\n",
                    "LICENSE": "submission license\n",
                    ".github/workflows/old.yml": "name: old\n",
                },
            )
            publish(dest, bare)
            result = run_sync(source, dest)
            self.assertEqual(result.returncode, 0, result.stderr)
            names = tree_names(bare)
            self.assertIn(".github/CODEOWNERS", names)
            self.assertEqual(blob(bare, "main", ".github/CODEOWNERS"), "owned\n")
            self.assertFalse(any(name.startswith(".github/workflows/") for name in names))
            self.assertFalse((dest / ".github" / "workflows").exists())

    def test_sync_finishes_without_a_commit_when_nothing_changed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, bare, dest = repos(root)
            init_repo(
                source,
                {"README.md": "same\n", "LICENSE": "source license\n"},
            )
            init_repo(
                dest,
                {"README.md": "same\n", "LICENSE": "submission license\n"},
            )
            publish(dest, bare)
            old = rev(bare, "main")
            result = run_sync(source, dest)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("変更はないので、コミットしません。", result.stdout)
            self.assertEqual(rev(bare, "main"), old)
            self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_sync_does_not_push_when_a_snapshot_contains_a_secret(self):
        secret = google_api_key()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, bare, dest = repos(root)
            init_repo(
                source,
                {
                    "README.md": "from source\n",
                    "LICENSE": "source license\n",
                    "notes/leak.txt": "prefix\n" + secret + "\nsuffix\n",
                },
            )
            init_repo(dest, {"README.md": "old\n", "LICENSE": "keep\n"})
            publish(dest, bare)
            old = rev(bare, "main")
            local = rev(dest, "HEAD")
            result = run_sync(source, dest)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("notes/leak.txt", result.stderr)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertNotIn(TOKEN, result.stdout + result.stderr)
            self.assertEqual(rev(bare, "main"), old)
            self.assertEqual(rev(dest, "HEAD"), local)

    def test_publish_explains_the_hand_run_and_the_token(self):
        text = PUBLISH.read_text(encoding="utf-8")
        section = text.split("## 13.", 1)[1].split("\n## ", 1)[0]
        self.assertIn("Devfest-Hackathon-2026/df-2026-t086", section)
        self.assertIn("workflow_dispatch", section)
        self.assertIn("mise run check", section)
        self.assertIn("git archive HEAD", section)
        self.assertIn(".github/workflows/", section)
        self.assertIn("Workflows", section)
        self.assertIn("Contents の読み書き", section)
        self.assertIn("gh secret set SUBMISSION_TOKEN --repo gesop0n/kazokuai", section)
        self.assertIn("読み取り専用", section)
        self.assertIn("SUBMISSION_MESSAGE", section)

    def test_repository_license_matches_the_submission(self):
        text = LICENSE.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("MIT License\n"))
        self.assertIn("Copyright (c) 2026 The contributors of this repository\n", text)
        self.assertIn("Permission is hereby granted, free of charge,", text)


def google_api_key():
    alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
    body = "".join(alphabet[i % len(alphabet)] for i in range(35))
    return "AI" + "za" + body


def private_key_header():
    return "-----BEGIN " + "PRIVATE KEY-----"


def github_token():
    return "gh" + "p_" + ("Ab" * 18)


def fine_grained_token():
    return "github_" + "pat_" + ("c" * 22) + "_" + ("d" * 59)


def near_misses():
    lines = [
        "AI" + "za" + "short",
        "-----BEGIN " + "PUBLIC KEY-----",
        "gh" + "p_" + "short",
        "github_" + "pat_" + "short",
        "AI" + "za" + "[0-9A-Za-z_-]{10,}",
        "SUBMISSION_TOKEN",
    ]
    return "\n".join(lines) + "\n"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def clean_env():
    env = os.environ.copy()
    for name in ("SUBMISSION_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"):
        env.pop(name, None)
    return env


def run_script(arg, env):
    return subprocess.run(
        ["bash", str(SCRIPT), arg],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def run_scan(root):
    return subprocess.run(
        ["python3", "-I", str(SCAN), str(root)],
        capture_output=True,
        text=True,
        check=False,
    )


def run_sync(source, dest, message=MESSAGE):
    env = clean_env()
    env["SUBMISSION_TOKEN"] = TOKEN
    env["SOURCE_DIR"] = str(source)
    env["SUBMISSION_DIR"] = str(dest)
    if message is not None:
        env["SUBMISSION_MESSAGE"] = message
    return subprocess.run(
        ["bash", str(SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def repos(root):
    return root / "source", root / "origin.git", root / "submission"


def init_repo(path, files):
    path.mkdir(parents=True)
    git("init", "-b", "main", str(path))
    for name, content in files.items():
        write(path / name, content)
    git("-C", str(path), "add", "-A")
    git("-C", str(path), "commit", "-m", "init")


def publish(path, bare):
    git("init", "--bare", "-b", "main", str(bare))
    git("-C", str(path), "remote", "add", "origin", str(bare))
    git("-C", str(path), "push", "-u", "origin", "main")


def git(*args):
    result = subprocess.run(
        [
            "git",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            *args,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return result


def rev(repo, spec):
    if (repo / "HEAD").exists() or (repo / "config").exists() and (repo / "objects").exists():
        result = subprocess.run(
            ["git", "--git-dir", str(repo), "rev-parse", spec],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", spec],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def blob(bare, revspec, path):
    result = subprocess.run(
        ["git", "--git-dir", str(bare), "show", f"{revspec}:{path}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def tree_names(bare):
    result = subprocess.run(
        ["git", "--git-dir", str(bare), "ls-tree", "-r", "--name-only", "main"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def subject(bare):
    return log_format(bare, "%s")


def log_format(bare, fmt):
    result = subprocess.run(
        ["git", "--git-dir", str(bare), "log", "-1", f"--format={fmt}", "main"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


if __name__ == "__main__":
    unittest.main()
