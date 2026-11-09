import os
import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "scripts" / "deploy_backend.sh"
WEB = ROOT / "scripts" / "deploy_web.sh"

PROJECT = "kazokuai-prod"
BILLING = "ABCDEF-123456-ABCDEF"
BUCKET = "kazokuai-tfstate"
AMBIENT = "other-default-project"
REGION = "asia-northeast1"
IMAGE_PREFIX = f"{REGION}-docker.pkg.dev/{PROJECT}/kazokuai/backend:"

TF_JSON = """{
  "firebase_api_key": {"value": "test-api-key"},
  "firebase_auth_domain": {"value": "kazokuai-prod.firebaseapp.com"},
  "firebase_project_id": {"value": "kazokuai-prod"},
  "firebase_app_id": {"value": "1:1:web:abc"},
  "firebase_messaging_sender_id": {"value": "123"},
  "firebase_storage_bucket": {"value": ""},
  "hosting_url": {"value": "https://kazokuai.web.app"},
  "cloud_run_uri": {"value": "https://kazokuai-example.run.app"},
  "cloud_run_region": {"value": "asia-northeast1"},
  "cloud_run_service": {"value": "kazokuai"}
}"""


class DeployScriptTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.docker_log = root / "docker.log"
        self.gcloud_log = root / "gcloud.log"
        self.terraform_log = root / "terraform.log"
        self.flutter_log = root / "flutter.log"
        self.firebase_log = root / "firebase.log"
        self._fake("docker", self.docker_log)
        self._fake("gcloud", self.gcloud_log)
        self._fake("terraform", self.terraform_log, terraform=True)
        self._fake("flutter", self.flutter_log)
        self._fake("firebase", self.firebase_log)

    def tearDown(self):
        self.tmp.cleanup()

    def _fake(self, name, log, terraform=False):
        path = self.bin / name
        extra = ""
        if terraform:
            extra = (
                'output=0; json=0; raw=0\n'
                'for arg in "$@"; do\n'
                '  if [ "$arg" = "output" ]; then output=1; fi\n'
                '  if [ "$arg" = "-json" ]; then json=1; fi\n'
                '  if [ "$arg" = "-raw" ]; then raw=1; fi\n'
                "done\n"
                'if [ "$output" = 1 ] && [ "$json" = 1 ]; then\n'
                '  printf "%s\\n" "$FAKE_TF_JSON"\n'
                "fi\n"
                'if [ "$output" = 1 ] && [ "$raw" = 1 ]; then\n'
                '  printf "%s\\n" "$FAKE_TF_RAW"\n'
                "fi\n"
            )
        path.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$@\" >> {sh_quote(log)}\n"
            "printf 'PWD=%s\\n' \"$PWD\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_PROJECT=%s\\n' \"$GOOGLE_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_CLOUD_PROJECT=%s\\n' \"$GOOGLE_CLOUD_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'CLOUDSDK_CORE_PROJECT=%s\\n' \"$CLOUDSDK_CORE_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_BILLING_PROJECT=%s\\n' \"$GOOGLE_BILLING_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf '%s\\n' '---' >> "
            f"{sh_quote(log)}\n"
            + extra
            + "exit 0\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def env(self, **extra):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin}{os.pathsep}{env.get('PATH', '')}"
        env["GOOGLE_PROJECT"] = AMBIENT
        env["GOOGLE_CLOUD_PROJECT"] = AMBIENT
        env["CLOUDSDK_CORE_PROJECT"] = AMBIENT
        env["GOOGLE_BILLING_PROJECT"] = AMBIENT
        env["TF_VAR_project_id"] = AMBIENT
        env["FAKE_TF_JSON"] = TF_JSON
        env["FAKE_TF_RAW"] = "https://kazokuai-example.run.app"
        env.update(extra)
        return env

    def run_script(self, script, *args, **extra):
        return subprocess.run(
            ["bash", str(script), *args],
            env=self.env(**extra),
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_untouched(self):
        for log in (
            self.docker_log,
            self.gcloud_log,
            self.terraform_log,
            self.flutter_log,
            self.firebase_log,
        ):
            self.assertFalse(log.exists(), log.name)

    def test_backend_without_project_does_not_call_tools(self):
        result = self.run_script(
            BACKEND,
            f"--billing-account={BILLING}",
            f"--state-bucket={BUCKET}",
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_backend_rejects_ambient_project_name_in_the_bucket(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            f"--billing-account={BILLING}",
            "--state-bucket=gs://bucket",
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_backend_builds_amd64_and_applies_that_image(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            f"--billing-account={BILLING}",
            f"--state-bucket={BUCKET}",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        docker = self.docker_log.read_text(encoding="utf-8")
        terraform = self.terraform_log.read_text(encoding="utf-8")
        gcloud = self.gcloud_log.read_text(encoding="utf-8")
        image = re.search(re.escape(IMAGE_PREFIX) + r"\S+", docker)
        self.assertIsNotNone(image, docker)
        image = image.group(0)
        self.assertIn("--platform", docker)
        self.assertIn("linux/amd64", docker)
        self.assertIn("push", docker)
        self.assertIn(image, docker)
        self.assertIn(f"-var=container_image={image}", terraform)
        self.assertIn(f"-var=project_id={PROJECT}", terraform)
        self.assertIn(f"-var=billing_account={BILLING}", terraform)
        self.assertIn(f"-backend-config=bucket={BUCKET}", terraform)
        self.assertIn("apply", terraform)
        self.assertNotIn("-target=", terraform)
        self.assertNotIn("deletion_protection=false", terraform)
        self.assertNotIn("-auto-approve", terraform)
        self.assertNotIn(AMBIENT, docker + terraform + gcloud)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", terraform)
        self.assertIn(f"CLOUDSDK_CORE_PROJECT={PROJECT}", gcloud)
        gcloud_args = [
            line
            for line in gcloud.split("---")[0].splitlines()
            if line and not line.startswith(("PWD=", "GOOGLE_", "CLOUDSDK_"))
        ]
        self.assertEqual(
            gcloud_args[:2],
            ["auth", "configure-docker"],
            gcloud,
        )
        self.assertNotIn("config", gcloud_args)
        self.assertIn(image, result.stdout)
        self.assertIn("https://kazokuai-example.run.app", result.stdout)
        self.assertFalse(self.flutter_log.exists())
        self.assertFalse(self.firebase_log.exists())

    def test_backend_uses_the_given_region_in_the_image(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            f"--billing-account={BILLING}",
            f"--state-bucket={BUCKET}",
            "--region=asia-northeast2",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        docker = self.docker_log.read_text(encoding="utf-8")
        self.assertIn(
            "asia-northeast2-docker.pkg.dev/kazokuai-prod/kazokuai/backend:",
            docker,
        )

    def test_web_without_project_does_not_call_tools(self):
        result = self.run_script(WEB, f"--state-bucket={BUCKET}")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_web_builds_with_terraform_output_and_deploys_that_project(self):
        result = self.run_script(WEB, f"--project={PROJECT}", f"--state-bucket={BUCKET}")
        self.assertEqual(result.returncode, 0, result.stderr)
        terraform = self.terraform_log.read_text(encoding="utf-8")
        flutter = self.flutter_log.read_text(encoding="utf-8")
        firebase = self.firebase_log.read_text(encoding="utf-8")
        self.assertIn(f"-backend-config=bucket={BUCKET}", terraform)
        self.assertIn("output", terraform)
        self.assertIn("-json", terraform)
        self.assertIn("KAZOKUAI_TARGET=production", flutter)
        self.assertIn("FIREBASE_API_KEY=test-api-key", flutter)
        self.assertIn("FIREBASE_APP_ID=1:1:web:abc", flutter)
        self.assertIn("FIREBASE_MESSAGING_SENDER_ID=123", flutter)
        self.assertIn(f"FIREBASE_PROJECT_ID={PROJECT}", flutter)
        self.assertIn("FIREBASE_AUTH_DOMAIN=kazokuai-prod.firebaseapp.com", flutter)
        self.assertIn("build", flutter)
        self.assertIn("web", flutter)
        self.assertTrue(any(line.startswith("PWD=") and line.endswith("/mobile") for line in flutter.splitlines()))
        self.assertIn(f"--project={PROJECT}", firebase)
        self.assertIn("hosting", firebase)
        self.assertIn("--non-interactive", firebase)
        self.assertTrue(any(line.startswith("PWD=") and line.endswith("/firebase") for line in firebase.splitlines()))
        self.assertNotIn(AMBIENT, terraform + flutter + firebase)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", terraform)
        self.assertIn("hosting:kazokuai", firebase)
        self.assertIn("Web 版: https://kazokuai.web.app\n", result.stdout)
        self.assertNotIn("test-api-key", result.stdout)
        self.assertFalse(self.docker_log.exists())

    def test_web_stops_when_output_project_differs(self):
        result = self.run_script(
            WEB,
            f"--project={PROJECT}",
            f"--state-bucket={BUCKET}",
            FAKE_TF_JSON=TF_JSON.replace(
                '"firebase_project_id": {"value": "kazokuai-prod"}',
                '"firebase_project_id": {"value": "other-project"}',
                1,
            ),
        )
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.flutter_log.exists())
        self.assertFalse(self.firebase_log.exists())

    def test_web_stops_when_hosting_url_is_not_the_firebase_json_site(self):
        result = self.run_script(
            WEB,
            f"--project={PROJECT}",
            f"--state-bucket={BUCKET}",
            FAKE_TF_JSON=TF_JSON.replace(
                '"hosting_url": {"value": "https://kazokuai.web.app"}',
                '"hosting_url": {"value": "https://kazokuai-prod.web.app"}',
                1,
            ),
        )
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://kazokuai.web.app", result.stderr)
        self.assertFalse(self.flutter_log.exists())
        self.assertFalse(self.firebase_log.exists())

    def test_web_stops_when_the_region_is_not_the_hosting_rewrite(self):
        result = self.run_script(
            WEB,
            f"--project={PROJECT}",
            f"--state-bucket={BUCKET}",
            "--region=asia-northeast2",
        )
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assert_untouched()

    def test_dockerignore_keeps_env_out_of_the_image(self):
        text = (ROOT / ".dockerignore").read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^\.env$")

    def test_cloud_run_env_matches_the_backend(self):
        text = (ROOT / "infra" / "run.tf").read_text(encoding="utf-8")
        self.assertIn('name = "PHONE_SECRET"', text)
        self.assertNotIn("PHONE_SHARED_SECRET", text)


def sh_quote(path):
    return "'" + str(path).replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
