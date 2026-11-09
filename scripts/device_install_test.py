import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "device_install.sh"
ENV_EXAMPLE = ROOT / "device" / "pi" / "device.env"
UNIT = ROOT / "device" / "pi" / "kazokuai-device.service"

# linux/arm64 の ELF ヘッダ。e_machine は EM_AARCH64 (0xB7)。
ARM64_ELF = bytes(
    [
        0x7F,
        0x45,
        0x4C,
        0x46,
        0x02,
        0x01,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x02,
        0x00,
        0xB7,
        0x00,
    ]
)
# e_machine が EM_X86_64 (0x3E) のヘッダ。
AMD64_ELF = bytes(ARM64_ELF[:18] + bytes([0x3E, 0x00]))


class DeviceInstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.dest = root / "root"
        self.go_log = root / "go.log"
        self.systemctl_log = root / "systemctl.log"
        self.sudo_log = root / "sudo.log"
        self._fake_go()
        self._fake_systemctl()
        self._fake_sudo()
        gcc = self.bin / "gcc"
        gcc.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        gcc.chmod(gcc.stat().st_mode | stat.S_IEXEC)

    def tearDown(self):
        self.tmp.cleanup()

    def _fake_go(self):
        path = self.bin / "go"
        path.write_text(
            "#!/bin/sh\n"
            f"printf 'CGO_ENABLED=%s\\n' \"$CGO_ENABLED\" >> {sh_quote(self.go_log)}\n"
            f"printf 'GOOS=%s\\n' \"$GOOS\" >> {sh_quote(self.go_log)}\n"
            f"printf 'GOARCH=%s\\n' \"$GOARCH\" >> {sh_quote(self.go_log)}\n"
            f"printf '%s\\n' \"$@\" >> {sh_quote(self.go_log)}\n"
            f"printf '%s\\n' --- >> {sh_quote(self.go_log)}\n"
            "out=\n"
            "prev=\n"
            "for arg in \"$@\"; do\n"
            "  if [ \"$prev\" = \"-o\" ]; then\n"
            "    out=$arg\n"
            "  fi\n"
            "  prev=$arg\n"
            "done\n"
            "if [ -z \"$out\" ]; then\n"
            "  echo 'go fake: -o がありません' >&2\n"
            "  exit 1\n"
            "fi\n"
            "mkdir -p \"$(dirname \"$out\")\"\n"
            "printf '\\177ELF\\002\\001\\001\\000\\000\\000\\000\\000\\000\\000\\000\\000\\002\\000\\267\\000' > \"$out\"\n"
            "exit 0\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _fake_systemctl(self):
        path = self.bin / "systemctl"
        path.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$@\" >> {sh_quote(self.systemctl_log)}\n"
            f"printf '%s\\n' --- >> {sh_quote(self.systemctl_log)}\n"
            "exit 0\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _fake_sudo(self):
        path = self.bin / "sudo"
        path.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$@\" >> {sh_quote(self.sudo_log)}\n"
            "exit 99\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def env(self):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin}{os.pathsep}/bin{os.pathsep}/usr/bin"
        env["DEVICE_INSTALL_ROOT"] = str(self.dest)
        env.pop("CC", None)
        return env

    def run_install(self, *args):
        return subprocess.run(
            ["bash", str(INSTALL), *args],
            env=self.env(),
            capture_output=True,
            text=True,
            check=False,
        )

    def test_given_binary_skips_build_and_does_not_start_without_person(self):
        binary = Path(self.tmp.name) / "kazokuai-device"
        binary.write_bytes(ARM64_ELF)

        result = self.run_install(str(binary))

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(self.go_log.exists())
        self.assertFalse(self.systemctl_log.exists())
        self.assertFalse(self.sudo_log.exists())
        installed = self.dest / "usr" / "local" / "bin" / "kazokuai-device"
        self.assertEqual(installed.read_bytes(), ARM64_ELF)
        self.assertTrue(os.access(installed, os.X_OK))
        unit = (self.dest / "etc" / "systemd" / "system" / "kazokuai-device.service").read_text(
            encoding="utf-8"
        )
        self.assertEqual(unit, UNIT.read_text(encoding="utf-8"))
        self.assertIn("EnvironmentFile=/etc/kazokuai/device.env", unit)
        self.assertIn("Restart=on-failure", unit)
        self.assertIn("WantedBy=multi-user.target", unit)
        self.assertIn("/usr/local/bin/kazokuai-device", unit)
        env_text = (self.dest / "etc" / "kazokuai" / "device.env").read_text(encoding="utf-8")
        self.assertEqual(env_text, ENV_EXAMPLE.read_text(encoding="utf-8"))
        self.assertIn("見守る方の ID", result.stderr)

    def test_build_uses_cgo_when_no_binary_is_given(self):
        result = self.run_install()

        self.assertEqual(result.returncode, 1, result.stderr)
        log = self.go_log.read_text(encoding="utf-8")
        self.assertIn("CGO_ENABLED=1\n", log)
        self.assertIn("\nbuild\n", "\n" + log)
        self.assertIn("./device\n", log)
        self.assertIn("GOARCH=arm64", log)
        installed = self.dest / "usr" / "local" / "bin" / "kazokuai-device"
        self.assertEqual(installed.read_bytes()[:4], b"\x7fELF")
        self.assertFalse(self.systemctl_log.exists())

    def test_starts_service_when_watched_person_is_set_and_keeps_env(self):
        env_dir = self.dest / "etc" / "kazokuai"
        env_dir.mkdir(parents=True)
        env_file = env_dir / "device.env"
        original = (
            "KAZOKUAI_BACKEND=http://10.0.0.8:8080\n"
            "KAZOKUAI_WATCHED_PERSON=test-person\n"
            "PHONE_SECRET=kept-value\n"
        )
        env_file.write_text(original, encoding="utf-8")
        binary = Path(self.tmp.name) / "prebuilt"
        binary.write_bytes(ARM64_ELF + b"prebuilt")

        result = self.run_install(str(binary))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(env_file.read_text(encoding="utf-8"), original)
        self.assertFalse(self.go_log.exists())
        self.assertFalse(self.sudo_log.exists())
        log = self.systemctl_log.read_text(encoding="utf-8")
        self.assertEqual(
            log,
            "daemon-reload\n---\nenable\nkazokuai-device.service\n---\nrestart\nkazokuai-device.service\n---\n",
        )
        self.assertNotIn("test-person", log)
        self.assertNotIn("kept-value", log)
        installed = self.dest / "usr" / "local" / "bin" / "kazokuai-device"
        self.assertEqual(installed.read_bytes(), ARM64_ELF + b"prebuilt")

    def test_refuses_non_arm64_binary(self):
        binary = Path(self.tmp.name) / "amd64"
        binary.write_bytes(AMD64_ELF)

        result = self.run_install(str(binary))

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse((self.dest / "usr" / "local" / "bin" / "kazokuai-device").exists())
        self.assertFalse(self.systemctl_log.exists())

    def test_missing_binary_exits_1(self):
        result = self.run_install(str(Path(self.tmp.name) / "missing"))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.go_log.exists())

    def test_extra_args_and_help_exit_2(self):
        binary = Path(self.tmp.name) / "kazokuai-device"
        binary.write_bytes(ARM64_ELF)
        extra = self.run_install(str(binary), str(binary))
        self.assertEqual(extra.returncode, 2, extra.stderr)
        self.assertFalse(self.dest.exists())
        help_result = self.run_install("--help")
        self.assertEqual(help_result.returncode, 2, help_result.stderr)

    def test_example_env_has_defaults_and_no_secret_or_id(self):
        text = ENV_EXAMPLE.read_text(encoding="utf-8")
        values = assignments(text)
        self.assertEqual(values["KAZOKUAI_BACKEND"], "http://localhost:8080")
        self.assertEqual(values["KAZOKUAI_WATCHED_PERSON"], "")
        self.assertEqual(values["PHONE_SECRET"], "")
        self.assertEqual(
            {key: values[key] for key in (
                "KAZOKUAI_AUDIO_DEVICE",
                "KAZOKUAI_MIC_CHANNEL",
                "KAZOKUAI_SPEAKER_GAIN",
                "KAZOKUAI_SPEAKER_LIMIT",
                "KAZOKUAI_GPIO_CHIP",
                "KAZOKUAI_HOOK_GPIO",
                "KAZOKUAI_RINGER_GPIO",
                "KAZOKUAI_LIFTED_WHEN_CLOSED",
                "KAZOKUAI_HOOK_DEBOUNCE",
            )},
            {
                "KAZOKUAI_AUDIO_DEVICE": "",
                "KAZOKUAI_MIC_CHANNEL": "0",
                "KAZOKUAI_SPEAKER_GAIN": "0.15",
                "KAZOKUAI_SPEAKER_LIMIT": "0.1",
                "KAZOKUAI_GPIO_CHIP": "gpiochip0",
                "KAZOKUAI_HOOK_GPIO": "5",
                "KAZOKUAI_RINGER_GPIO": "18",
                "KAZOKUAI_LIFTED_WHEN_CLOSED": "true",
                "KAZOKUAI_HOOK_DEBOUNCE": "50ms",
            },
        )
        self.assertNotIn("dev-phone-secret", text)


def assignments(text):
    found = {}
    for line in text.splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        found[key] = value
    return found


def sh_quote(path):
    return "'" + str(path).replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
