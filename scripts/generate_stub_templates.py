#!/usr/bin/env python3
"""Generate minimal docker-only stub templates (manifest, YAML scaffold, compose)."""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STEPS = """steps:
  - step: stub-placeholder
    label: Placeholder (stub template)
    run:
      - command: "true"
"""

PIPELINE = """pipeline:
  - steps:
      - stub-placeholder
"""

DEPS = "dependencies: []\n"

ENV = """schemaVersion: 3
environments:
  dev:
    id: dev
    runtime: docker
    docker:
      composeFile: _resources/_docker/docker-compose.yml
      service: app
      url:
        scheme: http
        domain: localhost
        port: "{{localPort}}"
    vars:
      localPort:
        required: true
        default: "8080"
"""

COMPOSE = """services:
  app:
    image: nginx:alpine
    ports:
      - "{{localPort}}:80"
"""

OPT_BASE = """options:
  - id: projectName
    label: Project name
    type: string
    required: true
    default: my-app
  - id: localPort
    label: Local HTTP port
    type: auto-port-local
    range: app
    required: true
"""

OPT_PHP_MODE = (
    OPT_BASE
    + """
  - id: appMode
    label: Application mode
    type: select
    required: true
    default: web
    options:
      - label: Web (server-rendered)
        value: web
      - label: API only
        value: api
      - label: Hybrid
        value: hybrid
"""
)

OPT_NODE_API = (
    OPT_BASE
    + """
  - id: nodeFramework
    label: Node framework
    type: select
    required: true
    default: express
    options:
      - label: Express
        value: express
      - label: Fastify
        value: fastify
      - label: NestJS
        value: nest
"""
)


def manifest_block(
    tid: str,
    name: str,
    description: str,
    categories: list[str],
    capabilities: str,
    logos: list[str],
    tags: list[str],
    version: str = "0.1.0-stub",
) -> str:
    cat_yaml = "\n".join(f"  - {c}" for c in categories)
    logos_yaml = "\n".join(f"  - {l}" for l in logos)
    tags_yaml = "\n".join(f"  - {t}" for t in tags)
    cap_indented = "\n".join(
        "    " + line if line.strip() else ""
        for line in capabilities.strip().split("\n")
    )
    return f"""manifest:
  id: {tid}
  name: {name}
  description: {description}
  version: {version}
  tags:
{tags_yaml}
  categories:
{cat_yaml}
  capabilities: |
{cap_indented}
  logos:
{logos_yaml}
"""


STUBS: list[dict] = [
    # Static Web App
    dict(
        id="static-react-vite",
        name="React (Vite)",
        desc="Static or SPA build with React and Vite; deploy as static assets.",
        cats=["static-web-app"],
        caps="Client-side React, Vite bundler, static export/CDN-friendly output.",
        logos=["react", "vite"],
        tags=["static", "react", "vite", "javascript"],
        opt="base",
    ),
    dict(
        id="static-react-cra",
        name="React (CRA-style)",
        desc="React single-page app with a classic CRA-style static build output.",
        cats=["static-web-app"],
        caps="React SPA, static build directory suitable for CDN or object storage hosting.",
        logos=["react"],
        tags=["static", "react", "javascript"],
        opt="base",
    ),
    dict(
        id="static-vue",
        name="Vue",
        desc="Vue static site or SPA built for static hosting.",
        cats=["static-web-app"],
        caps="Vue 3 composition or options API, static site generation or SPA build.",
        logos=["vue"],
        tags=["static", "vue", "javascript"],
        opt="base",
    ),
    dict(
        id="static-svelte",
        name="Svelte (static)",
        desc="Svelte compiled to static assets for edge/CDN delivery.",
        cats=["static-web-app"],
        caps="Svelte components, small bundle, static adapter output.",
        logos=["svelte"],
        tags=["static", "svelte", "javascript"],
        opt="base",
    ),
    dict(
        id="static-astro",
        name="Astro (static)",
        desc="Astro content-focused static site with optional islands.",
        cats=["static-web-app"],
        caps="Static generation, partial hydration, MD/MDX content.",
        logos=["astro"],
        tags=["static", "astro", "javascript"],
        opt="base",
    ),
    # Full Stack JS
    dict(
        id="fullstack-nextjs",
        name="Next.js",
        desc="Full stack React with SSR, API routes, and app router patterns.",
        cats=["fullstack-js-web-app"],
        caps="Server components, API routes, SSR/SSG, Node runtime.",
        logos=["nextjs", "react"],
        tags=["nextjs", "react", "fullstack"],
        opt="base",
    ),
    dict(
        id="fullstack-sveltekit",
        name="SvelteKit",
        desc="Full stack Svelte with SSR, endpoints, and adapters.",
        cats=["fullstack-js-web-app"],
        caps="File-based routing, server endpoints, adapter-based deploy.",
        logos=["svelte"],
        tags=["sveltekit", "svelte", "fullstack"],
        opt="base",
    ),
    dict(
        id="fullstack-nuxt",
        name="Nuxt",
        desc="Full stack Vue with SSR, Nitro server, and modules.",
        cats=["fullstack-js-web-app"],
        caps="Vue SSR, server API, file-based routing, Nitro engine.",
        logos=["nuxt", "vue"],
        tags=["nuxt", "vue", "fullstack"],
        opt="base",
    ),
    # PHP
    dict(
        id="php-symfony",
        name="Symfony",
        desc="Symfony web, API, or hybrid PHP application with Doctrine and console.",
        cats=["php-web-app"],
        caps="HTTP kernel, DI, Messenger, API Platform optional; choose web, API, or hybrid mode when scaffolding.",
        logos=["symfony", "php"],
        tags=["php", "symfony"],
        opt="php",
    ),
    dict(
        id="php-laravel",
        name="Laravel",
        desc="Laravel MVC, API resources, queues, and Eloquent ORM.",
        cats=["php-web-app"],
        caps="Blade or API-first, Sanctum/Passport, Horizon queues; mode selector for API/web/hybrid.",
        logos=["laravel", "php"],
        tags=["php", "laravel"],
        opt="php",
    ),
    # Python
    dict(
        id="python-django",
        name="Django",
        desc="Django for admin-heavy and server-rendered web apps.",
        cats=["python-web-app"],
        caps="ORM, admin, migrations, templates; suited for data-driven sites and internal tools.",
        logos=["django", "python"],
        tags=["python", "django"],
        opt="base",
    ),
    dict(
        id="python-fastapi",
        name="FastAPI",
        desc="FastAPI for high-performance APIs (also listed under API Service).",
        cats=["python-web-app", "api-service"],
        caps="Async Python, OpenAPI docs, Pydantic models; ideal for API-first and microservices.",
        logos=["fastapi", "python"],
        tags=["python", "fastapi", "api"],
        opt="base",
    ),
    dict(
        id="python-flask",
        name="Flask",
        desc="Lightweight Python web framework for small services and prototypes.",
        cats=["python-web-app"],
        caps="Minimal core, blueprints, Jinja; flexible stack choice.",
        logos=["flask", "python"],
        tags=["python", "flask"],
        opt="base",
    ),
    # API Service (shape-focused)
    dict(
        id="api-node",
        name="Node API (Express / Fastify / Nest)",
        desc="Node.js REST/GraphQL-style API with interchangeable framework preference.",
        cats=["api-service"],
        caps="HTTP APIs, middleware, validation; pick Express, Fastify, or Nest when generating.",
        logos=["nodejs"],
        tags=["node", "api", "javascript"],
        opt="node_api",
    ),
    dict(
        id="api-symfony",
        name="Symfony API",
        desc="API-focused Symfony (JSON, serialization, API Platform path).",
        cats=["api-service"],
        caps="JSON APIs, Symfony Serializer, API Platform optional; pairs with PHP Symfony stack.",
        logos=["symfony", "php"],
        tags=["php", "symfony", "api"],
        opt="php",
    ),
    dict(
        id="api-laravel",
        name="Laravel API",
        desc="Laravel as API backend (resources, Sanctum, queues).",
        cats=["api-service"],
        caps="REST resources, form requests, policies; API-first Laravel deployment.",
        logos=["laravel", "php"],
        tags=["php", "laravel", "api"],
        opt="php",
    ),
    # Container
    dict(
        id="container-go",
        name="Go",
        desc="Go service packaged as a Docker image.",
        cats=["container-app"],
        caps="Static binary, small images, high concurrency; bring your own framework.",
        logos=["go"],
        tags=["go", "docker", "container"],
        opt="base",
    ),
    dict(
        id="container-java-spring",
        name="Java (Spring)",
        desc="Spring Boot (or similar) in a container image.",
        cats=["container-app"],
        caps="JVM ecosystem, Spring ecosystem, production-ready defaults.",
        logos=["spring", "java"],
        tags=["java", "spring", "docker"],
        opt="base",
    ),
    dict(
        id="container-dotnet",
        name=".NET",
        desc=".NET application in a Linux container image.",
        cats=["container-app"],
        caps="ASP.NET Core, minimal APIs, worker services.",
        logos=["dotnet"],
        tags=["dotnet", "docker", "container"],
        opt="base",
    ),
    dict(
        id="container-rust",
        name="Rust",
        desc="Rust binary or web service in a slim container.",
        cats=["container-app"],
        caps="Memory safety, performance, multi-stage Dockerfile patterns.",
        logos=["rust"],
        tags=["rust", "docker", "container"],
        opt="base",
    ),
    dict(
        id="container-rails",
        name="Rails",
        desc="Ruby on Rails app containerized for web or API.",
        cats=["container-app"],
        caps="Convention over configuration, ActiveRecord, Sidekiq-friendly.",
        logos=["rails", "ruby"],
        tags=["rails", "ruby", "docker"],
        opt="base",
    ),
    dict(
        id="container-custom",
        name="Custom Docker app",
        desc="Bring any Dockerfile; framework-agnostic container deploy.",
        cats=["container-app"],
        caps="Full control of base image, build, and runtime; language-agnostic.",
        logos=["docker"],
        tags=["docker", "container"],
        opt="base",
    ),
    # Workers
    dict(
        id="worker-node",
        name="Node worker",
        desc="Background jobs and queue consumers in Node.js.",
        cats=["worker-job-service"],
        caps="BullMQ, SQS, scheduled tasks, event-driven workers.",
        logos=["nodejs"],
        tags=["node", "worker", "queue"],
        opt="base",
    ),
    dict(
        id="worker-python",
        name="Python worker",
        desc="Celery, RQ, or async Python job processors.",
        cats=["worker-job-service"],
        caps="Queue workers, cron-style schedules, batch pipelines.",
        logos=["python"],
        tags=["python", "worker", "queue"],
        opt="base",
    ),
    dict(
        id="worker-php",
        name="PHP worker",
        desc="Symfony Messenger or Laravel queue workers in PHP.",
        cats=["worker-job-service"],
        caps="Message consumers, retry policies, supervisor-friendly.",
        logos=["php"],
        tags=["php", "worker", "queue"],
        opt="base",
    ),
    dict(
        id="worker-container",
        name="Generic container worker",
        desc="Any containerized worker image (language-agnostic).",
        cats=["worker-job-service"],
        caps="Custom entrypoint, scale-to-zero patterns, job runners.",
        logos=["docker"],
        tags=["docker", "worker", "container"],
        opt="base",
    ),
]


def opt_yaml(kind: str) -> str:
    if kind == "php":
        return OPT_PHP_MODE
    if kind == "node_api":
        return OPT_NODE_API
    return OPT_BASE


def write_stub(s: dict) -> None:
    tid = s["id"]
    d = ROOT / tid
    if d.exists():
        print(f"skip existing {tid}")
        return
    d.mkdir(parents=True)
    (d / "_resources" / "_docker").mkdir(parents=True)
    (d / "manifest.yaml").write_text(
        manifest_block(
            tid,
            s["name"],
            s["desc"],
            s["cats"],
            s["caps"],
            s["logos"],
            s["tags"],
        ),
        encoding="utf-8",
    )
    (d / "options.yaml").write_text(opt_yaml(s["opt"]), encoding="utf-8")
    (d / "steps.yaml").write_text(STEPS, encoding="utf-8")
    (d / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
    (d / "dependencies.yaml").write_text(DEPS, encoding="utf-8")
    (d / "environments.yaml").write_text(ENV, encoding="utf-8")
    (d / "_resources" / "_docker" / "docker-compose.yml").write_text(
        COMPOSE, encoding="utf-8"
    )
    print(f"wrote {tid}")


def _capability_lines(text: str) -> list[str]:
    """Lines for `capabilities: |` block (indented under template entry)."""
    inner = text.rstrip("\n")
    lines = inner.split("\n") if inner else [""]
    out = ["    capabilities: |"]
    for ln in lines:
        out.append("      " + ln)
    return out


def write_info_yaml() -> None:
    """Emit repo-root info.yaml (source of truth for catalog listing; includes logos)."""
    lines: list[str] = ["templates:"]
    # Legacy — display name only; ids unchanged
    lines.append("  - id: static-html-site")
    lines.append('    name: "__(legacy)__ Static HTML Site"')
    lines.append(
        "    description: Simple static HTML/CSS/JS website with low-cost AWS S3 hosting."
    )
    lines.append("    version: 3.0.0")
    lines.append("    tags:")
    for t in [
        "static",
        "html",
        "css",
        "javascript",
        "aws",
        "s3",
        "web",
        "legacy",
    ]:
        lines.append(f"      - {t}")
    lines.append("  - id: partrocks-symfony")
    lines.append('    name: "__(legacy)__ PartRocks Symfony"')
    lines.append(
        "    description: PartRocks Symfony is an opinionated template for building Symfony applications."
    )
    lines.append("    version: 3.0.5")
    lines.append("    tags:")
    for t in ["symfony", "php", "framework", "web", "api", "partrocks", "legacy"]:
        lines.append(f"      - {t}")

    for s in STUBS:
        lines.append(f"  - id: {s['id']}")
        lines.append(f"    name: {s['name']!r}")
        lines.append(f"    description: {s['desc']!r}")
        lines.append("    version: 0.1.0-stub")
        lines.append("    tags:")
        for t in s["tags"]:
            lines.append(f"      - {t}")
        lines.append("    categories:")
        for c in s["cats"]:
            lines.append(f"      - {c}")
        lines.extend(_capability_lines(s["caps"]))
        lines.append("    logos:")
        for logo in s["logos"]:
            lines.append(f"      - {logo}")

    out_path = ROOT / "info.yaml"
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")


def main() -> None:
    import sys

    os.chdir(ROOT)
    if len(sys.argv) > 1 and sys.argv[1] in ("info", "--info", "write-info"):
        write_info_yaml()
        return
    for s in STUBS:
        write_stub(s)


if __name__ == "__main__":
    main()
