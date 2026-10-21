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
    code = 1 if state.get("fail_info") else 0
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
        rules = Path(args[1]).read_text()
        if " to self port " in rules and state.get("native_rendering"):
            rules = state["native_rendering"]
        # macOS expands "self" to one rule per local IPv4 address.
        rendered = []
        for rule in rules.splitlines():
            if " to self port " in rule:
                for address in state.get("addresses", ["127.0.0.1", "192.0.2.10"]):
                    rendered.append(rule.replace("to self port ", "to " + address + " port = "))
            else:
                rendered.append(rule)
        if state.get("missing_ftp"):
            rendered = [rule for rule in rendered if "proto tcp" not in rule]
        if state.get("wrong_destination"):
            rendered = [rule.replace("port 5140", "port 5141") for rule in rendered]
        state["anchors"][anchor] = "\n".join(rendered) + "\n" if rendered else ""
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
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"].count("rdr pass"), 6)
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

    def test_expanded_rules_are_recognized_by_status(self):
        self.run_helper("enable")
        self.assertIn("SYSTFTP_PF_ENABLED", self.run_helper("status").stdout)

    def test_single_address_is_supported(self):
        self.configure(addresses=["192.0.2.10"])
        self.run_helper("enable")
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"].count("rdr pass"), 3)

    def test_missing_mapping_is_rolled_back(self):
        self.configure(missing_ftp=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["references"], [100])
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"], "")
        self.assert_other_services_unchanged()

    def test_incorrect_mapping_is_rolled_back(self):
        self.configure(wrong_destination=True)
        self.run_helper("enable", success=False)
        self.assertEqual(self.state()["references"], [100])
        self.assertEqual(self.state()["anchors"]["com.apple/SysTFTP"], "")
        self.assert_other_services_unchanged()

    def test_status_read_failure_is_not_reported_as_disabled(self):
        self.configure(fail_info=True)
        result = self.run_helper("status", success=False)
        self.assertNotIn("SYSTFTP_PF_DISABLED", result.stdout)
        self.assertIn("无法读取系统 PF 状态", result.stderr)

    def test_rule_read_failure_is_not_reported_as_disabled(self):
        self.configure(fail_backup=True)
        result = self.run_helper("status", success=False)
        self.assertNotIn("SYSTFTP_PF_DISABLED", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "Requires the macOS PF parser")
    def test_actual_macos_pf_rule_expansion(self):
        source = (PROJECT / "SysTFTP/Resources/port_forwarding.sh").read_text()
        rules = source.split("<<'RULES'\n", 1)[1].split("\nRULES", 1)[0]
        # -n only parses and prints rules; it never changes the system firewall.
        result = subprocess.run(
            ["/sbin/pfctl", "-a", "com.apple/SysTFTP", "-vnf", "-"],
            input=rules + "\n", text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(result.stdout.count("rdr pass"), 3)
        self.configure(native_rendering=result.stdout)
        self.run_helper("enable")
        self.assertIn("SYSTFTP_PF_ENABLED", self.run_helper("status").stdout)


if __name__ == "__main__":
    unittest.main()
