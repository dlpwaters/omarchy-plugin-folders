from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PLUGIN_DIR = Path(__file__).resolve().parents[1]
FOLDERCTL = PLUGIN_DIR / "folderctl"
SELF_ID = "io.github.dlpwaters.plugin-folders"


class FolderCtlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.shell = self.root / "shell.json"
        self.state = self.root / "state.json"
        self.manifests = self.root / "manifests"
        self.manifests.mkdir()

        self.write_manifest("test.alpha", "Alpha Tool")
        self.write_manifest("test.beta", "Beta Tool")
        self.write_manifest("test.gamma", "Gamma Tool")
        self.write_manifest("omarchy.weather", "Weather")
        self.write_shell(
            {
                "version": 1,
                "bar": {
                    "layout": {
                        "left": [
                            {"id": "omarchy.menu"},
                            {"id": "omarchy.workspaces"},
                            {"id": "test.alpha", "mode": "compact"},
                            {"id": "test.beta"},
                        ],
                        "center": [{"id": "test.gamma", "level": 7}],
                        "right": [{"id": "omarchy.weather"}],
                    }
                },
                "plugins": [],
            }
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "OMARCHY_PLUGIN_FOLDERS_SHELL_CONFIG": str(self.shell),
                "OMARCHY_PLUGIN_FOLDERS_STATE": str(self.state),
                "OMARCHY_PLUGIN_FOLDERS_MANIFEST_DIRS": str(self.manifests),
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_manifest(self, plugin_id: str, name: str) -> None:
        folder = self.manifests / plugin_id
        folder.mkdir()
        (folder / "manifest.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "id": plugin_id,
                    "name": name,
                    "version": "1.0.0",
                    "kinds": ["bar-widget"],
                    "entryPoints": {"barWidget": "BarWidget.qml"},
                    "barWidget": {"displayName": name, "category": "Test"},
                }
            ),
            encoding="utf-8",
        )

    def write_shell(self, value: dict) -> None:
        self.shell.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

    def read_shell(self) -> dict:
        return json.loads(self.shell.read_text(encoding="utf-8"))

    def run_ctl(self, *arguments: str, expect: int = 0) -> dict:
        result = subprocess.run(
            [str(FOLDERCTL), *arguments],
            check=False,
            capture_output=True,
            text=True,
            env=self.env,
        )
        self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def bootstrap(self) -> str:
        payload = self.run_ctl("bootstrap")
        return payload["result"]["id"]

    def test_bootstrap_is_idempotent_and_places_folder_after_workspaces(self) -> None:
        folder_id = self.bootstrap()
        second = self.run_ctl("bootstrap")
        self.assertEqual(second["result"]["id"], folder_id)
        left = self.read_shell()["bar"]["layout"]["left"]
        folder_entries = [entry for entry in left if entry.get("id") == SELF_ID]
        self.assertEqual(folder_entries, [{"id": SELF_ID, "folderId": folder_id}])
        self.assertEqual(left[2], folder_entries[0])

    def test_bootstrap_converts_generic_enabled_entry(self) -> None:
        shell = self.read_shell()
        shell["bar"]["layout"]["left"].insert(2, {"id": SELF_ID})
        self.write_shell(shell)
        folder_id = self.bootstrap()
        entries = [
            entry for entry in self.read_shell()["bar"]["layout"]["left"]
            if entry.get("id") == SELF_ID
        ]
        self.assertEqual(entries, [{"id": SELF_ID, "folderId": folder_id}])

    def test_assign_removes_bar_entry_keeps_plugin_enabled_and_preserves_settings(self) -> None:
        folder_id = self.bootstrap()
        member = self.run_ctl("assign", folder_id, "test.alpha")["result"]
        shell = self.read_shell()
        self.assertNotIn("test.alpha", [entry.get("id") for entry in shell["bar"]["layout"]["left"]])
        self.assertIn({"id": "test.alpha"}, shell["plugins"])
        self.assertEqual(member["entry"], {"id": "test.alpha", "mode": "compact"})
        self.assertEqual(member["section"], "left")

    def test_unassign_restores_original_entry_and_removes_temporary_keepalive(self) -> None:
        folder_id = self.bootstrap()
        self.run_ctl("assign", folder_id, "test.alpha")
        self.run_ctl("unassign", folder_id, "test.alpha")
        shell = self.read_shell()
        left = shell["bar"]["layout"]["left"]
        alpha = next(entry for entry in left if entry.get("id") == "test.alpha")
        self.assertEqual(alpha["mode"], "compact")
        self.assertNotIn("test.alpha", [entry.get("id") for entry in shell["plugins"]])
        self.assertLess(
            next(index for index, entry in enumerate(left) if entry.get("id") == "test.alpha"),
            next(index for index, entry in enumerate(left) if entry.get("id") == "test.beta"),
        )

    def test_preexisting_plugin_entry_is_not_removed_on_restore(self) -> None:
        shell = self.read_shell()
        shell["plugins"].append({"id": "test.beta", "keepLoaded": True})
        self.write_shell(shell)
        folder_id = self.bootstrap()
        self.run_ctl("assign", folder_id, "test.beta")
        self.run_ctl("unassign", folder_id, "test.beta")
        self.assertIn({"id": "test.beta", "keepLoaded": True}, self.read_shell()["plugins"])

    def test_plugin_cannot_be_assigned_twice(self) -> None:
        first = self.bootstrap()
        second = self.run_ctl("create", "Media", "󰝚", "#bb9af7", "--after", first)["result"]["id"]
        self.run_ctl("assign", first, "test.alpha")
        failure = self.run_ctl("assign", second, "test.alpha", expect=2)
        self.assertFalse(failure["ok"])
        self.assertIn("already assigned", failure["error"])

    def test_delete_restores_all_members_and_removes_only_that_folder(self) -> None:
        first = self.bootstrap()
        second = self.run_ctl("create", "Media", "󰝚", "#bb9af7", "--after", first)["result"]["id"]
        self.run_ctl("assign", first, "test.alpha")
        self.run_ctl("assign", first, "test.gamma")
        self.run_ctl("delete", first)
        shell = self.read_shell()
        all_ids = [entry.get("id") for section in ("left", "center", "right") for entry in shell["bar"]["layout"][section]]
        self.assertIn("test.alpha", all_ids)
        self.assertIn("test.gamma", all_ids)
        self.assertNotIn(first, [entry.get("folderId") for entry in shell["bar"]["layout"]["left"] if entry.get("id") == SELF_ID])
        self.assertIn(second, [entry.get("folderId") for entry in shell["bar"]["layout"]["left"] if entry.get("id") == SELF_ID])

    def test_restore_all_returns_everything_and_removes_folder_widgets(self) -> None:
        first = self.bootstrap()
        second = self.run_ctl("create", "Media", "󰝚", "#bb9af7", "--after", first)["result"]["id"]
        self.run_ctl("assign", first, "test.alpha")
        self.run_ctl("assign", second, "test.gamma")
        result = self.run_ctl("restore-all")["result"]
        self.assertEqual(set(result["restored"]), {"test.alpha", "test.gamma"})
        shell = self.read_shell()
        all_ids = [entry.get("id") for section in ("left", "center", "right") for entry in shell["bar"]["layout"][section]]
        self.assertNotIn(SELF_ID, all_ids)
        self.assertIn("test.alpha", all_ids)
        self.assertIn("test.gamma", all_ids)

    def test_update_reorder_catalog_and_doctor(self) -> None:
        folder_id = self.bootstrap()
        self.run_ctl("assign", folder_id, "test.alpha")
        self.run_ctl("assign", folder_id, "test.beta")
        self.run_ctl("reorder", folder_id, "test.beta", "0")
        folder = self.run_ctl(
            "update", folder_id, "--name", "Daily Tools", "--icon", "󰖷", "--color", "#73daca"
        )["result"]
        self.assertEqual(folder["name"], "Daily Tools")
        self.assertEqual(folder["members"][0]["id"], "test.beta")
        catalog = self.run_ctl("catalog")["result"]
        alpha = next(item for item in catalog["plugins"] if item["id"] == "test.alpha")
        self.assertEqual(alpha["assignedFolderId"], folder_id)
        self.assertTrue(self.run_ctl("doctor")["result"]["ok"])

    def test_structural_omarchy_widget_is_protected(self) -> None:
        folder_id = self.bootstrap()
        failure = self.run_ctl("assign", folder_id, "omarchy.weather", expect=2)
        self.assertIn("protected structural widget", failure["error"])
        self.assertIn("omarchy.weather", [entry.get("id") for entry in self.read_shell()["bar"]["layout"]["right"]])


if __name__ == "__main__":
    unittest.main()
