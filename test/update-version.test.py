#!/usr/bin/env python3
"""Server update checks must never depend on player releases."""

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "script"))
SPEC = importlib.util.spec_from_file_location("update_version", ROOT / "script/update-version.py")
UPDATER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATER)


class ServerUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.paths = []
        for platform in ("entware", "openwrt"):
            path = self.root / platform / "songloft/Makefile"
            path.parent.mkdir(parents=True)
            content = (ROOT / platform / "songloft/Makefile").read_text(encoding="utf-8")
            content = UPDATER.replace_assignment(content, "PKG_VERSION", "2.13.6")
            path.write_text(UPDATER.replace_assignment(content, "PKG_RELEASE", "3"), encoding="utf-8")
            self.paths.append(path)
        self.before = [path.read_text(encoding="utf-8") for path in self.paths]
        self.output = self.root / "github-output"

    def run_update(self, version="2.13.9", arguments=(), hash_error=None):
        def metadata(endpoint, directory):
            if endpoint == UPDATER.SERVER + "/tags?per_page=100&page=1":
                return [{"name": "v" + version}, {"name": "v99.0.0-rc1"}]
            if endpoint == UPDATER.SERVER + "/contents/pkg/tag?ref=v" + version:
                return {"type": "submodule", "submodule_git_url": "https://github.com/hanxi/tag.git",
                        "sha": "a" * 40}
            self.fail("Unexpected API request: " + endpoint)

        with patch.object(UPDATER, "ROOT", self.root), \
                patch.object(UPDATER, "api_json", side_effect=metadata) as api, \
                patch.object(UPDATER, "archive_hash", side_effect=hash_error,
                             return_value="b" * 64) as archive, \
                patch.dict(os.environ, {"GITHUB_OUTPUT": str(self.output)}), \
                patch.object(sys, "argv", ["update-version.py"] + list(arguments)):
            UPDATER.main()
        return api, archive

    def test_server_upgrade_succeeds_without_any_player_request(self):
        api, archive = self.run_update()
        self.assertEqual(api.call_count, 2)
        self.assertEqual(archive.call_count, 2)
        for path, before in zip(self.paths, self.before):
            content = path.read_text(encoding="utf-8")
            self.assertIn("PKG_VERSION:=2.13.9\n", content)
            self.assertIn("PKG_RELEASE:=1\n", content)
            self.assertEqual([line for line in content.splitlines() if line.startswith("SONGLOFT_WEB_")],
                             [line for line in before.splitlines() if line.startswith("SONGLOFT_WEB_")])
        self.assertIn("upgrade_ready=true\n", self.output.read_text(encoding="utf-8"))

    def test_same_server_version_skips_resources_and_builds(self):
        api, archive = self.run_update(version="2.13.6")
        self.assertEqual(api.call_count, 1)
        archive.assert_not_called()
        self.assertEqual([path.read_text(encoding="utf-8") for path in self.paths], self.before)
        self.assertIn("upgrade_ready=false\n", self.output.read_text(encoding="utf-8"))

    def test_older_server_does_not_downgrade(self):
        _, archive = self.run_update(version="2.13.5")
        archive.assert_not_called()
        self.assertEqual([path.read_text(encoding="utf-8") for path in self.paths], self.before)

    def test_forced_same_version_preserves_packaging_revision(self):
        self.run_update(version="2.13.6", arguments=("2.13.6",))
        for path in self.paths:
            self.assertIn("PKG_RELEASE:=3\n", path.read_text(encoding="utf-8"))
        self.assertIn("upgrade_ready=false\n", self.output.read_text(encoding="utf-8"))

    def test_download_failure_does_not_write_packages(self):
        with self.assertRaises(OSError):
            self.run_update(hash_error=OSError("download failed"))
        self.assertEqual([path.read_text(encoding="utf-8") for path in self.paths], self.before)
        self.assertFalse(self.output.exists())

    def test_invalid_second_package_does_not_partially_update_first(self):
        self.paths[1].write_text(self.before[1].replace("PKG_HASH:=", "MISSING_HASH:="), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.run_update()
        self.assertEqual(self.paths[0].read_text(encoding="utf-8"), self.before[0])
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
