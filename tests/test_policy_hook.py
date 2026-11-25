import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).resolve().parents[1] / "hooks" / "20-policy.sh"


class PolicyHookTest(unittest.TestCase):
    def run_hook(self, policy_exit=0, deny_push=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            log = root / "calls"
            policy = root / "bin" / "sbx-github-policy"
            policy.write_text(f'#!/bin/sh\nprintf "github-policy\\n" >> "$LOG"\nexit {policy_exit}\n')
            policy.chmod(0o755)
            sbx = root / "sbx"
            sbx.write_text('#!/bin/sh\nprintf "sbx %s\\n" "$*" >> "$LOG"\n')
            sbx.chmod(0o755)
            env = {
                **os.environ,
                "SBX_DIR": str(root),
                "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
                "LOG": str(log),
                "SBX_GLOBAL_DENY_PUSH": "1" if deny_push else "0",
            }
            result = subprocess.run(["bash", str(HOOK)], env=env, capture_output=True, text=True)
            return result, log.read_text().splitlines()

    def test_default_policy_allows_network_after_github_restrictions(self):
        result, calls = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["github-policy", "sbx policy allow network **"])

    def test_github_restrictions_precede_open_network(self):
        result, calls = self.run_hook(deny_push=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [
            "github-policy",
            "sbx policy deny network github.com --method POST --path /**/git-receive-pack",
            "sbx policy allow network **",
        ])

    def test_failed_github_policy_does_not_open_network(self):
        result, calls = self.run_hook(policy_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, ["github-policy"])


if __name__ == "__main__":
    unittest.main()
