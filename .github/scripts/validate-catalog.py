#!/usr/bin/env python3
"""Validate catalog changes."""
import os
import re
import sys
import subprocess
from pathlib import Path
from typing import Any


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


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in overlay.items():
        if (
            key in out
            and isinstance(out[key], dict)
            and isinstance(value, dict)
        ):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def merge_target(parent: dict[str, Any], child: dict[str, Any]) -> dict[str, Any]:
    return {
        "engine": child.get("engine", parent.get("engine")),
        "source": child.get("source", parent.get("source")),
        "capabilities": (
            child.get("capabilities")
            if isinstance(child.get("capabilities"), list) and len(child.get("capabilities")) > 0
            else parent.get("capabilities", [])
        ),
        "constraints": deep_merge(
            parent.get("constraints", {}) if isinstance(parent.get("constraints"), dict) else {},
            child.get("constraints", {}) if isinstance(child.get("constraints"), dict) else {},
        ),
        "outputs": (
            child.get("outputs")
            if isinstance(child.get("outputs"), list) and len(child.get("outputs")) > 0
            else parent.get("outputs", [])
        ),
        "presets": (
            child.get("presets")
            if isinstance(child.get("presets"), list) and len(child.get("presets")) > 0
            else parent.get("presets", [])
        ),
    }


def resolve_environment(
    env_key: str,
    environments: dict[str, Any],
    resolving: set[str],
    cache: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if env_key in cache:
        return cache[env_key]
    if env_key in resolving:
        raise ValueError(f"environments.yaml: extends cycle detected at {env_key}")
    if env_key not in environments:
        raise ValueError(f"environments.yaml: missing environment {env_key}")
    resolving.add(env_key)
    raw_env = environments[env_key]
    if not isinstance(raw_env, dict):
        raise ValueError(f"environments.yaml: environment {env_key} must be an object")

    parent_key = raw_env.get("extends")
    merged: dict[str, Any] = {
        "id": raw_env.get("id", env_key),
        "runtime": raw_env.get("runtime"),
        "abstract": raw_env.get("abstract") is True,
        "deploy": {"targets": {}},
    }

    if isinstance(parent_key, str) and parent_key:
        parent = resolve_environment(parent_key, environments, resolving, cache)
        merged["runtime"] = merged["runtime"] or parent.get("runtime")
        merged["deploy"] = {
            "targets": dict(parent.get("deploy", {}).get("targets", {}))
        }

    deploy = raw_env.get("deploy")
    deploy_targets = deploy.get("targets") if isinstance(deploy, dict) else None
    if isinstance(deploy_targets, dict):
        next_targets = dict(merged.get("deploy", {}).get("targets", {}))
        for provider, target in deploy_targets.items():
            if not isinstance(target, dict):
                continue
            parent_target = next_targets.get(provider, {})
            if not isinstance(parent_target, dict):
                parent_target = {}
            next_targets[provider] = merge_target(parent_target, target)
        merged["deploy"] = {"targets": next_targets}

    resolving.remove(env_key)
    cache[env_key] = merged
    return merged


def collect_interpolation_tokens(value: str) -> list[str]:
    return [token.strip() for token in re.findall(r"\{\{\s*([^}]+)\s*\}\}", value)]


def extract_tf_outputs(tf_source: str) -> set[str]:
    return set(re.findall(r'output\s+"([^"]+)"\s*\{', tf_source))


def validate_template_deploy_contract(repo_root: Path, template_dir: str) -> list[str]:
    errors: list[str] = []
    template_path = repo_root / template_dir
    env_path = template_path / "environments.yaml"
    if not env_path.exists():
        return errors

    try:
        import yaml
    except ImportError:
        return [f"{template_dir}: pyyaml is required for catalog validation"]

    with open(env_path, encoding="utf-8") as f:
        env_doc = yaml.safe_load(f) or {}
    envs = env_doc.get("environments")
    if not isinstance(envs, dict):
        return [f"{template_dir}/environments.yaml: missing or invalid environments object"]

    resolved_cache: dict[str, dict[str, Any]] = {}
    for env_key in envs.keys():
        try:
            resolved_env = resolve_environment(env_key, envs, set(), resolved_cache)
        except ValueError as exc:
            errors.append(f"{template_dir}/environments.yaml: {exc}")
            continue

        if resolved_env.get("abstract") is True:
            continue
        if resolved_env.get("runtime") != "cloud":
            continue

        targets = resolved_env.get("deploy", {}).get("targets", {})
        if not isinstance(targets, dict):
            continue

        for provider, target in targets.items():
            if not isinstance(target, dict):
                continue
            engine = target.get("engine")
            source = target.get("source")
            if not isinstance(engine, str) or not isinstance(source, str):
                errors.append(
                    f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                    f"deploy.targets.{provider} must define engine and source"
                )
                continue

            source_path = template_path / "_resources" / source
            if not source_path.exists():
                errors.append(
                    f"{template_dir}/environments.yaml: deploy.targets.{provider}.source "
                    f"references missing file '{source}'"
                )
                continue

            outputs = target.get("outputs")
            if not isinstance(outputs, list):
                errors.append(
                    f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                    f"deploy.targets.{provider}.outputs must be an array"
                )
                continue

            key_counts: dict[str, int] = {}
            for row in outputs:
                if not isinstance(row, dict):
                    continue
                key = row.get("key")
                if isinstance(key, str) and key.strip():
                    key_counts[key.strip()] = key_counts.get(key.strip(), 0) + 1

            for key, count in key_counts.items():
                if count > 1:
                    errors.append(
                        f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                        f"deploy.targets.{provider}.outputs has duplicate key '{key}'"
                    )

            for required_key in ["public_url", "dns_name"]:
                if key_counts.get(required_key, 0) == 0:
                    errors.append(
                        f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                        f"deploy.targets.{provider}.outputs must include '{required_key}'"
                    )

            if provider == "aws" and key_counts.get("canonical_hosted_zone_id", 0) == 0:
                errors.append(
                    f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                    f"deploy.targets.{provider}.outputs must include 'canonical_hosted_zone_id'"
                )

            tf_outputs = extract_tf_outputs(source_path.read_text(encoding="utf-8"))
            for row in outputs:
                if not isinstance(row, dict):
                    continue
                value = row.get("value")
                if not isinstance(value, str):
                    continue
                for token in collect_interpolation_tokens(value):
                    # Skip dynamic path variables like environment.id/release.tag.
                    if "." in token:
                        continue
                    if token and token not in tf_outputs:
                        errors.append(
                            f"{template_dir}/environments.yaml: environment '{resolved_env.get('id', env_key)}' "
                            f"deploy.targets.{provider}.outputs references '{{{{ {token} }}}}' "
                            f"but '{source}' does not declare output \"{token}\""
                        )
    return errors


def validate_yaml_files(repo_root: Path, changed_files: list[str]) -> bool:
    """Validate that changed YAML files parse correctly."""
    try:
        import yaml
    except ImportError:
        print("ERROR: pyyaml is required to run catalog validation.", file=sys.stderr)
        return False

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

    contract_errors: list[str] = []
    for template_dir in sorted(changed_templates):
        contract_errors.extend(validate_template_deploy_contract(repo_root, template_dir))
    if contract_errors:
        for err_msg in contract_errors:
            print(f"ERROR: {err_msg}", file=sys.stderr)
        return 1

    print(f"Validated: {', '.join(sorted(changed_templates)) if changed_templates else 'no template changes'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
