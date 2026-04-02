#!/usr/bin/env python3
"""Validate catalog changes for environments.yaml schema v3 and provider-native infra presets."""
import os
import re
import sys
import subprocess
from pathlib import Path
from typing import Any

ENVIRONMENTS_SCHEMA_VERSION = 3

# Align with pr-desktop INFRA_SLICE_KINDS_ALL / INFRA_SLICE_TAXONOMY_VERSION 2.
INFRA_SLICE_KINDS: frozenset[str] = frozenset(
    {
        "gateway",
        "static_site",
        "object_storage",
        "app_runtime",
        "database",
        "container_registry",
        "edge_binding",
        "edge_workload",
        "network",
    }
)


def get_template_dirs(repo_root: Path) -> list[str]:
    return [
        d.name
        for d in repo_root.iterdir()
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


def normalize_preset_file_doc(doc: Any) -> dict[str, Any] | None:
    if not isinstance(doc, dict):
        return None
    preset = doc.get("preset")
    if isinstance(preset, dict):
        return preset
    return doc


def validate_preset_outputs_keys(
    preset_doc: dict[str, Any],
    rel_display: str,
    provider: str,
    errors: list[str],
) -> None:
    outputs = preset_doc.get("outputs")
    output_keys: set[str] = set()
    if isinstance(outputs, list):
        for row in outputs:
            if not isinstance(row, dict):
                continue
            key = row.get("key")
            if isinstance(key, str) and key.strip():
                output_keys.add(key.strip())
    for required_output in ["public_url", "dns_name"]:
        if required_output not in output_keys:
            errors.append(f"{rel_display}: outputs must include '{required_output}'")
    if provider == "aws" and "canonical_hosted_zone_id" not in output_keys:
        errors.append(f"{rel_display}: outputs must include 'canonical_hosted_zone_id' for AWS")


def validate_provider_native_slices(
    preset_doc: dict[str, Any],
    rel_display: str,
    errors: list[str],
) -> None:
    slices = preset_doc.get("slices")
    if not isinstance(slices, list) or len(slices) == 0:
        errors.append(f"{rel_display}: provider-native presets must declare a non-empty 'slices' list")
        return
    for i, s in enumerate(slices):
        if not isinstance(s, dict):
            errors.append(f"{rel_display}: slices[{i}] must be an object")
            continue
        sk = s.get("sliceKind")
        sf = s.get("sliceFlavor")
        if not isinstance(sk, str) or not sk.strip():
            errors.append(f"{rel_display}: slices[{i}].sliceKind must be a non-empty string")
        elif sk.strip() not in INFRA_SLICE_KINDS:
            errors.append(
                f"{rel_display}: slices[{i}].sliceKind '{sk.strip()}' is not a canonical "
                f"infra slice kind (see INFRA_SLICE_TAXONOMY in PartRocks provider-control)"
            )
        if not isinstance(sf, str) or not sf.strip():
            errors.append(f"{rel_display}: slices[{i}].sliceFlavor must be a non-empty string")
        ik = s.get("instanceKey")
        if ik is not None and (not isinstance(ik, str) or not ik.strip()):
            errors.append(f"{rel_display}: slices[{i}].instanceKey must be a non-empty string when set")
        sh = s.get("shareable")
        if sh is not None and not isinstance(sh, bool):
            errors.append(f"{rel_display}: slices[{i}].shareable must be a boolean when set")


def validate_optional_deploy_slices(
    deploy: dict[str, Any],
    rel_prefix: str,
    errors: list[str],
) -> None:
    """Validate deploy.slices when present (same slice shape as preset.yaml slices)."""
    raw = deploy.get("slices")
    if raw is None:
        return
    if not isinstance(raw, list):
        errors.append(f"{rel_prefix}: deploy.slices must be an array when set")
        return
    for i, s in enumerate(raw):
        if not isinstance(s, dict):
            errors.append(f"{rel_prefix}: deploy.slices[{i}] must be an object")
            continue
        sk = s.get("sliceKind")
        sf = s.get("sliceFlavor")
        if not isinstance(sk, str) or not sk.strip():
            errors.append(f"{rel_prefix}: deploy.slices[{i}].sliceKind must be a non-empty string")
        elif sk.strip() not in INFRA_SLICE_KINDS:
            errors.append(
                f"{rel_prefix}: deploy.slices[{i}].sliceKind '{sk.strip()}' is not a canonical "
                f"infra slice kind (see INFRA_SLICE_TAXONOMY in PartRocks provider-control)"
            )
        if not isinstance(sf, str) or not sf.strip():
            errors.append(f"{rel_prefix}: deploy.slices[{i}].sliceFlavor must be a non-empty string")
        ik = s.get("instanceKey")
        if ik is not None and (not isinstance(ik, str) or not ik.strip()):
            errors.append(
                f"{rel_prefix}: deploy.slices[{i}].instanceKey must be a non-empty string when set"
            )
        sh = s.get("shareable")
        if sh is not None and not isinstance(sh, bool):
            errors.append(f"{rel_prefix}: deploy.slices[{i}].shareable must be a boolean when set")
        refs = s.get("refs")
        if refs is not None:
            if not isinstance(refs, list):
                errors.append(f"{rel_prefix}: deploy.slices[{i}].refs must be an array when set")
            else:
                for j, ref in enumerate(refs):
                    if not isinstance(ref, dict):
                        errors.append(
                            f"{rel_prefix}: deploy.slices[{i}].refs[{j}] must be an object"
                        )
                        continue
                    rel = ref.get("relation")
                    tik = ref.get("targetInstanceKey")
                    if not isinstance(rel, str) or not rel.strip():
                        errors.append(
                            f"{rel_prefix}: deploy.slices[{i}].refs[{j}] requires relation"
                        )
                    if not isinstance(tik, str) or not tik.strip():
                        errors.append(
                            f"{rel_prefix}: deploy.slices[{i}].refs[{j}] requires targetInstanceKey"
                        )
        params = s.get("parameters")
        if params is not None and (not isinstance(params, dict) or isinstance(params, list)):
            errors.append(f"{rel_prefix}: deploy.slices[{i}].parameters must be an object when set")


def validate_boot_script_for_cloud(
    template_dir: str,
    env_id: str,
    env_raw: dict[str, Any],
    has_presets: bool,
    errors: list[str],
) -> None:
    """Schema v3: cloud + deploy.presets requires boot.script relative to _resources/."""
    if not has_presets:
        return
    prefix = f"{template_dir}/environments.yaml"
    boot = env_raw.get("boot")
    if boot is None:
        errors.append(
            f"{prefix}: environment '{env_id}' cloud runtime with deploy.presets requires "
            "boot.script (path under _resources/, e.g. _deploy/hooks/cloud-boot.sh)"
        )
        return
    if not isinstance(boot, dict):
        errors.append(f"{prefix}: environment '{env_id}' boot must be an object with script")
        return
    script_raw = boot.get("script")
    if not isinstance(script_raw, str) or not script_raw.strip():
        errors.append(f"{prefix}: environment '{env_id}' boot.script is required and must be a string")
        return
    s = script_raw.strip()
    if s.startswith("_resources/"):
        s = s[len("_resources/") :]
    if s.startswith("/"):
        errors.append(
            f"{prefix}: environment '{env_id}' boot.script must be relative to _resources/, not absolute"
        )
        return
    segments = [x for x in s.split("/") if x]
    if not segments:
        errors.append(
            f"{prefix}: environment '{env_id}' boot.script must be a non-empty path relative to _resources/"
        )
        return
    for seg in segments:
        if seg == "..":
            errors.append(
                f"{prefix}: environment '{env_id}' boot.script must not contain '..'"
            )
            return
        if seg == ".":
            errors.append(
                f"{prefix}: environment '{env_id}' boot.script must not contain '.' path segments"
            )
            return


def validate_preset_document(
    preset_doc: dict[str, Any],
    rel_display: str,
    expected_provider: str | None,
    expected_preset_id: str | None,
    errors: list[str],
) -> None:
    required_fields = ["provider", "id", "label", "engine", "outputs"]
    for field in required_fields:
        if field not in preset_doc:
            errors.append(f"{rel_display}: missing required field '{field}'")

    provider = preset_doc.get("provider")
    if not isinstance(provider, str):
        errors.append(f"{rel_display}: provider must be a string")
        return
    provider = provider.strip()
    if expected_provider is not None and provider != expected_provider:
        errors.append(f"{rel_display}: provider must be '{expected_provider}'")

    preset_id = preset_doc.get("id")
    if not isinstance(preset_id, str):
        errors.append(f"{rel_display}: id must be a string")
        return
    preset_id = preset_id.strip()
    if expected_preset_id is not None and preset_id != expected_preset_id:
        errors.append(f"{rel_display}: id must be '{expected_preset_id}'")

    engine = preset_doc.get("engine")
    if not isinstance(engine, str) or not engine.strip():
        errors.append(f"{rel_display}: engine must be a non-empty string")
        return
    engine_norm = engine.strip().lower()
    if engine_norm != "provider-native":
        errors.append(
            f"{rel_display}: engine must be 'provider-native' (got '{engine}')"
        )

    source = preset_doc.get("source")
    if isinstance(source, str) and source.strip():
        errors.append(
            f"{rel_display}: 'source' (IaC file) must not be set for provider-native presets; remove '{source}'"
        )

    validate_provider_native_slices(preset_doc, rel_display, errors)
    validate_preset_outputs_keys(preset_doc, rel_display, provider, errors)

    omit = preset_doc.get("omitShareableResourceIds")
    if omit is not None:
        if not isinstance(omit, list):
            errors.append(
                f"{rel_display}: omitShareableResourceIds must be an array when set"
            )
        else:
            seen_omit: set[str] = set()
            for i, item in enumerate(omit):
                if not isinstance(item, str) or not item.strip():
                    errors.append(
                        f"{rel_display}: omitShareableResourceIds[{i}] must be a non-empty string"
                    )
                elif item.strip() in seen_omit:
                    errors.append(
                        f"{rel_display}: omitShareableResourceIds has duplicate '{item.strip()}'"
                    )
                else:
                    seen_omit.add(item.strip())

    ui = preset_doc.get("ui")
    if isinstance(ui, dict):
        images = ui.get("images")
        if images is not None and not isinstance(images, list):
            errors.append(f"{rel_display}: ui.images must be an array")
        if isinstance(images, list):
            for image_path in images:
                if not isinstance(image_path, str) or not image_path.strip():
                    errors.append(f"{rel_display}: ui.images entries must be non-empty strings")


def _validate_ui_images_exist(
    template_path: Path,
    template_dir: str,
    preset_yaml_path: Path,
    preset_doc: dict[str, Any],
    errors: list[str],
) -> None:
    rel_display = f"{template_dir}/{preset_yaml_path.relative_to(template_path)}"
    ui = preset_doc.get("ui")
    if not isinstance(ui, dict):
        return
    images = ui.get("images")
    if not isinstance(images, list):
        return
    for image_path in images:
        if not isinstance(image_path, str) or not image_path.strip():
            continue
        absolute_image_path = template_path / image_path.strip().lstrip("/")
        if not absolute_image_path.exists():
            errors.append(f"{rel_display}: ui.images references missing file '{image_path}'")


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
            f"{template_dir}/environments.yaml: environment '{env_id}' has invalid preset namespace "
            f"'{namespace}' (expected provider/preset)"
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
        errors.append(
            f"{template_dir}/{preset_yaml_path.relative_to(template_path)}: invalid preset.yaml structure"
        )
        return

    rel_display = f"{template_dir}/{preset_yaml_path.relative_to(template_path)}"
    if preset_doc.get("provider") != provider:
        errors.append(f"{rel_display}: provider must be '{provider}'")
    if preset_doc.get("id") != preset_id:
        errors.append(f"{rel_display}: id must be '{preset_id}'")
    _validate_ui_images_exist(template_path, template_dir, preset_yaml_path, preset_doc, errors)


def collect_dot_tf_paths_under_infra(template_path: Path) -> list[Path]:
    infra = template_path / "infra"
    if not infra.is_dir():
        return []
    return sorted(infra.rglob("*.tf"))


def validate_no_dot_tf_under_infra(template_path: Path, template_dir: str, errors: list[str]) -> None:
    for path in collect_dot_tf_paths_under_infra(template_path):
        errors.append(
            f"{template_dir}: remove '{path.relative_to(template_path)}' "
            "(.tf under infra is not supported; use provider-native presets)"
        )


def validate_orphan_infra_presets(template_path: Path, template_dir: str, errors: list[str], yaml: Any) -> None:
    """Ensure every infra preset package validates even if not referenced by environments.yaml."""
    infra = template_path / "infra"
    if not infra.is_dir():
        return
    for preset_yaml_path in sorted(infra.rglob("preset.yaml")):
        with open(preset_yaml_path, encoding="utf-8") as f:
            raw_doc = yaml.safe_load(f) or {}
        preset_doc = normalize_preset_file_doc(raw_doc)
        rel_display = f"{template_dir}/{preset_yaml_path.relative_to(template_path)}"
        if not isinstance(preset_doc, dict):
            errors.append(f"{rel_display}: invalid preset.yaml structure")
            continue
        # Infer expected provider/id from path …/infra/<provider>/<preset_id>/preset.yaml
        try:
            rel_parts = preset_yaml_path.relative_to(infra).parts
            if len(rel_parts) >= 3 and rel_parts[-1] == "preset.yaml":
                exp_provider = rel_parts[0]
                exp_id = rel_parts[1]
            else:
                exp_provider, exp_id = None, None
        except ValueError:
            exp_provider, exp_id = None, None
        validate_preset_document(preset_doc, rel_display, exp_provider, exp_id, errors)
        _validate_ui_images_exist(template_path, template_dir, preset_yaml_path, preset_doc, errors)


def validate_resources_yaml(template_path: Path, template_dir: str, errors: list[str]) -> None:
    """Gateway resources must declare sliceFlavor; legacy gatewayFlavor/awsGatewayType forbidden."""
    path = template_path / "resources.yaml"
    if not path.is_file():
        return
    try:
        import yaml
    except ImportError:
        return
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}
    resources = doc.get("resources")
    prefix = f"{template_dir}/resources.yaml"
    if resources is None:
        return
    if not isinstance(resources, list):
        errors.append(f"{prefix}: 'resources' must be an array when set")
        return
    for i, row in enumerate(resources):
        if not isinstance(row, dict):
            errors.append(f"{prefix}: resources[{i}] must be an object")
            continue
        if row.get("kind") != "gateway":
            continue
        if "gatewayFlavor" in row or "awsGatewayType" in row:
            errors.append(
                f"{prefix}: resources[{i}] must use sliceFlavor, not gatewayFlavor/awsGatewayType "
                "(remove legacy top-level keys)"
            )
        cons = row.get("constraints")
        if isinstance(cons, dict):
            if "gatewayFlavor" in cons or "awsGatewayType" in cons:
                errors.append(
                    f"{prefix}: resources[{i}] gateway constraints must use sliceFlavor, "
                    "not gatewayFlavor/awsGatewayType"
                )
        top_sf = row.get("sliceFlavor")
        cons_sf = cons.get("sliceFlavor") if isinstance(cons, dict) else None
        top_s = top_sf.strip() if isinstance(top_sf, str) else ""
        cons_s = cons_sf.strip() if isinstance(cons_sf, str) else ""
        if top_s and cons_s and top_s != cons_s:
            errors.append(
                f"{prefix}: resources[{i}] sliceFlavor conflict (top-level vs constraints)"
            )
        if not top_s and not cons_s:
            errors.append(
                f"{prefix}: resources[{i}] kind gateway requires non-empty sliceFlavor "
                "(top-level or constraints.sliceFlavor)"
            )


def validate_template_deploy_contract(repo_root: Path, template_dir: str) -> list[str]:
    errors: list[str] = []
    template_path = repo_root / template_dir
    env_path = template_path / "environments.yaml"

    try:
        import yaml
    except ImportError:
        return [f"{template_dir}: pyyaml is required for catalog validation"]

    validate_no_dot_tf_under_infra(template_path, template_dir, errors)
    validate_orphan_infra_presets(template_path, template_dir, errors, yaml)
    validate_resources_yaml(template_path, template_dir, errors)

    if not env_path.exists():
        return errors

    with open(env_path, encoding="utf-8") as f:
        env_doc = yaml.safe_load(f) or {}
    if env_doc.get("schemaVersion") != ENVIRONMENTS_SCHEMA_VERSION:
        errors.append(
            f"{template_dir}/environments.yaml: schemaVersion must be {ENVIRONMENTS_SCHEMA_VERSION}"
        )
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
        if "lifecycle" in env_raw:
            errors.append(
                f"{template_dir}/environments.yaml: environment '{env_id}' cannot use 'lifecycle' "
                "(removed in schema v3; use boot.script)"
            )
        if runtime == "cloud":
            deploy = env_raw.get("deploy")
            presets = deploy.get("presets") if isinstance(deploy, dict) else None
            has_presets = isinstance(presets, list) and len(presets) > 0
            if not has_presets:
                errors.append(
                    f"{template_dir}/environments.yaml: environment '{env_id}' runtime cloud requires deploy.presets"
                )
            else:
                assert isinstance(presets, list)
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
            if isinstance(deploy, dict):
                validate_optional_deploy_slices(
                    deploy,
                    f"{template_dir}/environments.yaml: environment '{env_id}'",
                    errors,
                )
                omit = deploy.get("omitShareableResourceIds")
                if omit is not None:
                    if not isinstance(omit, list):
                        errors.append(
                            f"{template_dir}/environments.yaml: environment '{env_id}' "
                            "deploy.omitShareableResourceIds must be an array when set"
                        )
                    else:
                        seen_omit: set[str] = set()
                        for j, item in enumerate(omit):
                            if not isinstance(item, str) or not item.strip():
                                errors.append(
                                    f"{template_dir}/environments.yaml: environment '{env_id}' "
                                    f"deploy.omitShareableResourceIds[{j}] must be a non-empty string"
                                )
                                continue
                            oid = item.strip()
                            if oid in seen_omit:
                                errors.append(
                                    f"{template_dir}/environments.yaml: environment '{env_id}' "
                                    f"deploy.omitShareableResourceIds has duplicate '{oid}'"
                                )
                            seen_omit.add(oid)
            validate_boot_script_for_cloud(
                template_dir, str(env_id), env_raw, has_presets, errors
            )
        elif isinstance(env_raw.get("deploy"), dict):
            deploy = env_raw["deploy"]
            assert isinstance(deploy, dict)
            validate_optional_deploy_slices(
                deploy,
                f"{template_dir}/environments.yaml: environment '{env_id}'",
                errors,
            )
        if "abstract" in env_raw or "extends" in env_raw:
            errors.append(
                f"{template_dir}/environments.yaml: environment '{env_id}' cannot use abstract/extends in schema v3"
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
    work_root = os.environ.get("GITHUB_WORKSPACE") or str(repo_root)
    repo_root = Path(work_root).resolve()
    os.chdir(repo_root)

    template_dirs = get_template_dirs(repo_root)
    changed_files = get_changed_files()

    if not validate_yaml_files(repo_root, changed_files):
        return 1

    contract_errors: list[str] = []
    for template_dir in sorted(template_dirs):
        contract_errors.extend(validate_template_deploy_contract(repo_root, template_dir))
    if contract_errors:
        for err_msg in contract_errors:
            print(f"ERROR: {err_msg}", file=sys.stderr)
        return 1

    print(
        f"Validated: all {len(template_dirs)} template packages "
        f"(environments schema v{ENVIRONMENTS_SCHEMA_VERSION}, provider-native infra guardrails)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
