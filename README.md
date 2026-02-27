### PartRocks App Template Catalog

## A library of App Templates Curated by PartRocks

---

## Overview

This catalog provides clients with fast search capability via the root `info.yaml` file. Each folder in this repo contains a different template with its own manifest and configuration.

---

## Template Directory Structure

Each template directory describes a local software project's build and deployment information. It consists of the following:

### manifest.yaml

Describes the template for discovery and search:

- **id** — unique identifier
- **name** — display name
- **description** — what the template provides
- **tags** — array of tags for categorization
- **keywords** — list of keywords for search

### options.yaml

Defines internal variables for app setup. These are the questions the **partrocks-desktop** app (a GUI tool for orchestrating build and deployments) will ask users during the setup process.

### steps.yaml

Procedures the desktop app (or any tool) will perform for new app bootstrapping. Steps consist of commands such as:


| Command  | Description                                                          |
| -------- | -------------------------------------------------------------------- |
| `run`    | Execute on the command line                                          |
| `copy`   | Copy a file from the template directory into the new project folder  |
| `modify` | Perform a find/replace on an existing file in the app project folder |
| `append` | Add content to an existing file                                      |
| `delete` | Delete a file from the project folder                                |


### pipeline.yaml

Ordered steps (from `steps.yaml`) that define the bootstrap flow. Each step in the pipeline has a `when` clause that provides conditional logic for whether to run the step (typically based on variables set in `options.yaml`).

### dependencies.yaml

Environmental tools the app will need in order to build and run.

### _resources/

Assets (files and folders of any sort) used during app setup or deployment.

### _deploy/

Deployment configuration for the template:


| File                  | Purpose                                                                                                                           |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **providers.yaml**    | Data on which cloud hosting providers are configured in this template for deployments                                             |
| **environments.yaml** | A set of environments that can run simultaneously on a provider                                                                   |
| **presets.yaml**      | Pre-configured groups of infrastructure data recommended for deployments (e.g., cloud resource differences for production vs UAT) |


