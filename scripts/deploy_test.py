import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from contextlib import contextmanager
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
WEB_SENTINEL = "kazokuai-web-build"
HOSTING_DIR = ROOT / "firebase" / "hosting"

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
        self._fake("gcloud", self.gcloud_log, gcloud=True)
        self._fake("terraform", self.terraform_log, terraform=True)
        self._fake("flutter", self.flutter_log)
        self._fake("firebase", self.firebase_log)

    def tearDown(self):
        self.tmp.cleanup()

    def _fake(self, name, log, terraform=False, gcloud=False):
        path = self.bin / name
        extra = ""
        if gcloud:
            extra = (
                "describe=0\n"
                'for arg in "$@"; do\n'
                '  if [ "$arg" = "describe" ]; then describe=1; fi\n'
                "done\n"
                'if [ "$describe" = 1 ]; then\n'
                '  if [ "${FAKE_GCLOUD_DESCRIBE_STATUS:-0}" != 0 ]; then\n'
                '    echo "not found" >&2\n'
                '    exit "${FAKE_GCLOUD_DESCRIBE_STATUS}"\n'
                "  fi\n"
                "  printf '%s\\n' 'https://kazokuai-example.run.app'\n"
                "fi\n"
            )
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
            "if [ -f hosting/index.html ]; then\n"
            "  printf 'HOSTING_INDEX=%s\\n' \"$(cat hosting/index.html)\" >> "
            f"{sh_quote(log)}\n"
            "fi\n"
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
        env["FAKE_GCLOUD_DESCRIBE_STATUS"] = "0"
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

    def gcloud_invocations(self):
        text = self.gcloud_log.read_text(encoding="utf-8")
        blocks = []
        for chunk in text.split("---"):
            args = [
                line
                for line in chunk.splitlines()
                if line and not line.startswith(("PWD=", "GOOGLE_", "CLOUDSDK_"))
            ]
            if args:
                blocks.append(args)
        return blocks

    def test_backend_without_project_does_not_call_tools(self):
        result = self.run_script(BACKEND)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_backend_rejects_terraform_flags(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            f"--billing-account={BILLING}",
            f"--state-bucket={BUCKET}",
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_backend_builds_amd64_and_deploys_that_image(self):
        result = self.run_script(BACKEND, f"--project={PROJECT}")
        self.assertEqual(result.returncode, 0, result.stderr)
        docker = self.docker_log.read_text(encoding="utf-8")
        gcloud = self.gcloud_log.read_text(encoding="utf-8")
        image = re.search(re.escape(IMAGE_PREFIX) + r"\S+", docker)
        self.assertIsNotNone(image, docker)
        image = image.group(0)
        self.assertIn("--platform", docker)
        self.assertIn("linux/amd64", docker)
        self.assertIn("push", docker)
        self.assertIn(image, docker)
        self.assertFalse(self.terraform_log.exists())
        self.assertNotIn(AMBIENT, docker + gcloud)
        self.assertNotIn(BILLING, docker + gcloud + result.stdout)
        self.assertIn(f"CLOUDSDK_CORE_PROJECT={PROJECT}", gcloud)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", gcloud)
        invocations = self.gcloud_invocations()
        self.assertEqual(invocations[0][:2], ["auth", "configure-docker"], gcloud)
        self.assertEqual(invocations[1][:3], ["run", "services", "describe"], gcloud)
        self.assertIn(f"--project={PROJECT}", invocations[1])
        self.assertIn(f"--region={REGION}", invocations[1])
        self.assertEqual(invocations[2][:3], ["run", "deploy", "kazokuai"], gcloud)
        deploy = invocations[2]
        self.assertIn(f"--project={PROJECT}", deploy)
        self.assertIn(f"--region={REGION}", deploy)
        self.assertIn(f"--image={image}", deploy)
        self.assertIn("--quiet", deploy)
        for flag in (
            "--set-env-vars",
            "--update-env-vars",
            "--set-secrets",
            "--tag",
            "--allow-unauthenticated",
            "--clear-env-vars",
        ):
            self.assertNotIn(flag, gcloud)
        self.assertNotIn("config", invocations[0])
        self.assertIn(image, result.stdout)
        self.assertIn("https://kazokuai-example.run.app", result.stdout)
        self.assertFalse(self.flutter_log.exists())
        self.assertFalse(self.firebase_log.exists())

    def test_backend_stops_when_the_service_is_missing(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            FAKE_GCLOUD_DESCRIBE_STATUS="1",
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("infra:apply", result.stderr)
        self.assertIn("push", self.docker_log.read_text(encoding="utf-8"))
        flat = [arg for block in self.gcloud_invocations() for arg in block]
        self.assertIn("describe", flat)
        self.assertNotIn("deploy", flat)
        self.assertFalse(self.terraform_log.exists())

    def test_backend_uses_the_given_region_in_the_image(self):
        result = self.run_script(
            BACKEND,
            f"--project={PROJECT}",
            "--region=asia-northeast2",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        docker = self.docker_log.read_text(encoding="utf-8")
        self.assertIn(
            "asia-northeast2-docker.pkg.dev/kazokuai-prod/kazokuai/backend:",
            docker,
        )
        deploy = self.gcloud_invocations()[2]
        self.assertIn("--region=asia-northeast2", deploy)

    def test_web_without_project_does_not_call_tools(self):
        result = self.run_script(WEB, f"--state-bucket={BUCKET}")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_web_builds_with_terraform_output_and_deploys_that_project(self):
        with staged_web_build():
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

    def test_web_deploys_the_build_from_inside_the_firebase_directory(self):
        config = json.loads((ROOT / "firebase" / "firebase.json").read_text(encoding="utf-8"))
        public = config["hosting"]["public"]
        firebase_dir = (ROOT / "firebase").resolve()
        public_dir = (firebase_dir / public).resolve()
        self.assertEqual(public, "hosting")
        self.assertTrue(public_dir.is_relative_to(firebase_dir), public)
        self.assertIn("firebase/hosting/", (ROOT / ".gitignore").read_text(encoding="utf-8"))

        with staged_web_build():
            result = self.run_script(WEB, f"--project={PROJECT}", f"--state-bucket={BUCKET}")
            self.assertEqual(result.returncode, 0, result.stderr)
            firebase = self.firebase_log.read_text(encoding="utf-8")
            self.assertIn(f"HOSTING_INDEX={WEB_SENTINEL}", firebase)
            self.assertTrue(any(line.startswith("PWD=") and line.endswith("/firebase") for line in firebase.splitlines()))
            self.assertEqual((HOSTING_DIR / "index.html").read_text(encoding="utf-8"), WEB_SENTINEL)
            self.assertEqual((HOSTING_DIR / "assets" / "app.js").read_text(encoding="utf-8"), "app")
            self.assertFalse((HOSTING_DIR / "stale.txt").exists())

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

    def test_web_direct_firebase_flags_skip_terraform(self):
        with staged_web_build():
            result = self.run_script(WEB, f"--project={PROJECT}", *firebase_flags())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.terraform_log.exists())
        self.assertFalse(self.docker_log.exists())
        flutter = self.flutter_log.read_text(encoding="utf-8")
        firebase = self.firebase_log.read_text(encoding="utf-8")
        self.assertIn("FIREBASE_API_KEY=test-api-key", flutter)
        self.assertIn("FIREBASE_STORAGE_BUCKET=", flutter)
        self.assertIn("--dart-define=FIREBASE_STORAGE_BUCKET=", flutter.splitlines())
        self.assertIn(f"--project={PROJECT}", firebase)
        self.assertIn("hosting:kazokuai", firebase)
        self.assertNotIn(AMBIENT, flutter + firebase)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", firebase)
        self.assertIn("Web 版: https://kazokuai.web.app\n", result.stdout)
        self.assertNotIn("test-api-key", result.stdout)
        self.assertNotIn("電話機がつなぐ URL", result.stdout)

    def test_web_rejects_mixing_state_bucket_and_firebase_flags(self):
        result = self.run_script(
            WEB,
            f"--project={PROJECT}",
            f"--state-bucket={BUCKET}",
            *firebase_flags(),
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_web_rejects_firebase_flags_that_are_missing_a_value(self):
        result = self.run_script(WEB, f"--project={PROJECT}", "--firebase-api-key=test-api-key")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assert_untouched()

    def test_web_direct_stops_when_the_firebase_project_differs(self):
        flags = [
            "--firebase-project-id=other-project" if item.startswith("--firebase-project-id=") else item
            for item in firebase_flags()
        ]
        result = self.run_script(WEB, f"--project={PROJECT}", *flags)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.flutter_log.exists())
        self.assertFalse(self.firebase_log.exists())
        self.assertFalse(self.terraform_log.exists())

    def test_cloud_run_ignores_the_image_and_prevents_deletion(self):
        text = (ROOT / "infra" / "run.tf").read_text(encoding="utf-8")
        self.assertIn("template[0].containers[0].image", text)
        self.assertIn("client_version", text)
        self.assertIn('deletion_policy = "PREVENT"', text)
        self.assertNotIn("prevent_destroy", text)
        hosting = (ROOT / "infra" / "firebase.tf").read_text(encoding="utf-8")
        self.assertEqual(hosting.count('deletion_policy = "PREVENT"'), 2)
        self.assertIn("site_id  = var.project_id", hosting)
        self.assertIn("site_id  = var.hosting_site_id", hosting)
        self.assertNotIn("prevent_destroy", hosting)

    def test_workload_identity_accepts_only_this_repo_on_main(self):
        text = (ROOT / "infra" / "github.tf").read_text(encoding="utf-8")
        self.assertIn("gesop0n/kazokuai", text)
        self.assertIn("refs/heads/main", text)
        self.assertIn("assertion.ref_type == 'branch'", text)
        self.assertIn("repo:gesop0n@133982741/kazokuai@1446577671:ref:refs/heads/main", text)
        self.assertIn("roles/artifactregistry.writer", text)
        self.assertIn("roles/run.developer", text)
        self.assertIn("roles/iam.serviceAccountUser", text)
        self.assertIn("roles/firebasehosting.admin", text)
        self.assertIn("roles/iam.workloadIdentityUser", text)
        self.assertNotRegex(text, r'resource\s+"google_service_account_key"')
        self.assertNotIn("private_key", text)
        for forbidden in (
            "roles/editor",
            "roles/owner",
            "roles/run.admin",
            "roles/iam.serviceAccountTokenCreator",
        ):
            self.assertNotIn(f'"{forbidden}"', text)
        outputs = (ROOT / "infra" / "outputs.tf").read_text(encoding="utf-8")
        self.assertIn("google_iam_workload_identity_pool_provider.github.name", outputs)
        self.assertIn("google_service_account.deploy.email", outputs)
        services = (ROOT / "infra" / "locals.tf").read_text(encoding="utf-8")
        self.assertIn("iamcredentials.googleapis.com", services)
        self.assertIn("sts.googleapis.com", services)
        bootstrap = (ROOT / "infra" / "run.sh").read_text(encoding="utf-8")
        self.assertNotIn("google_iam_workload_identity_pool.github", bootstrap)
        self.assertNotIn("google_cloud_run_v2_service_iam_member.deploy", bootstrap)

    def test_deploy_workflow_is_manual_and_checks_first(self):
        text = (ROOT / ".github" / "workflows" / "deploy.yml").read_text(encoding="utf-8")
        trigger = text.split("on:", 1)[1].split("permissions:", 1)[0]
        self.assertIn("workflow_dispatch", trigger)
        self.assertNotIn("pull_request", trigger)
        self.assertNotIn("push", trigger)
        self.assertNotIn("secrets.", text)
        self.assertIn("id-token: write", text)
        self.assertIn("contents: read", text)
        check = text.index("mise run check")
        auth = text.index("google-github-actions/auth@")
        backend = text.index("mise run deploy:backend")
        web = text.index("mise run deploy:web")
        self.assertLess(check, auth)
        self.assertLess(auth, backend)
        self.assertLess(backend, web)
        self.assertIn('github.ref == \'refs/heads/main\'', text)

    def test_publish_says_what_the_person_runs_once(self):
        text = (ROOT / "docs" / "publish.md").read_text(encoding="utf-8")
        step7 = text.split("## 7.", 1)[1].split("## 8.", 1)[0]
        self.assertIn("gcloud run deploy", step7)
        self.assertNotIn("Terraform を適用し", step7)
        once = text.split("## 12.", 1)[1].split("## Cloud Run", 1)[0]
        self.assertIn("deletion_policy", once)
        self.assertIn("PREVENT", once)
        self.assertIn("gh variable set", once)
        self.assertIn("WORKLOAD_IDENTITY_PROVIDER", once)
        self.assertIn("DEPLOY_SERVICE_ACCOUNT", once)
        apply = once.split("```bash", 1)[1].split("```", 1)[0]
        self.assertIn("infra:apply", apply)
        self.assertNotIn("--bootstrap", apply)
        self.assertNotIn("--allow-replace", apply)
        tainted = text.split("## Cloud Run が tainted", 1)[1]
        self.assertIn("PREVENT", tainted)
        self.assertIn("deletion_policy", tainted)
        self.assertNotIn("deploy:backend` の apply", tainted)


def firebase_flags():
    return [
        "--firebase-api-key=test-api-key",
        "--firebase-auth-domain=kazokuai-prod.firebaseapp.com",
        "--firebase-app-id=1:1:web:abc",
        "--firebase-messaging-sender-id=123",
        f"--firebase-project-id={PROJECT}",
        "--firebase-storage-bucket=",
    ]


def sh_quote(path):
    return "'" + str(path).replace("'", "'\\''") + "'"


@contextmanager
def staged_web_build():
    """本物の Flutter のビルドを脇へよけ、公開のテスト用の小さなビルドを置く。"""
    web = ROOT / "mobile" / "build" / "web"
    backup = web.with_name("web.deploy-test-backup")
    if backup.exists():
        raise RuntimeError(f"退避先が既にある: {backup}")
    moved = web.exists()
    if moved:
        web.rename(backup)
    web.mkdir(parents=True)
    (web / "index.html").write_text(WEB_SENTINEL, encoding="utf-8")
    (web / "assets").mkdir()
    (web / "assets" / "app.js").write_text("app", encoding="utf-8")
    HOSTING_DIR.mkdir(parents=True, exist_ok=True)
    (HOSTING_DIR / "stale.txt").write_text("stale", encoding="utf-8")
    try:
        yield web
    finally:
        if HOSTING_DIR.exists():
            shutil.rmtree(HOSTING_DIR)
        if web.exists():
            shutil.rmtree(web)
        if moved:
            backup.rename(web)


if __name__ == "__main__":
    unittest.main()
