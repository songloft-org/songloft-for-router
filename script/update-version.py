#!/usr/bin/env python3
"""Update both router packages from upstream archives (Python 3.6+, curl)."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com/repos/"
SERVER = "songloft-org/songloft"
PLAYER = "songloft-org/songloft-player"


def download(url, destination, api=False):
    command = ["curl", "--fail", "--location", "--silent", "--show-error",
               "--retry", "3", "--connect-timeout", "30", "--max-time", "600",
               "--user-agent", "songloft-router-version-updater"]
    # Never forward the API token to archive hosts or release redirects.
    if api and os.environ.get("GITHUB_TOKEN"):
        command += ["--header", "Authorization: Bearer " + os.environ["GITHUB_TOKEN"]]
    subprocess.run(command + ["--output", str(destination), url], check=True)


def api_json(path, directory):
    destination = directory / "metadata.json"
    download(API + path, destination, api=True)
    return json.loads(destination.read_text(encoding="utf-8"))


def latest_version(directory):
    # A server tag may be available before its GitHub Release is published.
    versions = []
    page = 1
    while True:
        tags = api_json(SERVER + "/tags?per_page=100&page=" + str(page), directory)
        for tag in tags:
            match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag["name"])
            if match:
                versions.append(tuple(map(int, match.groups())))
        if len(tags) < 100:
            break
        page += 1
    if not versions:
        raise ValueError("No stable upstream version tags found")
    return ".".join(map(str, max(versions)))


def archive_hash(url, destination):
    print("Downloading " + url, flush=True)
    download(url, destination)
    digest = hashlib.sha256()
    with destination.open("rb") as archive:
        for chunk in iter(lambda: archive.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_assignment(content, key, value):
    content, count = re.subn(r"^" + re.escape(key) + r":=.*$",
                             lambda _: key + ":=" + value, content, flags=re.M)
    if count != 1:
        raise ValueError("Expected exactly one assignment for " + key)
    return content


def report_version(version, upgrade_ready):
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as stream:
            stream.write("version=" + version + "\n")
            stream.write("upgrade_ready=" + str(upgrade_ready).lower() + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?",
                        help="force-check this version, e.g. 2.13.2 (default: skip if already latest)")
    parser.add_argument("--verify-web", action="store_true",
                        help="also download the Web archive to verify GitHub's digest")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="songloft-update-") as temporary:
        directory = Path(temporary)
        version = args.version.lstrip("v") if args.version else latest_version(directory)
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError("Version must have the form 2.13.2")
        packages = []
        for platform in ("entware", "openwrt"):
            path = ROOT / platform / "songloft" / "Makefile"
            original = path.read_text(encoding="utf-8")
            match = re.search(r"^PKG_VERSION:=(.+)$", original, re.M)
            if not match:
                raise ValueError("PKG_VERSION not found in " + str(path))
            packages.append((path, original, match.group(1).strip()))
        target = tuple(map(int, version.split(".")))
        current_versions = [tuple(map(int, current.split("."))) for _, _, current in packages]
        new_version = (all(target >= current for current in current_versions) and
                       any(target > current for current in current_versions))
        if args.version is None and not new_version:
            print("Upstream " + version + " requires no version upgrade; skipping the remaining workflow.")
            report_version(version, False)
            return
        tag = "v" + version
        print("Updating Entware and OpenWrt to " + tag, flush=True)
        submodule = api_json(SERVER + "/contents/pkg/tag?ref=" + tag, directory)
        if (submodule.get("type") != "submodule" or
                submodule.get("submodule_git_url") != "https://github.com/hanxi/tag.git" or
                not re.fullmatch(r"[0-9a-f]{40}", submodule.get("sha", ""))):
            raise ValueError("Unexpected pkg/tag submodule metadata")
        commit = submodule["sha"]
        release = api_json(PLAYER + "/releases/tags/" + tag, directory)
        assets = [asset for asset in release["assets"]
                  if asset["name"] == "songloft-web-embedded.tar.gz"]
        if (release["tag_name"] != tag or release["draft"] or release["prerelease"] or
                not release["published_at"] or len(assets) != 1):
            raise ValueError("Matching stable Web release asset is unavailable")
        if assets[0].get("state") != "uploaded" or assets[0].get("size", 0) <= 0:
            raise ValueError("songloft-web-embedded.tar.gz has not finished uploading")
        source_hash = archive_hash("https://codeload.github.com/" + SERVER +
                                   "/tar.gz/" + tag, directory / "source.tar.gz")
        tag_hash = archive_hash("https://codeload.github.com/hanxi/tag/tar.gz/" +
                                commit, directory / "tag.tar.gz")
        expected = assets[0].get("digest")
        if expected and not re.fullmatch(r"sha256:[0-9a-f]{64}", expected):
            raise ValueError("Unexpected Web asset digest format")
        if expected and not args.verify_web:
            # GitHub publishes the uploaded asset's digest; avoid a large download.
            web_hash = expected.split(":", 1)[1]
        else:
            web_hash = archive_hash(assets[0]["browser_download_url"], directory / "web.tar.gz")
            if expected and expected != "sha256:" + web_hash:
                raise ValueError("Web archive does not match GitHub's SHA256 digest")

        # Validate and prepare both files before changing either package.
        updates = []
        for path, original, old_version in packages:
            content = original
            # Make preserves backslashes in variable assignments. Always write
            # plain https:// so the SDK can recognize the download protocol.
            for key, value in (("PKG_VERSION", version),
                               ("PKG_SOURCE_URL", "https://codeload.github.com/" + SERVER +
                                "/tar.gz/v$(PKG_VERSION)?"),
                               ("PKG_HASH", source_hash),
                               ("SONGLOFT_TAG_VERSION", commit),
                               ("SONGLOFT_TAG_URL", "https://codeload.github.com/hanxi/tag/"
                                "tar.gz/$(SONGLOFT_TAG_VERSION)?"),
                               ("SONGLOFT_TAG_HASH", tag_hash),
                               ("SONGLOFT_WEB_HASH", web_hash)):
                content = replace_assignment(content, key, value)
            if old_version != version:
                content = replace_assignment(content, "PKG_RELEASE", "1")
            updates.append((path, original, content))
        for path, original, content in updates:
            if content != original:
                path.write_text(content, encoding="utf-8")
            print(str(path.relative_to(ROOT)) + ": " + version)
        print("Source SHA256: " + source_hash)
        print("pkg/tag SHA256: " + tag_hash)
        print("Web SHA256: " + web_hash)
        # Only a successful version upgrade may continue to tagging and builds.
        report_version(version, new_version)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print("Update failed: " + str(error), file=sys.stderr)
        sys.exit(1)
