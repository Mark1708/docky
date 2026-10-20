#!/usr/bin/env python3
"""Validate an immutable Docky release tag before signing or publication."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INITIAL_RELEASE_TAG = "v0.10.0"
INITIAL_BUILD_FLOOR = 202610020901
TAG_PATTERN = re.compile(r"^v(?P<version>\d+\.\d+\.\d+)$")
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class PreflightError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreflightResult:
    release_tag: str
    marketing_version: str
    build_version: int


def extract_latest_build(appcast: bytes) -> int:
    try:
        root = ET.fromstring(appcast)
    except ET.ParseError as error:
        raise PreflightError(f"latest appcast is malformed XML: {error}") from error

    item = root.find("./channel/item")
    if item is None:
        item = root.find(".//item")
    if item is None:
        raise PreflightError("latest appcast has no item")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise PreflightError("latest appcast item has no enclosure")
    raw_build = enclosure.attrib.get(f"{{{SPARKLE_NAMESPACE}}}version")
    if raw_build is None or not raw_build.isdigit():
        raise PreflightError("latest appcast enclosure has no numeric sparkle:version")
    return int(raw_build)


def validate_preflight(
    *,
    release_tag: str,
    build_version: str,
    checked_out_commit: str,
    tag_commit: str,
    main_is_ancestor: bool,
    release_state: str | None,
    has_stable_release: bool,
    latest_appcast: bytes | None,
    latest_appcast_error: str | None = None,
) -> PreflightResult:
    match = TAG_PATTERN.fullmatch(release_tag)
    if match is None:
        raise PreflightError("RELEASE_TAG must match vX.Y.Z")
    if not build_version.isdigit():
        raise PreflightError("BUILD_VERSION must be numeric")
    numeric_build = int(build_version)

    if checked_out_commit != tag_commit:
        raise PreflightError("release tag does not resolve to the checked-out commit")
    if not main_is_ancestor:
        raise PreflightError("release commit is not an ancestor of origin/main")
    if release_state is not None:
        raise PreflightError(f"GitHub Release already exists for {release_tag} ({release_state})")

    if release_tag == INITIAL_RELEASE_TAG:
        if has_stable_release:
            raise PreflightError("initial fork release requires no existing stable GitHub Release")
        if latest_appcast_error is not None:
            raise PreflightError(f"could not prove initial appcast absence: {latest_appcast_error}")
        if latest_appcast is not None:
            raise PreflightError("initial fork release requires no existing latest appcast")
        if numeric_build <= INITIAL_BUILD_FLOOR:
            raise PreflightError(f"BUILD_VERSION must be greater than initial floor {INITIAL_BUILD_FLOOR}")
    else:
        if latest_appcast_error is not None:
            raise PreflightError(f"latest appcast is unavailable: {latest_appcast_error}")
        if latest_appcast is None:
            raise PreflightError("latest appcast is required after the initial fork release")
        latest_build = extract_latest_build(latest_appcast)
        if numeric_build <= latest_build:
            raise PreflightError(f"BUILD_VERSION must be greater than latest appcast build {latest_build}")

    return PreflightResult(
        release_tag=release_tag,
        marketing_version=match.group("version"),
        build_version=numeric_build,
    )


def run_git(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=check,
        capture_output=True,
        text=True,
    )


def remote_tag_commit(release_tag: str) -> str:
    result = run_git(
        "ls-remote",
        "origin",
        f"refs/tags/{release_tag}",
        f"refs/tags/{release_tag}^{{}}",
    )
    references: dict[str, str] = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2:
            references[parts[1]] = parts[0]
    peeled = references.get(f"refs/tags/{release_tag}^{{}}")
    direct = references.get(f"refs/tags/{release_tag}")
    commit = peeled or direct
    if commit is None:
        raise PreflightError(f"origin has no tag {release_tag}")
    return commit


def github_request(url: str, token: str | None) -> tuple[int, bytes]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Docky-release-preflight",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except urllib.error.URLError as error:
        raise PreflightError(f"request failed for {url}: {error.reason}") from error


def github_release_state(repository: str, release_tag: str, token: str | None) -> str | None:
    status, payload = github_request(
        f"https://api.github.com/repos/{repository}/releases/tags/{release_tag}",
        token,
    )
    if status == 404:
        return None
    if status != 200:
        raise PreflightError(f"GitHub release lookup failed with HTTP {status}")
    release = json.loads(payload)
    return "draft" if release.get("draft") else "published"


def github_has_stable_release(repository: str, token: str | None) -> bool:
    status, _ = github_request(
        f"https://api.github.com/repos/{repository}/releases/latest",
        token,
    )
    if status == 404:
        return False
    if status != 200:
        raise PreflightError(f"latest stable GitHub release lookup failed with HTTP {status}")
    return True


def latest_appcast(repository: str, token: str | None) -> bytes | None:
    status, payload = github_request(
        f"https://github.com/{repository}/releases/latest/download/appcast.xml",
        token,
    )
    if status == 404:
        return None
    if status != 200:
        raise PreflightError(f"latest appcast lookup failed with HTTP {status}")
    return payload


def write_outputs(result: PreflightResult) -> None:
    values = {
        "release_tag": result.release_tag,
        "marketing_version": result.marketing_version,
        "build_version": str(result.build_version),
    }
    for key, value in values.items():
        print(f"{key.upper()}={value}")
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={value}\n")


def main() -> int:
    try:
        release_tag = os.environ["RELEASE_TAG"]
        build_version = os.environ["BUILD_VERSION"]
        repository = os.environ.get("GITHUB_REPOSITORY", "Mark1708/docky")
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

        checked_out_commit = run_git("rev-parse", "HEAD").stdout.strip()
        tag_commit = remote_tag_commit(release_tag)
        main_check = run_git("merge-base", "--is-ancestor", checked_out_commit, "origin/main", check=False)
        if main_check.returncode not in {0, 1}:
            raise PreflightError("git could not verify ancestry against origin/main")

        release_state = github_release_state(repository, release_tag, token)
        has_stable_release = github_has_stable_release(repository, token)
        appcast = latest_appcast(repository, token)
        result = validate_preflight(
            release_tag=release_tag,
            build_version=build_version,
            checked_out_commit=checked_out_commit,
            tag_commit=tag_commit,
            main_is_ancestor=main_check.returncode == 0,
            release_state=release_state,
            has_stable_release=has_stable_release,
            latest_appcast=appcast,
        )
        write_outputs(result)
        return 0
    except KeyError as error:
        print(f"release preflight failed: missing environment variable {error.args[0]}", file=sys.stderr)
    except (PreflightError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"release preflight failed: {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
