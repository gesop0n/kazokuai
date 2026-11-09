import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "pi-release.yml"
PUBLISH = ROOT / "device" / "pi" / "publish_release.sh"
BUILD = ROOT / "device" / "pi" / "bookworm-build.sh"
README = ROOT / "device" / "pi" / "README.md"
TASKS = ROOT / "mise-tasks.toml"

SHA = "0123456789abcdef0123456789abcdef01234567"


class PiReleaseTest(unittest.TestCase):
    def test_workflow_builds_on_bookworm_arm_and_check_lints_it(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("ubuntu-24.04-arm", workflow)
        self.assertIn("debian:bookworm", workflow)
        self.assertIn("pi-release", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("device/pi/bookworm-build.sh", workflow)
        self.assertIn("device/pi/publish_release.sh", workflow)
        tasks = TASKS.read_text(encoding="utf-8")
        self.assertIn("check:actions", tasks)
        self.assertIn("actionlint", tasks)
        self.assertIn("device:install", tasks)
        build = BUILD.read_text(encoding="utf-8")
        self.assertIn("CGO_ENABLED=1", build)
        self.assertIn("go1.27.3", build)
        self.assertIn("a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49", build)

    def test_readme_has_rebuild_steps(self):
        text = README.read_text(encoding="utf-8")
        for phrase in [
            "Raspberry Pi Imager",
            "17 / 27 / 22 / 23",
            "24 / 25 / 4",
            "PAM8012",
            "10kΩ",
            "1kΩ",
            "8Ω",
            "journalctl",
            "pi-release",
            "早送り",
            "debian:bookworm",
            "ubuntu-24.04-arm",
            "cgo",
            "PowerShell",
            "sha256",
            "/etc/kazokuai/device.env",
            "device:install",
            "電話回線",
        ]:
            self.assertIn(phrase, text, phrase)
        self.assertNotIn("dev-phone-secret", text)
        self.assertNotIn("dtoverlay", text)
        self.assertNotIn("PWM", text)
        self.assertNotIn("pwm", text)

    def test_publish_creates_prerelease_named_by_short_sha(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / "gh.log"
            write_gh(root / "bin" / "gh", log, view_code=1)
            (root / "kazokuai-device").write_bytes(b"\x7fELF")
            (root / "kazokuai-device.sha256").write_text("abc  kazokuai-device\n", encoding="utf-8")
            result = run_publish(root, log)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = log.read_text(encoding="utf-8")
            self.assertIn("release\ncreate\n", text)
            self.assertIn(f"pi-{SHA}\n", text)
            self.assertIn("--prerelease\n", text)
            self.assertIn(f"--target\n{SHA}\n", text)
            self.assertIn("--title\n0123456\n", text)
            self.assertIn("kazokuai-device\n", text)
            self.assertIn("kazokuai-device.sha256\n", text)
            self.assertNotIn("\nupload\n", text)

    def test_publish_replaces_assets_when_release_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / "gh.log"
            write_gh(root / "bin" / "gh", log, view_code=0)
            (root / "kazokuai-device").write_bytes(b"\x7fELF")
            (root / "kazokuai-device.sha256").write_text("abc  kazokuai-device\n", encoding="utf-8")
            result = run_publish(root, log)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = log.read_text(encoding="utf-8")
            self.assertIn("\nupload\n", text)
            self.assertIn("--clobber\n", text)
            self.assertNotIn("\ncreate\n", text)

    def test_bookworm_build_refuses_other_arch_before_apt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            apt_log = root / "apt.log"
            uname = bin_dir / "uname"
            uname.write_text("#!/bin/sh\necho x86_64\n", encoding="utf-8")
            uname.chmod(uname.stat().st_mode | stat.S_IEXEC)
            apt = bin_dir / "apt-get"
            apt.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' \"$@\" >> {sh_quote(apt_log)}\n"
                "exit 99\n",
                encoding="utf-8",
            )
            apt.chmod(apt.stat().st_mode | stat.S_IEXEC)
            env = os.environ.copy()
            env["PATH"] = str(bin_dir)
            result = subprocess.run(
                ["/bin/bash", str(BUILD)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("arm64", result.stderr)
            self.assertFalse(apt_log.exists())


def run_publish(root, log):
    env = os.environ.copy()
    env["PATH"] = f"{root / 'bin'}{os.pathsep}/bin{os.pathsep}/usr/bin"
    env["GITHUB_SHA"] = SHA
    env["GITHUB_REPOSITORY"] = "gesop0n/kazokuai"
    env["GH_TOKEN"] = "test-token"
    return subprocess.run(
        ["bash", str(PUBLISH)],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def write_gh(path, log, view_code):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$@\" >> {sh_quote(log)}\n"
        f"printf '%s\\n' --- >> {sh_quote(log)}\n"
        f"if [ \"$1\" = release ] && [ \"$2\" = view ]; then\n"
        f"  exit {view_code}\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def sh_quote(path):
    return "'" + str(path).replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
