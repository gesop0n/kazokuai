import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "infra" / "run.sh"

PROJECT = "kazokuai-prod"
BILLING = "ABCDEF-123456-ABCDEF"
IMAGE = "asia-northeast1-docker.pkg.dev/kazokuai-prod/kazokuai/backend:1"
BUCKET = "kazokuai-tfstate"
AMBIENT = "not-the-project"


class InfraRunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.terraform_log = root / "terraform.log"
        self.gcloud_log = root / "gcloud.log"
        self._fake("terraform", self.terraform_log, exit_code=0)
        self._fake("gcloud", self.gcloud_log, exit_code=99)

    def tearDown(self):
        self.tmp.cleanup()

    def _fake(self, name, log, exit_code):
        path = self.bin / name
        path.write_text(
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$@\" >> {sh_quote(log)}\n"
            "printf 'GOOGLE_PROJECT=%s\\n' \"$GOOGLE_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_CLOUD_PROJECT=%s\\n' \"$GOOGLE_CLOUD_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'CLOUDSDK_CORE_PROJECT=%s\\n' \"$CLOUDSDK_CORE_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_BILLING_PROJECT=%s\\n' \"$GOOGLE_BILLING_PROJECT\" >> "
            f"{sh_quote(log)}\n"
            "printf 'TF_VAR_project_id=%s\\n' \"$TF_VAR_project_id\" >> "
            f"{sh_quote(log)}\n"
            "printf 'TF_VAR_hosting_site_id=%s\\n' \"$TF_VAR_hosting_site_id\" >> "
            f"{sh_quote(log)}\n"
            "printf 'GOOGLE_APPLICATION_CREDENTIALS=%s\\n' "
            "\"$GOOGLE_APPLICATION_CREDENTIALS\" >> "
            f"{sh_quote(log)}\n"
            "printf '%s\\n' '---' >> "
            f"{sh_quote(log)}\n"
            f"exit {exit_code}\n",
            encoding="utf-8",
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def env(self):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin}{os.pathsep}{env.get('PATH', '')}"
        env["GOOGLE_PROJECT"] = AMBIENT
        env["GOOGLE_CLOUD_PROJECT"] = AMBIENT
        env["CLOUDSDK_CORE_PROJECT"] = AMBIENT
        env["GOOGLE_BILLING_PROJECT"] = AMBIENT
        env["TF_VAR_project_id"] = AMBIENT
        env["TF_VAR_hosting_site_id"] = AMBIENT
        env["GOOGLE_APPLICATION_CREDENTIALS"] = "/tmp/kazokuai-adc.json"
        return env

    def run_script(self, *args):
        return subprocess.run(
            ["bash", str(RUN), *args],
            env=self.env(),
            capture_output=True,
            text=True,
            check=False,
        )

    def test_missing_project_does_not_call_terraform(self):
        result = self.run_script(
            "plan",
            f"--billing-account={BILLING}",
            f"--image={IMAGE}",
            f"--state-bucket={BUCKET}",
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.terraform_log.exists())
        self.assertFalse(self.gcloud_log.exists())

    def test_no_args_exits_2(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.terraform_log.exists())

    def test_unknown_command_exits_2(self):
        result = self.run_script("destroy", f"--project={PROJECT}")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.terraform_log.exists())

    def test_rejects_blank_leading_dash_and_gs_prefix(self):
        cases = [
            ("--project=",),
            ("--project", "-kazokuai"),
            ("--project", "kazoku ai"),
            ("--project", PROJECT, "--state-bucket", "gs://bucket"),
            ("--project", PROJECT, "--state-bucket", "bucket/prefix"),
            ("--project", PROJECT, "--image", "image with space"),
            ("--billing-account", ""),
        ]
        for args in cases:
            with self.subTest(args=args):
                self.terraform_log.unlink(missing_ok=True)
                self.gcloud_log.unlink(missing_ok=True)
                result = self.run_script("plan", *pad(args))
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(self.terraform_log.exists(), args)

    def test_plan_passes_explicit_project_and_ignores_ambient(self):
        result = self.run_script("plan", *full_args())
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.terraform_log.read_text(encoding="utf-8")
        self.assertIn("-reconfigure", log)
        self.assertIn(f"-backend-config=bucket={BUCKET}", log)
        self.assertIn("-backend-config=prefix=kazokuai", log)
        self.assertIn("-var=project_id=" + PROJECT, log)
        self.assertIn("-var=region=asia-northeast1", log)
        self.assertIn("-var=billing_account=" + BILLING, log)
        self.assertIn("-var=container_image=" + IMAGE, log)
        self.assertNotIn("-auto-approve", log)
        self.assertNotIn(AMBIENT, log)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", log)
        self.assertIn(f"GOOGLE_PROJECT={PROJECT}", log)
        self.assertIn(f"CLOUDSDK_CORE_PROJECT={PROJECT}", log)
        self.assertIn(f"GOOGLE_BILLING_PROJECT={PROJECT}", log)
        self.assertIn("TF_VAR_project_id=\n", log)
        self.assertIn("TF_VAR_hosting_site_id=\n", log)
        self.assertIn("GOOGLE_APPLICATION_CREDENTIALS=/tmp/kazokuai-adc.json", log)
        self.assertFalse(self.gcloud_log.exists())
        self.assertEqual(log.split("---")[0].splitlines()[1], "init")

    def test_apply_uses_the_same_vars(self):
        result = self.run_script(
            "apply",
            "--project",
            PROJECT,
            "--billing-account",
            BILLING,
            "--image",
            IMAGE,
            "--state-bucket",
            BUCKET,
            "--region",
            "asia-northeast2",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.terraform_log.read_text(encoding="utf-8")
        self.assertIn("\napply\n", "\n" + log)
        self.assertIn("-var=region=asia-northeast2", log)
        self.assertNotIn("-target=", log)
        self.assertNotIn("deletion_protection=false", log)
        self.assertNotIn("-auto-approve", log)
        self.assertFalse(self.gcloud_log.exists())

    def test_bootstrap_apply_skips_cloud_run(self):
        result = self.run_script("apply", "--bootstrap", *full_args())
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.terraform_log.read_text(encoding="utf-8")
        apply = log.split("---")[1]
        for target in (
            "google_project_service.api",
            "google_artifact_registry_repository.backend",
            "google_secret_manager_secret.gemini_api_key",
            "google_secret_manager_secret.phone_shared_secret",
            "google_service_account.backend",
            "google_project_iam_member.backend_firestore",
            "google_secret_manager_secret_iam_member.backend_gemini",
            "google_secret_manager_secret_iam_member.backend_phone",
            "google_project_service_identity.run",
            "google_artifact_registry_repository_iam_member.run_reader",
            "google_firestore_database.default",
            "google_firestore_field.booking_task_pending",
            "google_firebaserules_ruleset.firestore",
            "google_firebaserules_release.firestore",
            "google_firebase_web_app.web",
            "google_firebase_hosting_site.web",
            "google_firebase_hosting_site.published",
            "google_billing_budget.monthly",
        ):
            self.assertIn(f"-target={target}", apply)
        self.assertNotIn("google_cloud_run_v2_service", log)
        self.assertNotIn("-auto-approve", log)
        self.assertNotIn(AMBIENT, log)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", log)

    def test_bootstrap_without_project_does_not_call_terraform(self):
        result = self.run_script("apply", "--bootstrap")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.terraform_log.exists())

    def test_bootstrap_and_allow_replace_do_not_call_terraform(self):
        result = self.run_script("apply", "--bootstrap", "--allow-replace", *full_args())
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.terraform_log.exists())

    def test_allow_replace_turns_deletion_protection_off(self):
        result = self.run_script("apply", "--allow-replace", *full_args())
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.terraform_log.read_text(encoding="utf-8")
        self.assertIn("-var=deletion_protection=false", log)
        self.assertNotIn("-target=", log)
        self.assertNotIn(AMBIENT, log)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", log)

    def test_untaint_uses_the_explicit_project(self):
        result = self.run_script(
            "untaint",
            f"--project={PROJECT}",
            f"--state-bucket={BUCKET}",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.terraform_log.read_text(encoding="utf-8")
        self.assertIn("\nuntaint\n", "\n" + log)
        self.assertIn("google_cloud_run_v2_service.backend", log)
        self.assertNotIn("\napply\n", "\n" + log)
        self.assertNotIn("-target=", log)
        self.assertNotIn(AMBIENT, log)
        self.assertIn(f"GOOGLE_CLOUD_PROJECT={PROJECT}", log)
        self.assertIn(f"-backend-config=bucket={BUCKET}", log)
        self.assertFalse(self.gcloud_log.exists())


def full_args():
    return (
        f"--project={PROJECT}",
        f"--billing-account={BILLING}",
        f"--image={IMAGE}",
        f"--state-bucket={BUCKET}",
    )


def pad(args):
    """不足している必須の引数を足して、調べたい引数だけが拒否の理由になるようにする。"""
    text = " ".join(args)
    extra = []
    if "--project" not in text:
        extra.extend(["--project", PROJECT])
    if "--billing-account" not in text:
        extra.extend(["--billing-account", BILLING])
    if "--image" not in text:
        extra.extend(["--image", IMAGE])
    if "--state-bucket" not in text:
        extra.extend(["--state-bucket", BUCKET])
    return (*args, *extra)


def sh_quote(path):
    return "'" + str(path).replace("'", "'\\''") + "'"


if __name__ == "__main__":
    unittest.main()
