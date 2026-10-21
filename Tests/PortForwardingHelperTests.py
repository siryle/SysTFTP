"""Exercise the packaged helper against an isolated PF simulator, without sudo."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]

FAKE_PF = r'''
import json, os, sys
from pathlib import Path
state_file = Path(os.environ["PF_TEST_STATE"])
state = json.loads(state_file.read_text())
args = sys.argv[1:]
state["commands"].append(args)
anchor = None
if args[:1] == ["-a"]:
    anchor = args[1]
    args = args[2:]
result = ""
code = 0
if args == ["-s", "nat"]:
    result = state["main"] if anchor is None else state["anchors"].get(anchor, "")
    if anchor is not None and state.get("fail_backup"):
        code = 1
elif args == ["-s", "info"]:
    result = "Status: Enabled" if state["references"] else "Status: Disabled"
elif args == ["-s", "References"]:
    result = "\n".join(str(value) for value in state["references"])
elif args == ["-E"]:
    state["references"].append(200)
    result = "pf enabled\nToken : 200"
elif args[:1] == ["-X"]:
    state["references"].remove(int(args[1]))
elif args[:1] == ["-nf"]:
    code = 1 if state.get("syntax_error") else 0
elif args == ["-F", "nat"]:
    state["anchors"][anchor] = ""
elif args[:1] == ["-f"]:
    if state.get("fail_load"):
        state["fail_load"] = False
        code = 1
    elif anchor is None:
        state["main"] = Path(args[1]).read_text()
    else:
        state["anchors"][anchor] = Path(args[1]).read_text()
else:
    raise RuntimeError("Unexpected PF command: " + repr(sys.argv))
state_file.write_text(json.dumps(state))
if result:
    print(result, end="" if result.endswith("\n") else "\n")
sys.exit(code)
'''


class PortForwardingHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state_file = self.root / "pf.json"
        self.original = {
            "main": 'rdr-anchor "com.apple/*"\n',
            "anchors": {"com.apple/other-service": "unrelated rules"},
            "references": [100],
            "commands": [],
        }
        self.state_file.write_text(json.dumps(self.original))
        fake = self.root / "pfctl"
        fake.write_text("#!" + sys.executable + "\n" + FAKE_PF)
        fake.chmod(0o755)
        source = (PROJECT / "SysTFTP/Resources/port_forwarding.sh").read_text()
        # Substitute only the OS boundary; execute the production shell logic.
        source = source.replace("/sbin/pfctl", str(fake))
        source = source.replace("/var/run/systftp-pf", str(self.root / "runtime"))
        source = source.replace("/usr/bin/id -u", "printf 0")
        source = source.replace("/usr/bin/install -d -o root -g wheel", "/usr/bin/install -d")
        self.helper = self.root / "helper.sh"
        self.helper.write_text(source)
        self.environment = dict(os.environ, PF_TEST_STATE=str(self.state_file))

    def run_helper(self, action, success=True):
        result = subprocess.run(
            ["/bin/sh", str(self.helper), action],
            env=self.environment, text=True, capture_output=True,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def state(self):
        return json.loads(self.state_file.read_text())

    def configure(self, **values):
        state = self.state()
        state.update(values)
        self.state_file.write_text(json.dumps(state))

    def assert_other_services_unchanged(self):
        state = self.state()
        self.assertEqual(state["main"], self.original["main"])
        self.assertEqual(state["anchors"]["com.apple/other-service"], "unrelated rules")
        self.assertIn(100, state["references"])

    def test_enable_is_idempotent_and_scoped(self):
        self.assertIn("SYSTFTP_PF_ENABLED", self.run_helper("enable").stdout)
        self.run_helper("enable")
        self.assertEqual(self.state()["references"], [100, 200])
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"].count("rdr pass"), 3)
        self.assert_other_services_unchanged()
        self.assertFalse((self.root / "runtime/lock").exists())

    def test_disable_releases_only_our_rules_and_reference(self):
        self.run_helper("enable")
        self.assertIn("SYSTFTP_PF_DISABLED", self.run_helper("disable").stdout)
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"], "")
        self.assertEqual(self.state()["references"], [100])
        self.assert_other_services_unchanged()
        self.assertFalse((self.root / "runtime/token").exists())

    def test_custom_main_rules_are_not_replaced(self):
        self.configure(main="custom rules without an anchor")
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["main"], "custom rules without an anchor")
        self.assertEqual(self.state()["references"], [100])
        self.assertNotIn("com.apple/SysTFTP", self.state()["anchors"])

    def test_failed_load_rolls_back_and_releases_new_reference(self):
        self.configure(fail_load=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["references"], [100])
        self.assertEqual(self.state()["anchors"].get("com.apple/SysTFTP", ""), "")
        self.assert_other_services_unchanged()
        self.assertFalse((self.root / "runtime/token").exists())

    def test_syntax_error_changes_no_pf_state(self):
        self.configure(syntax_error=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["references"], [100])
        self.assertNotIn("com.apple/SysTFTP", self.state()["anchors"])
        self.assert_other_services_unchanged()

    def test_failed_backup_does_not_flush_existing_anchor(self):
        anchors = dict(self.original["anchors"], **{"com.apple/SysTFTP": "existing rules"})
        self.configure(anchors=anchors, fail_backup=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"], "existing rules")
        self.assertEqual(self.state()["references"], [100])
        self.assert_other_services_unchanged()

    def test_failed_reapply_preserves_existing_enable_reference(self):
        self.run_helper("enable")
        before = self.state()["anchors"]["com.apple/SysTFTP"]
        self.configure(fail_load=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["references"], [100, 200])
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"], before)
        self.assert_other_services_unchanged()

    def test_status_does_not_create_runtime_files(self):
        self.assertIn("SYSTFTP_PF_DISABLED", self.run_helper("status").stdout)
        self.assertFalse((self.root / "runtime").exists())
        self.assert_other_services_unchanged()


if __name__ == "__main__":
    unittest.main()
