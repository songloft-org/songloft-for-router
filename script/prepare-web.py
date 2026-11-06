#!/usr/bin/env python3
"""Pin the Web asset for a router build, independently of the update check."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from upstream import PLAYER, api_json, archive_hash, replace_assignment


ROOT = Path(__file__).resolve().parent.parent


def prepare_web(platform, mode="strict", verify_web=False, root=None):
    root = root or ROOT
    path = root / platform / "songloft" / "Makefile"
    original = path.read_text(encoding="utf-8")
    match = re.search(r"^PKG_VERSION:=(\d+\.\d+\.\d+)$", original, re.M)
    if not match:
        raise ValueError("Invalid or missing PKG_VERSION in " + str(path))
    server_tag = "v" + match.group(1)
    if mode not in ("strict", "latest"):
        raise ValueError("Web mode must be strict or latest")
    endpoint = "/releases/tags/" + server_tag if mode == "strict" else "/releases/latest"
    print("Selecting player Web: mode=" + mode + ", server=" + server_tag, flush=True)
    with tempfile.TemporaryDirectory(prefix="songloft-web-") as temporary:
        directory = Path(temporary)
        release = api_json(PLAYER + endpoint, directory)
        tag = release["tag_name"]
        assets = [asset for asset in release["assets"]
                  if asset["name"] == "songloft-web-embedded.tar.gz"]
        if (not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or
                (mode == "strict" and tag != server_tag) or release["draft"] or
                release["prerelease"] or not release["published_at"] or len(assets) != 1):
            raise ValueError("Selected stable player Web release asset is unavailable")
        asset = assets[0]
        if asset.get("state") != "uploaded" or asset.get("size", 0) <= 0:
            raise ValueError("songloft-web-embedded.tar.gz has not finished uploading")
        url = "https://github.com/" + PLAYER + "/releases/download/" + tag
        if asset["browser_download_url"] != url + "/songloft-web-embedded.tar.gz":
            raise ValueError("Unexpected player Web asset URL")
        expected = asset.get("digest")
        if expected and not re.fullmatch(r"sha256:[0-9a-f]{64}", expected):
            raise ValueError("Unexpected Web asset digest format")
        if expected and not verify_web:
            web_hash = expected.split(":", 1)[1]
        else:
            web_hash = archive_hash(asset["browser_download_url"], directory / "web.tar.gz")
            if expected and expected != "sha256:" + web_hash:
                raise ValueError("Web archive does not match GitHub's SHA256 digest")

    content = original
    # Older release tags predate the independent Web version assignment.
    if not re.search(r"^SONGLOFT_WEB_VERSION:=", content, re.M):
        content, count = re.subn(r"^SONGLOFT_WEB_SOURCE:=", "SONGLOFT_WEB_VERSION:=" +
                                tag[1:] + "\nSONGLOFT_WEB_SOURCE:=", content, flags=re.M)
        if count != 1:
            raise ValueError("Expected exactly one assignment for SONGLOFT_WEB_SOURCE")
    for key, value in (("SONGLOFT_WEB_VERSION", tag[1:]),
                       ("SONGLOFT_WEB_SOURCE", "songloft-web-embedded-v$(SONGLOFT_WEB_VERSION).tar.gz"),
                       ("SONGLOFT_WEB_URL", "https://github.com/" + PLAYER +
                        "/releases/download/v$(SONGLOFT_WEB_VERSION)"),
                       ("SONGLOFT_WEB_HASH", web_hash)):
        content = replace_assignment(content, key, value)
    # Write only after all metadata, hashes and assignments have been validated.
    if content != original:
        path.write_text(content, encoding="utf-8")
    print(str(path.relative_to(root)) + ": server=" + server_tag + ", player=" + tag)
    print("Web SHA256: " + web_hash)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("entware", "openwrt"))
    parser.add_argument("--root", type=Path, default=ROOT,
                        help="repository checkout containing the package Makefile")
    parser.add_argument("--mode", choices=("strict", "latest"), default="strict",
                        help="strict: match server tag (default); latest: latest stable player release")
    parser.add_argument("--verify-web", action="store_true",
                        help="download the Web archive to verify GitHub's SHA256 digest")
    args = parser.parse_args()
    prepare_web(args.platform, args.mode, args.verify_web, root=args.root)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print("Web preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
