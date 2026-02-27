#!/usr/bin/env python3
"""
Update catalog after push to main:
- Bump manifest version if template changed but version wasn't updated
- Regenerate info.yaml from all manifests
"""
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "pyyaml"], check=True)
    import yaml


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SEMVER_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def get_template_dirs() -> list[Path]:
    """Return paths to template directories (those containing manifest.yaml)."""
    return [
        d for d in REPO_ROOT.iterdir()
        if d.is_dir() and not d.name.startswith(".") and (d / "manifest.yaml").exists()
    ]


def get_changed_template_dirs() -> set[str]:
    """Return template dir names that have changes in the latest commit."""
    import subprocess
    # HEAD~1 may not exist on first commit
    result = subprocess.run(
        ["git", "rev-parse", "HEAD~1"],
        capture_output=True,
        cwd=REPO_ROOT,
    )
    if result.returncode != 0:
        # First commit: treat all templates as changed
        return {d.name for d in get_template_dirs()}
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD~1", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
        cwd=REPO_ROOT,
    )
    files = result.stdout.strip().splitlines() if result.stdout.strip() else []
    template_dirs = [d.name for d in get_template_dirs()]
    return {f.split("/")[0] for f in files if "/" in f and f.split("/")[0] in template_dirs}


def get_manifest_version(path: Path) -> str | None:
    """Extract version from manifest.yaml."""
    with open(path) as f:
        data = yaml.safe_load(f)
    # Handle both manifest: { version: ... } and top-level version
    manifest = data.get("manifest", data)
    version = manifest.get("version")
    return str(version) if version else None


def version_was_bumped(template_dir: str) -> bool:
    """Check if the manifest version was changed in this commit."""
    import subprocess
    result = subprocess.run(["git", "rev-parse", "HEAD~1"], capture_output=True, cwd=REPO_ROOT)
    if result.returncode != 0:
        return False  # First commit: we'll bump
    manifest_path = f"{template_dir}/manifest.yaml"
    result = subprocess.run(
        ["git", "diff", "HEAD~1", "HEAD", "--", manifest_path],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.returncode != 0 or not result.stdout:
        return False
    # Check if a version line was changed
    return "version:" in result.stdout


def bump_patch_version(version: str) -> str:
    """Increment patch component of semver."""
    m = SEMVER_PATTERN.match(version.strip())
    if not m:
        return version
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    return f"{major}.{minor}.{patch + 1}"


def bump_manifest_version(template_dir: str) -> bool:
    """Bump version in manifest.yaml. Returns True if file was modified."""
    manifest_path = REPO_ROOT / template_dir / "manifest.yaml"
    with open(manifest_path) as f:
        data = yaml.safe_load(f)

    manifest = data.get("manifest", data)
    old_version = manifest.get("version", "0.0.0")
    new_version = bump_patch_version(str(old_version))
    manifest["version"] = new_version

    with open(manifest_path, "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"Bumped {template_dir} version: {old_version} -> {new_version}")
    return True


def build_info_yaml() -> dict:
    """Build info.yaml content from all manifests (for fast search)."""
    templates = []
    for template_dir in get_template_dirs():
        manifest_path = template_dir / "manifest.yaml"
        with open(manifest_path) as f:
            data = yaml.safe_load(f)
        manifest = data.get("manifest", data)
        templates.append({
            "id": manifest.get("id", template_dir.name),
            "name": manifest.get("name"),
            "description": manifest.get("description"),
            "version": manifest.get("version"),
            "tags": manifest.get("tags", []),
            "keywords": manifest.get("keywords", []),
        })
    return {"templates": templates}


def main() -> int:
    os.chdir(REPO_ROOT)

    changed = get_changed_template_dirs()
    modified = False

    # Bump version for changed templates where author didn't already bump
    for template_dir in sorted(changed):
        if not version_was_bumped(template_dir):
            bump_manifest_version(template_dir)
            modified = True

    # Regenerate info.yaml from all manifests
    info_content = build_info_yaml()
    info_path = REPO_ROOT / "info.yaml"
    existing = info_path.read_text() if info_path.exists() else ""
    new_content = yaml.dump(info_content, default_flow_style=False, sort_keys=False, allow_unicode=True)
    if existing != new_content:
        info_path.write_text(new_content)
        print("Updated info.yaml")
        modified = True

    return 0


if __name__ == "__main__":
    sys.exit(main())
