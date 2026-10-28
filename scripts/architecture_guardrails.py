"""Deterministic import-boundary checks for TelStorage's Dart architecture."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

DIRECTIVE_PATTERN = re.compile(r"\b(?:import|export|part)\s+([^;]+);", re.DOTALL)
URI_PATTERN = re.compile(r"['\"]([^'\"]+)['\"]")
CONFLICT_MARKER_PATTERN = re.compile(
    r"^(?:<<<<<<< |=======|>>>>>>>)(?:.*)$", re.MULTILINE
)


def _source_files(root: Path) -> list[Path]:
    return sorted((root / "lib").rglob("*.dart"))


def _resolve_import(source: Path, raw_import: str, root: Path) -> str | None:
    if raw_import.startswith("package:telstorage/"):
        target = root / "lib" / raw_import.removeprefix("package:telstorage/")
    elif raw_import.startswith("."):
        target = (source.parent / raw_import).resolve()
    else:
        return None

    try:
        return target.relative_to(root / "lib").as_posix()
    except ValueError:
        return None


def _violates_boundary(source: str, target: str) -> bool:
    source_parts = source.split("/")
    target_parts = target.split("/")

    if source_parts[0] == "core" and target_parts[0] in {"features", "shared"}:
        return True
    if source_parts[0] == "shared" and target_parts[0] == "features":
        return True

    if (
        source_parts[0] == "features"
        and target_parts[0] == "features"
        and len(source_parts) >= 3
        and len(target_parts) >= 3
    ):
        source_layer, target_layer = source_parts[2], target_parts[2]
        return (
            (source_layer == "domain" and target_layer in {"data", "presentation"})
            or (source_layer == "data" and target_layer == "presentation")
            or (source_layer == "presentation" and target_layer == "data")
        )

    return False


def inspect_architecture(root: Path) -> tuple[list[str], list[str]]:
    root = root.resolve()
    allowlist_path = root / "scripts" / "architecture_allowlist.json"
    allowlist: dict[str, str] = json.loads(allowlist_path.read_text(encoding="utf-8"))
    locator_allowlist_path = root / "scripts" / "presentation_service_locator_allowlist.json"
    locator_allowlist: dict[str, str] = json.loads(
        locator_allowlist_path.read_text(encoding="utf-8")
    )
    found_edges: set[str] = set()
    found_locator_users: set[str] = set()
    violations: list[str] = []

    for source_path in _source_files(root):
        source = source_path.relative_to(root).as_posix()
        source_lib_path = source.removeprefix("lib/")
        content = source_path.read_text(encoding="utf-8")
        if source_lib_path.startswith("features/") and "/presentation/" in source_lib_path:
            if "ServiceLocator.instance" in content:
                found_locator_users.add(source)
                if source not in locator_allowlist:
                    violations.append(
                        f"{source}: new direct ServiceLocator.instance use in feature presentation"
                    )

        if source_path.name.endswith("_view_model.dart") and not re.search(
            r"\bclass\s+\w+\s+extends\s+(?:Bloc|Cubit)\s*<|"
            r"\bclass\s+\w+\s+extends\s+ChangeNotifier\b",
            content,
        ):
            violations.append(
                f"{source}: *_view_model.dart must declare a Bloc, Cubit, or ChangeNotifier state holder"
            )
        for marker in CONFLICT_MARKER_PATTERN.findall(content):
            violations.append(f"{source}: unresolved merge marker {marker}")

        for directive in DIRECTIVE_PATTERN.findall(content):
            for raw_import in URI_PATTERN.findall(directive):
                target_lib_path = _resolve_import(source_path, raw_import, root)
                if target_lib_path is None:
                    continue
                target = f"lib/{target_lib_path}"
                if not _violates_boundary(source_lib_path, target_lib_path):
                    continue

                edge = f"{source} -> {target}"
                found_edges.add(edge)
                if edge not in allowlist:
                    violations.append(f"{edge}: forbidden architecture dependency")

    stale_allowlist = sorted(
        [f"{edge} [legacy dependency]" for edge in set(allowlist) - found_edges]
        + [
            f"{path} [presentation ServiceLocator]"
            for path in set(locator_allowlist) - found_locator_users
        ]
    )
    return violations, stale_allowlist


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    violations, stale_allowlist = inspect_architecture(root)
    if violations:
        print("Architecture guardrails failed:")
        for violation in violations:
            print(f"  - {violation}")
    if stale_allowlist:
        print("Remove resolved entries from the relevant scripts allowlist:")
        for edge in stale_allowlist:
            print(f"  - {edge}")
    if violations or stale_allowlist:
        return 1

    count = len(json.loads((root / "scripts/architecture_allowlist.json").read_text(encoding="utf-8")))
    locator_count = len(json.loads((root / "scripts/presentation_service_locator_allowlist.json").read_text(encoding="utf-8")))
    print(f"Architecture guardrails passed ({count} legacy dependency edges; {locator_count} presentation ServiceLocator users).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
