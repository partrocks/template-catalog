#!/usr/bin/env python3
"""
Validate catalog changes:
- Validate all YAML files parse correctly
"""
import os
import sys
import subprocess
from pathlib import Path


def get_template_dirs(repo_root: Path) -> list[str]:
    """Return template dir names (those containing manifest.yaml)."""
    return [
        d.name for d in repo_root.iterdir()
        if d.is_dir() and not d.name.startswith(".") and (d / "manifest.yaml").exists()
    ]


def get_changed_files() -> list[str]:
    """Get files changed in the most recent commit (for push to main)."""
    # HEAD~1 may not exist on first commit
    rev = subprocess.run(
        ["git", "rev-parse", "HEAD~1"],
        capture_output=True,
    )
    if rev.returncode != 0:
        # First commit: all files are "changed"
        result = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    else:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD~1", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    return result.stdout.strip().splitlines() if result.stdout.strip() else []


def get_changed_template_dirs(changed_files: list[str], template_dirs: list[str]) -> set[str]:
    """Return which template directories have changed files."""
    changed = set()
    for f in changed_files:
        parts = f.split("/")
        if len(parts) >= 2 and parts[0] in template_dirs:
            changed.add(parts[0])
    return changed


def validate_yaml_files(repo_root: Path, changed_files: list[str]) -> bool:
    """Validate that changed YAML files parse correctly."""
    try:
        import yaml
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "pyyaml"], check=True)
        import yaml

    yaml_files = [f for f in changed_files if f.endswith((".yaml", ".yml"))]
    errors = []

    for rel_path in yaml_files:
        path = repo_root / rel_path
        if not path.exists():
            continue
        try:
            with open(path) as f:
                yaml.safe_load(f)
        except yaml.YAMLError as e:
            errors.append(f"{rel_path}: {e}")

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return False
    return True


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent.parent
    os.chdir(repo_root)

    template_dirs = get_template_dirs(repo_root)
    changed_files = get_changed_files()
    changed_templates = get_changed_template_dirs(changed_files, template_dirs)

    if not validate_yaml_files(repo_root, changed_files):
        return 1

    print(f"Validated: {', '.join(sorted(changed_templates)) if changed_templates else 'no template changes'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
