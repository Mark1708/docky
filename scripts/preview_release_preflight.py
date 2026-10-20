#!/usr/bin/env python3
"""Validate an immutable unsigned Docky preview tag before publication."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass

from release_preflight import (
    INITIAL_BUILD_FLOOR,
    PreflightError,
    github_release_state,
    remote_tag_commit,
    run_git,
)

PREVIEW_TAG_PATTERN = re.compile(
    r"^preview-v(?P<version>\d+\.\d+\.\d+)\.(?P<preview>[1-9]\d*)$"
)


class PreviewPreflightError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreviewPreflightResult:
    preview_tag: str
    marketing_version: str
    preview_number: int
    build_version: int


def validate_preview_preflight(
    *,
    preview_tag: str,
    build_version: str,
    checked_out_commit: str,
    tag_commit: str,
    main_is_ancestor: bool,
    release_state: str | None,
) -> PreviewPreflightResult:
    match = PREVIEW_TAG_PATTERN.fullmatch(preview_tag)
    if match is None:
        raise PreviewPreflightError("PREVIEW_TAG must match preview-vX.Y.Z.N")
    if not build_version.isdigit():
        raise PreviewPreflightError("BUILD_VERSION must be numeric")

    numeric_build = int(build_version)
    if numeric_build <= INITIAL_BUILD_FLOOR:
        raise PreviewPreflightError(
            f"BUILD_VERSION must be greater than initial floor {INITIAL_BUILD_FLOOR}"
        )
    if checked_out_commit != tag_commit:
        raise PreviewPreflightError("preview tag does not resolve to the checked-out commit")
    if not main_is_ancestor:
        raise PreviewPreflightError("preview commit is not an ancestor of origin/main")
    if release_state is not None:
        raise PreviewPreflightError(
            f"GitHub Release already exists for {preview_tag} ({release_state})"
        )

    return PreviewPreflightResult(
        preview_tag=preview_tag,
        marketing_version=match.group("version"),
        preview_number=int(match.group("preview")),
        build_version=numeric_build,
    )


def write_outputs(result: PreviewPreflightResult) -> None:
    values = {
        "preview_tag": result.preview_tag,
        "marketing_version": result.marketing_version,
        "preview_number": str(result.preview_number),
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
        preview_tag = os.environ["PREVIEW_TAG"]
        build_version = os.environ["BUILD_VERSION"]
        repository = os.environ.get("GITHUB_REPOSITORY", "Mark1708/docky")
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

        checked_out_commit = run_git("rev-parse", "HEAD").stdout.strip()
        tag_commit = remote_tag_commit(preview_tag)
        main_check = run_git(
            "merge-base", "--is-ancestor", checked_out_commit, "origin/main", check=False
        )
        if main_check.returncode not in {0, 1}:
            raise PreviewPreflightError("git could not verify ancestry against origin/main")

        result = validate_preview_preflight(
            preview_tag=preview_tag,
            build_version=build_version,
            checked_out_commit=checked_out_commit,
            tag_commit=tag_commit,
            main_is_ancestor=main_check.returncode == 0,
            release_state=github_release_state(repository, preview_tag, token),
        )
        write_outputs(result)
        return 0
    except KeyError as error:
        print(
            f"preview release preflight failed: missing environment variable {error.args[0]}",
            file=sys.stderr,
        )
    except (
        PreviewPreflightError,
        PreflightError,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ) as error:
        print(f"preview release preflight failed: {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
