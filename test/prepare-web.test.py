#!/usr/bin/env python3
"""Verify Web selection, SDK URL expansion and failure atomicity."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "script"))
SPEC = importlib.util.spec_from_file_location("prepare_web", ROOT / "script/prepare-web.py")
WEB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEB)


class PrepareWebTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.paths = {}
        for platform in ("entware", "openwrt"):
            path = self.root / platform / "songloft/Makefile"
            path.parent.mkdir(parents=True)
            content = (ROOT / platform / "songloft/Makefile").read_text(encoding="utf-8")
            path.write_text(WEB.replace_assignment(content, "PKG_VERSION", "2.13.9"), encoding="utf-8")
            self.paths[platform] = path
        self.original = self.paths["entware"].read_text(encoding="utf-8")

    def release(self, tag="v2.13.9", digest="sha256:" + "c" * 64):
        return {"tag_name": tag, "draft": False, "prerelease": False,
                "published_at": "2026-11-06T00:00:00Z", "assets": [{
                    "name": "songloft-web-embedded.tar.gz", "state": "uploaded", "size": 123,
                    "browser_download_url": "https://github.com/" + WEB.PLAYER +
                    "/releases/download/" + tag + "/songloft-web-embedded.tar.gz",
                    "digest": digest}]}

    def prepare(self, release, platform="entware", **kwargs):
        with patch.object(WEB, "ROOT", self.root), \
                patch.object(WEB, "api_json", return_value=release) as api, \
                patch.object(WEB, "archive_hash", return_value="c" * 64) as archive:
            WEB.prepare_web(platform, **kwargs)
        return api, archive

    def test_default_strict_matches_server(self):
        api, archive = self.prepare(self.release())
        self.assertEqual(api.call_args[0][0], WEB.PLAYER + "/releases/tags/v2.13.9")
        archive.assert_not_called()
        self.assertIn("SONGLOFT_WEB_VERSION:=2.13.9\n", self.paths["entware"].read_text(encoding="utf-8"))

    def test_latest_can_be_older_or_newer_than_server(self):
        for platform, tag in (("entware", "v2.12.1"), ("openwrt", "v2.14.0")):
            with self.subTest(platform=platform, tag=tag):
                api, _ = self.prepare(self.release(tag), platform=platform, mode="latest")
                self.assertEqual(api.call_args[0][0], WEB.PLAYER + "/releases/latest")
                content = self.paths[platform].read_text(encoding="utf-8")
                self.assertIn("PKG_VERSION:=2.13.9\n", content)
                self.assertIn("PKG_RELEASE:=1\n", content)
                self.assertIn("SONGLOFT_WEB_VERSION:=" + tag[1:] + "\n", content)
                assignments = "\n".join(line for line in content.splitlines()
                                        if line.startswith("SONGLOFT_WEB_"))
                # Exercise GNU Make's actual expansion of the SDK download variables.
                makefile = assignments + "\nprint:\n\t@echo $(SONGLOFT_WEB_SOURCE) $(SONGLOFT_WEB_URL) $(SONGLOFT_WEB_HASH)\n"
                result = subprocess.check_output(["make", "--no-print-directory", "-f", "-", "print"],
                                                 input=makefile.encode()).decode().strip()
                self.assertEqual(result, "songloft-web-embedded-" + tag + ".tar.gz " +
                                 "https://github.com/" + WEB.PLAYER + "/releases/download/" +
                                 tag + " " + "c" * 64)

    def test_missing_strict_release_fails_without_latest_fallback(self):
        with patch.object(WEB, "ROOT", self.root), \
                patch.object(WEB, "api_json", side_effect=OSError("404")) as api:
            with self.assertRaises(OSError):
                WEB.prepare_web("entware")
        self.assertEqual(api.call_count, 1)
        self.assertEqual(self.paths["entware"].read_text(encoding="utf-8"), self.original)

    def test_missing_digest_downloads_and_hashes(self):
        _, archive = self.prepare(self.release(digest=None))
        self.assertEqual(archive.call_count, 1)
        self.assertIn("SONGLOFT_WEB_HASH:=" + "c" * 64, self.paths["entware"].read_text(encoding="utf-8"))

    def test_verify_web_downloads_even_with_digest(self):
        _, archive = self.prepare(self.release(), verify_web=True)
        self.assertEqual(archive.call_count, 1)

    def test_digest_mismatch_leaves_original_unchanged(self):
        with self.assertRaises(ValueError):
            self.prepare(self.release(digest="sha256:" + "d" * 64), verify_web=True)
        self.assertEqual(self.paths["entware"].read_text(encoding="utf-8"), self.original)

    def test_invalid_releases_never_write_package(self):
        invalid = []
        for field, value in (("draft", True), ("prerelease", True),
                             ("published_at", None), ("assets", [])):
            release = self.release()
            release[field] = value
            invalid.append((field, release))
        invalid.append(("wrong tag", self.release("v2.14.0")))
        invalid.append(("prerelease tag", self.release("v2.13.9-rc1")))
        for field, value in (("state", "new"), ("size", 0), ("digest", "md5:bad"),
                             ("browser_download_url", "https://example.com/web.tar.gz")):
            release = self.release()
            release["assets"][0][field] = value
            invalid.append((field, release))
        release = self.release()
        release["assets"] *= 2
        invalid.append(("duplicate asset", release))
        for label, release in invalid:
            with self.subTest(label=label):
                with self.assertRaises(ValueError):
                    self.prepare(release)
                self.assertEqual(self.paths["entware"].read_text(encoding="utf-8"), self.original)

    def test_unknown_mode_fails_before_network(self):
        with patch.object(WEB, "ROOT", self.root), patch.object(WEB, "api_json") as api:
            with self.assertRaises(ValueError):
                WEB.prepare_web("entware", mode="typo")
        api.assert_not_called()

    def test_older_release_makefile_can_use_current_preparation_script(self):
        path = self.paths["entware"]
        content = "\n".join(line for line in self.original.splitlines()
                            if not line.startswith("SONGLOFT_WEB_VERSION:=")) + "\n"
        content = content.replace("$(SONGLOFT_WEB_VERSION)", "$(PKG_VERSION)")
        path.write_text(content, encoding="utf-8")
        with patch.object(WEB, "api_json", return_value=self.release("v2.12.1")):
            WEB.prepare_web("entware", mode="latest", root=self.root)
        updated = path.read_text(encoding="utf-8")
        self.assertIn("SONGLOFT_WEB_VERSION:=2.12.1\n", updated)
        self.assertNotIn("web-embedded-v$(PKG_VERSION)", updated)

    def test_missing_assignment_does_not_write_partial_preparation(self):
        path = self.paths["entware"]
        content = self.original.replace("SONGLOFT_WEB_HASH:=", "MISSING_HASH:=")
        path.write_text(content, encoding="utf-8")
        with self.assertRaises(ValueError):
            self.prepare(self.release())
        self.assertEqual(path.read_text(encoding="utf-8"), content)


if __name__ == "__main__":
    unittest.main()
