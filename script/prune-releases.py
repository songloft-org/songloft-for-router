#!/usr/bin/env python3
"""Keep the highest successful version of one platform; remove older releases/tags."""

import argparse
import json
import os
import re
import subprocess


def obsolete_releases(releases, platform):
    candidates = []
    # Include packaging revisions such as openwrt-2.13.1-2.
    pattern = re.compile(re.escape(platform) + r"-(\d+)\.(\d+)\.(\d+)(?:-(\d+))?")
    for release in releases:
        match = pattern.fullmatch(release["tag_name"])
        if match and not release["prerelease"]:
            version = tuple(int(part or 0) for part in match.groups())
            candidates.append((version, release["tag_name"], release["draft"]))
    candidates.sort(reverse=True)
    successful = [version for version, _, draft in candidates if not draft]
    if not successful:
        return []
    newest = max(successful)
    return [tag for version, tag, _ in candidates if version < newest]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("entware", "openwrt"))
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.repo:
        parser.error("--repo or GITHUB_REPOSITORY is required")
    releases = []
    page = 1
    while True:
        batch = json.loads(subprocess.check_output([
            "gh", "api", "repos/" + args.repo + "/releases?per_page=100&page=" + str(page)
        ]).decode("utf-8"))
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    for tag in obsolete_releases(releases, args.platform):
        print("Removing old release and tag: " + tag, flush=True)
        if not args.dry_run:
            subprocess.run(["gh", "release", "delete", tag, "--repo", args.repo,
                            "--cleanup-tag", "--yes"], check=True)


if __name__ == "__main__":
    main()
