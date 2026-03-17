#!/usr/bin/env python3
"""Validate catalog changes for preset-namespace schema v2."""
import os
import re
import sys
import subprocess
from pathlib import Path
from typing import Any


def get_template_dirs(repo_root: Path) -> list[str]:
    return [
        d.name for d in repo_root.iterdir()
        if d.is_dir() and not d.name.startswith(".") and (d / "manifest.yaml").exists()
    ]


def get_changed_files() -> list[str]:
    rev = subprocess.run(["git", "rev-parse", "HEAD~1"], capture_output=True)
    if rev.returncode != 0:
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
    changed = set()
    for f in changed_files:
        parts = f.split("/")
        if len(parts) >= 2 and parts[0] in template_dirs:
            changed.add(parts[0])
    return changed


def collect_interpolation_tokens(value: str) -> list[str]:
    return [token.strip() for token in re.findall(r"\{\{\s*([^}]+)\s*\}\}", value)]


def extract_tf_outputs(tf_source: str) -> set[str]:
    return set(re.findall(r'output\s+"([^"]+)"\s*\{', tf_source))


def normalize_preset_file_doc(doc: Any) -> dict[str, Any] | None:
    if not isinstance(doc, dict):
        return None
    preset = doc.get("preset")
    if isinstance(preset, dict):
        return preset
    return doc


def validate_namespace_preset(
    template_path: Path,
    template_dir: str,
    env_id: str,
    namespace: str,
    errors: list[str],
    yaml: Any,
) -> None:
    if not re.match(r"^[^/]+/[^/]+$", namespace):
        errors.append(
            f"{template_dir}/environments.yaml: environment '{env_id}' has invalid preset namespace '{namespace}' (expected provider/preset)"
        )
        return
    provider, preset_id = namespace.split("/", 1)
    package_path = template_path / "infra" / provider / preset_id
    preset_yaml_path = package_path / "preset.yaml"
    if not preset_yaml_path.exists():
        errors.append(
            f"{template_dir}/environments.yaml: environment '{env_id}' references missing preset package '{namespace}'"
        )
        return

    with open(preset_yaml_path, encoding="utf-8") as f:
        raw_doc = yaml.safe_load(f) or {}
    preset_doc = normalize_preset_file_doc(raw_doc)
    if not isinstance(preset_doc, dict):
        errors.append(f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: invalid preset.yaml structure")
        return

    required_fields = ["provider", "id", "label", "engine", "source", "outputs"]
    for field in required_fields:
        if field not in preset_doc:
            errors.append(
                f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: missing required field '{field}'"
            )
    if preset_doc.get("provider") != provider:
        errors.append(
            f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: provider must be '{provider}'"
        )
    if preset_doc.get("id") != preset_id:
        errors.append(
            f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: id must be '{preset_id}'"
        )
    source = preset_doc.get("source")
    if isinstance(source, str) and source.strip():
        source_path = (package_path / source.strip()).resolve()
        if not source_path.exists():
            errors.append(
                f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: source '{source}' does not exist in package"
            )
        else:
            outputs = preset_doc.get("outputs")
            output_keys = set()
            if isinstance(outputs, list):
                tf_outputs = extract_tf_outputs(source_path.read_text(encoding="utf-8"))
                for row in outputs:
                    if not isinstance(row, dict):
                        continue
                    key = row.get("key")
                    value = row.get("value")
                    if isinstance(key, str) and key.strip():
                        output_keys.add(key.strip())
                    if isinstance(value, str):
                        for token in collect_interpolation_tokens(value):
                            if "." in token:
                                continue
                            if token and token not in tf_outputs:
                                errors.append(
                                    f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: outputs references '{{{{ {token} }}}}' but source '{source}' has no output '{token}'"
                                )
            for required_output in ["public_url", "dns_name"]:
                if required_output not in output_keys:
                    errors.append(
                        f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: outputs must include '{required_output}'"
                    )
            if provider == "aws" and "canonical_hosted_zone_id" not in output_keys:
                errors.append(
                    f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: outputs must include 'canonical_hosted_zone_id' for AWS"
                )
    else:
        errors.append(
            f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: source must be a non-empty string"
        )

    ui = preset_doc.get("ui")
    if isinstance(ui, dict):
        images = ui.get("images")
        if images is not None and not isinstance(images, list):
            errors.append(
                f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: ui.images must be an array"
            )
        if isinstance(images, list):
            for image_path in images:
                if not isinstance(image_path, str) or not image_path.strip():
                    errors.append(
                        f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: ui.images entries must be non-empty strings"
                    )
                    continue
                absolute_image_path = template_path / image_path.strip().lstrip("/")
                if not absolute_image_path.exists():
                    errors.append(
                        f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: ui.images references missing file '{image_path}'"
                    )


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
    if env_doc.get("schemaVersion") != 2:
        errors.append(f"{template_dir}/environments.yaml: schemaVersion must be 2")
        return errors
    envs = env_doc.get("environments")
    if not isinstance(envs, dict):
        errors.append(f"{template_dir}/environments.yaml: missing or invalid environments object")
        return errors

    for env_key, env_raw in envs.items():
        if not isinstance(env_raw, dict):
            errors.append(f"{template_dir}/environments.yaml: environment '{env_key}' must be an object")
            continue
        env_id = env_raw.get("id", env_key)
        runtime = env_raw.get("runtime")
        if runtime == "cloud":
            deploy = env_raw.get("deploy")
            presets = deploy.get("presets") if isinstance(deploy, dict) else None
            if not isinstance(presets, list) or len(presets) == 0:
                errors.append(
                    f"{template_dir}/environments.yaml: environment '{env_id}' runtime cloud requires deploy.presets"
                )
                continue
            seen_namespaces: set[str] = set()
            for namespace in presets:
                if not isinstance(namespace, str):
                    errors.append(
                        f"{template_dir}/environments.yaml: environment '{env_id}' deploy.presets entries must be strings"
                    )
                    continue
                ns = namespace.strip()
                if ns in seen_namespaces:
                    errors.append(
                        f"{template_dir}/environments.yaml: environment '{env_id}' deploy.presets has duplicate namespace '{ns}'"
                    )
                    continue
                seen_namespaces.add(ns)
                validate_namespace_preset(template_path, template_dir, str(env_id), ns, errors, yaml)
        if "abstract" in env_raw or "extends" in env_raw:
            errors.append(
                f"{template_dir}/environments.yaml: environment '{env_id}' cannot use abstract/extends in schema v2"
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
