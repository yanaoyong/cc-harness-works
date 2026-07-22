#!/usr/bin/env python3
"""Validate plugin distribution integrity for local development and CI.

The default mode is offline and read-only.  Release-context validation is enabled
only when both --release-commit and --tag-repo are supplied; it reads local Git
refs and never creates, updates, fetches, or pushes tags.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import stat
import subprocess
import sys
import tempfile
from typing import Any, Iterable

PLUGIN_MANIFEST = PurePosixPath(".claude-plugin/plugin.json")
MARKETPLACE_MANIFEST = PurePosixPath(".claude-plugin/marketplace.json")
DEFAULT_DISTRIBUTION_MANIFEST = PurePosixPath(
    ".harness/config/public_distribution_manifest.json"
)
DEFAULT_SYNC_MANIFEST = PurePosixPath("plugins/harness-core/sync-manifest")
HOOKS_MANIFEST = PurePosixPath("plugins/harness-core/hooks/hooks.json")
WORKFLOW_PATH = PurePosixPath(".github/workflows/plugin-distribution.yml")
CHECKER_PATH = PurePosixPath(".harness/scripts/check_plugin_distribution.py")
LICENSE_PATH = PurePosixPath("LICENSE")
GUIDE_PATH = PurePosixPath("docs/guides/plugin-distribution-guide.md")
SYNC_SCRIPT_PATH = PurePosixPath(".harness/scripts/sync_public_marketplace.sh")
SEMVER_PARTS = 3


class CheckFailure(RuntimeError):
    """A user-actionable distribution check failure."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise CheckFailure(f"required JSON file is missing: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CheckFailure(f"invalid JSON in {path}: {exc}") from exc


def safe_relative(value: object, field: str) -> PurePosixPath:
    if not isinstance(value, str) or not value:
        raise CheckFailure(f"{field} must be a non-empty relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() in {".", ""}:
        raise CheckFailure(f"{field} is not a safe repository-relative path: {value!r}")
    return path


def run_checked(argv: list[str], cwd: Path, label: str) -> None:
    try:
        result = subprocess.run(
            argv,
            cwd=cwd,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    except FileNotFoundError as exc:
        raise CheckFailure(f"{label}: required command is unavailable: {argv[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise CheckFailure(f"{label}: command timed out after 120 seconds") from exc
    if result.returncode != 0:
        output = result.stdout.strip()
        raise CheckFailure(
            f"{label} failed (exit {result.returncode})"
            + (f":\n{output}" if output else "")
        )


def parse_manifest(root: Path, manifest_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    raw = load_json(manifest_path)
    if not isinstance(raw, dict) or raw.get("schema_version") != 1:
        raise CheckFailure("public distribution manifest must use schema_version 1")
    entries = raw.get("entries")
    if not isinstance(entries, list) or not entries:
        raise CheckFailure("public distribution manifest entries must be a non-empty array")

    seen_destinations: list[PurePosixPath] = []
    parsed: list[dict[str, Any]] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise CheckFailure(f"manifest entries[{index}] must be an object")
        entry_type = entry.get("type")
        if entry_type not in {"file", "directory", "generated"}:
            raise CheckFailure(f"manifest entries[{index}].type is unsupported: {entry_type!r}")
        destination = safe_relative(entry.get("destination"), f"entries[{index}].destination")
        conflicting_destination = next(
            (
                existing
                for existing in seen_destinations
                if destination == existing
                or existing in destination.parents
                or destination in existing.parents
            ),
            None,
        )
        if conflicting_destination is not None:
            raise CheckFailure(
                "conflicting manifest destinations (duplicate or ancestor/descendant): "
                f"{conflicting_destination} <-> {destination}"
            )
        seen_destinations.append(destination)
        normalized = dict(entry)
        normalized["destination_path"] = destination
        if entry_type in {"file", "directory"}:
            source = safe_relative(entry.get("source"), f"entries[{index}].source")
            source_path = root / source
            expected_kind = source_path.is_file() if entry_type == "file" else source_path.is_dir()
            if not expected_kind:
                raise CheckFailure(
                    f"manifest {entry_type} source is missing or has the wrong type: {source}"
                )
            normalized["source_path"] = source
        elif not isinstance(entry.get("generator"), str) or not entry["generator"]:
            raise CheckFailure(f"generated entry {destination} requires a generator identifier")
        parsed.append(normalized)

    exclusions = raw.get("directory_exclusions")
    if not isinstance(exclusions, dict):
        raise CheckFailure("directory_exclusions must be an object")
    for key in ("names", "file_globs"):
        values = exclusions.get(key)
        if not isinstance(values, list) or not all(isinstance(v, str) and v for v in values):
            raise CheckFailure(f"directory_exclusions.{key} must be a string array")
    permission = raw.get("permission_policy")
    if not isinstance(permission, dict) or permission.get("preserve_source_modes") is not True:
        raise CheckFailure("permission_policy.preserve_source_modes must be true")
    if permission.get("generated_file_mode") != "0644":
        raise CheckFailure("permission_policy.generated_file_mode must be '0644'")
    readme = raw.get("readme_policy")
    if (
        not isinstance(readme, dict)
        or readme.get("strategy") != "generated"
        or readme.get("entry_destination") != "README.md"
        or not isinstance(readme.get("generator"), str)
        or not readme["generator"]
    ):
        raise CheckFailure("readme_policy must identify the generated README.md entry")
    generated_entries = [item for item in parsed if item["type"] == "generated"]
    if len(generated_entries) != 1 or (
        generated_entries[0]["destination_path"] != PurePosixPath("README.md")
        or generated_entries[0].get("generator") != readme["generator"]
    ):
        raise CheckFailure(
            "manifest must contain exactly one generated README.md entry matching readme_policy"
        )

    # Completeness derives plugin roots from marketplace.json rather than copying a
    # second plugin whitelist into this checker.
    marketplace = load_json(root / MARKETPLACE_MANIFEST)
    plugins = marketplace.get("plugins") if isinstance(marketplace, dict) else None
    if not isinstance(plugins, list) or not plugins:
        raise CheckFailure("marketplace plugins must be a non-empty array")
    copied_sources = {
        item["source_path"]
        for item in parsed
        if item["type"] in {"file", "directory"}
    }
    # Release-chain entry points that must stay manifest-listed.  Dropping one
    # used to pass source-repo checks silently because the file still exists in
    # the work tree — that blind spot shipped the sync script unlisted and was
    # only caught by the public-side checker after release (hotfix #293).
    required_sources = {
        MARKETPLACE_MANIFEST,
        DEFAULT_DISTRIBUTION_MANIFEST,
        CHECKER_PATH,
        WORKFLOW_PATH,
        LICENSE_PATH,
        GUIDE_PATH,
        SYNC_SCRIPT_PATH,
    }
    for index, plugin in enumerate(plugins):
        if not isinstance(plugin, dict):
            raise CheckFailure(f"marketplace plugins[{index}] must be an object")
        source_value = plugin.get("source")
        if isinstance(source_value, str) and source_value.startswith("./"):
            source_value = source_value[2:]
        required_sources.add(safe_relative(source_value, f"marketplace plugins[{index}].source"))
    missing_sources = sorted(required_sources - copied_sources, key=str)
    if missing_sources:
        raise CheckFailure(
            "public distribution manifest omits required source entries: "
            + ", ".join(map(str, missing_sources))
        )
    return raw, parsed


def plugin_manifests(root: Path) -> tuple[list[tuple[str, Path, dict[str, Any]]], dict[str, Any]]:
    marketplace = load_json(root / MARKETPLACE_MANIFEST)
    records: list[tuple[str, Path, dict[str, Any]]] = []
    seen_names: set[str] = set()
    for index, item in enumerate(marketplace.get("plugins", [])):
        if not isinstance(item, dict):
            raise CheckFailure(f"marketplace plugins[{index}] must be an object")
        name = item.get("name")
        source = item.get("source")
        if not isinstance(name, str) or not name or name in seen_names:
            raise CheckFailure(f"marketplace plugin name is missing or duplicated: {name!r}")
        seen_names.add(name)
        if isinstance(source, str) and source.startswith("./"):
            source = source[2:]
        source_rel = safe_relative(source, f"marketplace plugins[{index}].source")
        data = load_json(root / source_rel / PLUGIN_MANIFEST)
        if data.get("name") != name:
            raise CheckFailure(f"marketplace/plugin name mismatch for {name}: {data.get('name')!r}")
        records.append((name, root / source_rel, data))
    if not records:
        raise CheckFailure("marketplace contains no plugins")
    return records, marketplace


def parse_semver(version: object, label: str) -> tuple[int, int, int]:
    if not isinstance(version, str):
        raise CheckFailure(f"{label} must be a semantic version string")
    parts = version.split(".")
    if len(parts) != SEMVER_PARTS or any(not part.isdigit() for part in parts):
        raise CheckFailure(f"{label} must be X.Y.Z, got {version!r}")
    return tuple(int(part) for part in parts)  # type: ignore[return-value]


def check_versions(records: list[tuple[str, Path, dict[str, Any]]], marketplace: dict[str, Any]) -> str:
    versions = {name: data.get("version") for name, _, data in records}
    unique = set(versions.values())
    if len(unique) != 1:
        raise CheckFailure(f"plugin versions are not lockstep: {versions}")
    version = next(iter(unique))
    parse_semver(version, "plugin version")
    marketplace_version = marketplace.get("metadata", {}).get("version")
    if marketplace_version != version:
        raise CheckFailure(
            f"marketplace metadata version {marketplace_version!r} does not match plugins {version!r}"
        )
    names = {name for name, _, _ in records}
    if "harness-core" not in names:
        raise CheckFailure("marketplace must include harness-core")
    for name, _, data in records:
        if name == "harness-core":
            continue
        dependencies = data.get("dependencies")
        core_constraints = [
            dep.get("version")
            for dep in dependencies or []
            if isinstance(dep, dict) and dep.get("name") == "harness-core"
        ]
        expected = f"~{version}"
        if core_constraints != [expected]:
            raise CheckFailure(
                f"{name} must depend exactly once on harness-core {expected}; got {core_constraints}"
            )
    return str(version)


def check_official_validation(root: Path, records: list[tuple[str, Path, dict[str, Any]]]) -> None:
    run_checked(["claude", "plugin", "validate", "--strict", "."], root, "root strict validation")
    for name, plugin_root, _ in records:
        run_checked(
            ["claude", "plugin", "validate", "--strict", str(plugin_root)],
            root,
            f"strict validation for {name}",
        )


def is_excluded(relative: PurePosixPath, exclusions: dict[str, Any]) -> bool:
    names = set(exclusions["names"])
    if any(part in names for part in relative.parts):
        return True
    return any(fnmatch.fnmatch(relative.name, pattern) for pattern in exclusions["file_globs"])


def distributed_source_files(
    root: Path, manifest: dict[str, Any], entries: list[dict[str, Any]]
) -> Iterable[Path]:
    exclusions = manifest["directory_exclusions"]
    for entry in entries:
        if entry["type"] == "file":
            yield root / entry["source_path"]
        elif entry["type"] == "directory":
            base = root / entry["source_path"]
            for path in base.rglob("*"):
                if path.is_file() and not is_excluded(PurePosixPath(path.relative_to(base).as_posix()), exclusions):
                    yield path


def check_syntax(root: Path, manifest: dict[str, Any], entries: list[dict[str, Any]]) -> None:
    for path in sorted(set(distributed_source_files(root, manifest, entries))):
        suffix = path.suffix.lower()
        relative = path.relative_to(root)
        if suffix == ".sh":
            run_checked(["bash", "-n", str(path)], root, f"Shell syntax {relative}")
        elif suffix == ".js":
            run_checked(["node", "--check", str(path)], root, f"JavaScript syntax {relative}")
        elif suffix == ".py":
            try:
                compile(path.read_bytes(), str(relative), "exec")
            except (OSError, SyntaxError) as exc:
                raise CheckFailure(f"Python syntax {relative} failed: {exc}") from exc


def hook_commands(value: object) -> Iterable[str]:
    if isinstance(value, dict):
        command = value.get("command")
        if value.get("type") == "command" and isinstance(command, str):
            yield command
        for nested in value.values():
            yield from hook_commands(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from hook_commands(nested)


def hook_inventory(hooks: object) -> dict[str, int]:
    if not isinstance(hooks, dict):
        raise CheckFailure("hooks.json hooks must be an object")
    inventory: dict[str, int] = {}
    for event, groups in hooks.items():
        if not isinstance(event, str) or not isinstance(groups, list):
            raise CheckFailure(f"invalid hook event declaration: {event!r}")
        inventory[event] = sum(1 for _ in hook_commands(groups))
    return inventory


def check_hook_targets(root: Path) -> None:
    data = load_json(root / HOOKS_MANIFEST)
    if not isinstance(data, dict):
        raise CheckFailure("hooks.json must be an object")
    hooks = data.get("hooks")
    commands = list(hook_commands(hooks))
    if not commands:
        raise CheckFailure("hooks.json declares no command hooks")
    contract = data.get("inventory_contract")
    if not isinstance(contract, dict):
        raise CheckFailure("hooks.json inventory_contract must be an object")
    expected_events = contract.get("event_command_counts")
    expected_total = contract.get("total_commands")
    if (
        not isinstance(expected_events, dict)
        or not all(isinstance(key, str) and isinstance(value, int) and value >= 0 for key, value in expected_events.items())
        or not isinstance(expected_total, int)
        or expected_total < 0
    ):
        raise CheckFailure("hooks.json inventory_contract must declare event_command_counts and total_commands")
    actual_events = hook_inventory(hooks)
    if actual_events != expected_events or sum(actual_events.values()) != expected_total:
        raise CheckFailure(
            "hook inventory mismatch: "
            f"expected events={expected_events}, total={expected_total}; "
            f"actual events={actual_events}, total={sum(actual_events.values())}"
        )
    prefix = "${CLAUDE_PLUGIN_ROOT}/"
    for command in commands:
        try:
            tokens = shlex.split(command)
        except ValueError as exc:
            raise CheckFailure(f"invalid hook command quoting: {command!r}: {exc}") from exc
        targets = [token[len(prefix) :] for token in tokens if token.startswith(prefix)]
        if len(targets) != 1:
            raise CheckFailure(f"hook command must identify one plugin-root target: {command!r}")
        target = root / "plugins/harness-core" / safe_relative(targets[0], "hook command target")
        if not target.is_file():
            raise CheckFailure(f"hook command target is missing: {target.relative_to(root)}")
        if not os.access(target, os.R_OK):
            raise CheckFailure(f"hook command target is not readable: {target.relative_to(root)}")


def check_sync_manifest(root: Path) -> None:
    path = root / DEFAULT_SYNC_MANIFEST
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise CheckFailure(f"cannot read consumer sync-manifest: {path}: {exc}") from exc
    rules: list[tuple[str, str, bool]] = []
    for line_number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) not in {2, 3} or fields[0] not in {"machine", "semi", "custom"}:
            raise CheckFailure(f"invalid sync-manifest line {line_number}: {raw!r}")
        if len(fields) == 3 and fields[2] != "opt-out":
            raise CheckFailure(f"invalid sync-manifest option on line {line_number}: {fields[2]!r}")
        pattern = safe_relative(fields[1], f"sync-manifest line {line_number} pattern").as_posix()
        rules.append((fields[0], pattern, len(fields) == 3))
    if not rules:
        raise CheckFailure("consumer sync-manifest contains no classification rules")
    plugin_root = root / "plugins/harness-core"
    ignored_files = {
        ".claude-plugin/plugin.json",
        "AGENTS.md",
        "CLAUDE.md.template",
        "sync-manifest",
    }
    # Ordinary plugin hooks are distributed natively and do not belong to the
    # consumer .harness mirror.  A same-relative-path file already present in
    # the consumer mirror is the structural contract that makes a hook managed
    # by sync-manifest (currently hooks/session_end_transcript.sh).
    consumer_mirror_root = root / ".harness"
    managed_mirror_hooks = {
        candidate.relative_to(plugin_root).as_posix()
        for candidate in (plugin_root / "hooks").glob("*")
        if candidate.is_file()
        and (consumer_mirror_root / candidate.relative_to(plugin_root)).is_file()
    }
    files = [
        candidate.relative_to(plugin_root).as_posix()
        for candidate in plugin_root.rglob("*")
        if candidate.is_file()
        and candidate.relative_to(plugin_root).as_posix() not in ignored_files
        and (
            candidate.relative_to(plugin_root).parts[0] != "hooks"
            or candidate.relative_to(plugin_root).as_posix() in managed_mirror_hooks
        )
    ]
    classified = 0
    unclassified: list[str] = []
    inactive_required: list[str] = []
    for candidate in files:
        matches = [rule for rule in rules if fnmatch.fnmatchcase(candidate, rule[1])]
        if not matches:
            unclassified.append(candidate)
            continue
        # Consumer contract: custom always wins; otherwise the longest glob is
        # the effective classification.  An effective opt-out is intentionally
        # registered but not mirrored.
        effective = max(
            matches,
            key=lambda rule: (1 if rule[0] == "custom" else 0, len(rule[1])),
        )
        if effective[2] and candidate in managed_mirror_hooks:
            inactive_required.append(candidate)
        elif not effective[2]:
            classified += 1
    if unclassified:
        raise CheckFailure(
            "consumer sync-manifest has unclassified managed files: "
            + ", ".join(sorted(unclassified))
        )
    if inactive_required:
        raise CheckFailure(
            "consumer sync-manifest marks required mirror files opt-out: "
            + ", ".join(sorted(inactive_required))
        )
    if classified == 0:
        raise CheckFailure("consumer sync-manifest classifies no active plugin files")


def check_modes(root: Path, entries: list[dict[str, Any]]) -> None:
    required_executables = (CHECKER_PATH, SYNC_SCRIPT_PATH)
    for required in required_executables:
        path = root / required
        if not path.is_file():
            raise CheckFailure(f"required executable source is missing: {required}")
        mode = stat.S_IMODE(path.stat().st_mode)
        if not mode & stat.S_IXUSR:
            raise CheckFailure(f"required source must be owner-executable: {required}")
    for entry in entries:
        if entry["type"] != "file":
            continue
        path = root / entry["source_path"]
        # Other file modes are preserved and verified by target parity.  The two
        # source-side CLI entry points above additionally require owner execute.
        path.stat()


def compare_tree(
    source: Path,
    destination: Path,
    exclusions: dict[str, Any],
    label: str,
) -> None:
    def file_map(base: Path) -> dict[PurePosixPath, Path]:
        result: dict[PurePosixPath, Path] = {}
        if not base.is_dir():
            raise CheckFailure(f"parity target directory is missing: {label}")
        for path in base.rglob("*"):
            if path.is_file():
                relative = PurePosixPath(path.relative_to(base).as_posix())
                if not is_excluded(relative, exclusions):
                    result[relative] = path
        return result

    source_files = file_map(source)
    destination_files = file_map(destination)
    if source_files.keys() != destination_files.keys():
        missing = sorted(source_files.keys() - destination_files.keys(), key=str)
        extra = sorted(destination_files.keys() - source_files.keys(), key=str)
        raise CheckFailure(f"parity path mismatch for {label}: missing={missing}, extra={extra}")
    for relative, source_path in source_files.items():
        destination_path = destination_files[relative]
        if source_path.read_bytes() != destination_path.read_bytes():
            raise CheckFailure(f"parity content mismatch: {label}/{relative}")
        if stat.S_IMODE(source_path.stat().st_mode) != stat.S_IMODE(destination_path.stat().st_mode):
            raise CheckFailure(f"parity permission mismatch: {label}/{relative}")


def generated_content(root: Path, destination: PurePosixPath, generator: str) -> bytes:
    expected_generator = "sync_public_marketplace.sh#public-readme"
    if destination != PurePosixPath("README.md") or generator != expected_generator:
        raise CheckFailure(
            f"unsupported generated contract: {destination} via {generator!r}"
        )
    try:
        result = subprocess.run(
            ["bash", str(root / SYNC_SCRIPT_PATH), "--print-generated", destination.as_posix()],
            cwd=root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise CheckFailure(f"generated content command failed for {destination}: {exc}") from exc
    if result.returncode != 0:
        raise CheckFailure(
            f"generated content command failed for {destination} (exit {result.returncode}): "
            f"{result.stderr.decode(errors='replace').strip()}"
        )
    return result.stdout


def managed_top_levels(entries: list[dict[str, Any]]) -> set[str]:
    return {entry["destination_path"].parts[0] for entry in entries}


def check_target_parity(
    root: Path, target: Path, manifest: dict[str, Any], entries: list[dict[str, Any]]
) -> None:
    if not target.is_dir():
        raise CheckFailure(f"--target is not a directory: {target}")
    exclusions = manifest["directory_exclusions"]
    allowed_top = managed_top_levels(entries) | {".git"}
    unexpected_top = sorted(
        path.name for path in target.iterdir() if path.name not in allowed_top
    )
    if unexpected_top:
        raise CheckFailure(
            "parity target contains unmanaged top-level entries: " + ", ".join(unexpected_top)
        )
    for entry in entries:
        destination = target / entry["destination_path"]
        if entry["type"] == "generated":
            if not destination.is_file():
                raise CheckFailure(f"generated distribution file is missing: {entry['destination_path']}")
            expected_content = generated_content(
                root, entry["destination_path"], str(entry.get("generator", ""))
            )
            if destination.read_bytes() != expected_content:
                raise CheckFailure(f"generated content mismatch: {entry['destination_path']}")
            expected_mode = int(manifest["permission_policy"]["generated_file_mode"], 8)
            if stat.S_IMODE(destination.stat().st_mode) != expected_mode:
                raise CheckFailure(
                    f"generated file permission mismatch: {entry['destination_path']} "
                    f"expected {expected_mode:04o}"
                )
        elif entry["type"] == "file":
            source = root / entry["source_path"]
            if not destination.is_file():
                raise CheckFailure(f"parity target file is missing: {entry['destination_path']}")
            if source.read_bytes() != destination.read_bytes():
                raise CheckFailure(f"parity content mismatch: {entry['destination_path']}")
            if stat.S_IMODE(source.stat().st_mode) != stat.S_IMODE(destination.stat().st_mode):
                raise CheckFailure(f"parity permission mismatch: {entry['destination_path']}")
        else:
            compare_tree(
                root / entry["source_path"],
                destination,
                exclusions,
                entry["destination_path"].as_posix(),
            )


def peel_ref(tag_repo: Path, ref: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(tag_repo), "rev-parse", "--verify", f"{ref}^{{commit}}"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    if result.returncode != 0:
        raise CheckFailure(f"release tag is missing or invalid: {ref}")
    return result.stdout.strip()


def check_release_context(
    records: list[tuple[str, Path, dict[str, Any]]],
    version: str,
    tag_repo: Path,
    release_commit: str,
) -> None:
    expected_commit = peel_ref(tag_repo, release_commit)
    for name, _, _ in records:
        tag = f"refs/tags/{name}--v{version}"
        actual = peel_ref(tag_repo, tag)
        if actual != expected_commit:
            raise CheckFailure(
                f"release tag points to the wrong commit: {tag} -> {actual}, expected {expected_commit}"
            )


def infer_root() -> Path:
    return Path(__file__).resolve().parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run offline plugin distribution checks; release refs are opt-in.",
    )
    parser.add_argument("--repo-root", type=Path, default=infer_root())
    parser.add_argument("--manifest", type=Path)
    parser.add_argument(
        "--target",
        type=Path,
        help="also compare a locally assembled public-repository directory",
    )
    parser.add_argument(
        "--release-commit",
        help="explicitly enable release-context checks against this commit/ref",
    )
    parser.add_argument(
        "--tag-repo",
        type=Path,
        help="local Git repository containing release tags (no fetch/network is performed)",
    )
    parser.add_argument(
        "--skip-official-validator",
        action="store_true",
        help="skip the external claude validator for isolated checker fixtures only",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = args.repo_root.resolve()
    manifest_path = (args.manifest or root / DEFAULT_DISTRIBUTION_MANIFEST).resolve()
    release_requested = args.release_commit is not None or args.tag_repo is not None
    if release_requested and (not args.release_commit or args.tag_repo is None):
        print(
            "ERROR: release-context validation requires both --release-commit and --tag-repo",
            file=sys.stderr,
        )
        return 2
    try:
        manifest, entries = parse_manifest(root, manifest_path)
        records, marketplace = plugin_manifests(root)
        version = check_versions(records, marketplace)
        if not args.skip_official_validator:
            check_official_validation(root, records)
        check_syntax(root, manifest, entries)
        check_hook_targets(root)
        check_sync_manifest(root)
        check_modes(root, entries)
        if args.target is not None:
            check_target_parity(root, args.target.resolve(), manifest, entries)
        if release_requested:
            check_release_context(
                records,
                version,
                args.tag_repo.resolve(),
                args.release_commit,
            )
    except (CheckFailure, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    modes = ["default"]
    if args.target is not None:
        modes.append("parity")
    if release_requested:
        modes.append("release-context")
    print(f"PASS: plugin distribution checks ({', '.join(modes)}; version={version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
