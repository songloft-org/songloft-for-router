"""Shared GitHub download helpers (Python 3.6+, curl)."""

import hashlib
import json
import os
import re
import subprocess


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
