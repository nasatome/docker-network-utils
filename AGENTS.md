# AGENTS.md

Instructions for AI agents and human contributors working on this repository.

## What this repository is

A public, generic collection of reusable Docker service definitions, grouped by
purpose: `inference/`, `reverse-proxy/`, `utility/`. Anyone should be able to
clone it, copy a module, fill in their own `.env`, and get a working service.

Everything here is published to the world under an individual's name. Treat it
as such.

## The core rule: keep it generic

**Nothing in this repository may describe one specific machine, one specific
workload, or one specific client.** A module is finished when a stranger with
different hardware can use it without deleting anything first.

This is not a style preference. Machine-specific content is a leak: absolute
paths expose a filesystem layout, benchmark comments expose a hardware
inventory, and workload comments expose who someone works for and what their
data looks like.

### Do not commit

| Category | Examples of what to avoid |
|---|---|
| Absolute host paths | `/mnt/MyDisk4TB/models`, `/home/alice/projects/...`, `C:\Users\...` |
| Hardware-tuned constants presented as defaults | offload-layer counts, thread counts, or batch sizes calibrated for one specific GPU or CPU |
| Benchmark results | throughput in tokens/s, measured VRAM figures, seconds-per-document timings, links to `bench-*.md` files that live outside the repo |
| Client or business context | customer names, industry-specific document types, internal pipeline stage names, project codenames |
| Personal inventories | a list of the 40 models that happen to be on one person's disk |
| Real secrets | keys, tokens, passwords, webhook URLs. Only `.example` templates are versioned |

### Do commit

- Service definitions parameterized by environment variables.
- Container-relative paths (`/models/...`), never host paths.
- `.example` templates for every file that holds real values.
- Comments that explain **why a flag exists and how to calibrate it**, without
  stating the value that happens to work on one machine. "Lower this until it
  stops fitting in your VRAM, then step back one" is generic and useful. "Set
  this to 33" is neither.

## The pattern: infrastructure here, inventory outside

When a module needs a large, personal, or fast-changing set of data — a model
catalog, a site list, a scan target list — the repository ships **the mechanism
and a small documented template**, and the real content lives outside the repo,
selected by an environment variable.

`inference/llama-swap` is the reference implementation:

- `config/llama-swap.yaml.example` — versioned template, a few models, teaching
  the available patterns.
- `LLAMA_SWAP_CONFIG` — points at the user's real catalog, anywhere on their
  filesystem. Defaults to the template so a fresh clone still runs.
- `.gitignore` — blocks the local catalog by name, so a personal inventory
  cannot be committed by accident.

Apply the same shape to any future module with the same problem.

## Before you commit

1. `git diff --staged` and read it. Every line.
2. Grep the staged diff for host paths: `/mnt/`, `/home/`, `/Users/`, `/opt/prj/`.
3. Grep for units that only mean something on one machine: `t/s`, `GB VRAM`,
   `s/doc`, GPU model names.
4. Ask whether any proper noun in the diff is a customer, a project, or a person.
5. Never `git add -A` or `git add .`. Add files by name.

## Language

Root-level documents (`README.md`, `CONTRIBUTING.md`, this file) are in English.
Individual modules document themselves in the language their author chose; keep
a module internally consistent rather than mixing.

## Git

- Conventional commits: `feat|fix|docs|refactor|chore: description`.
- One logical change per commit.
- Do not add AI tools as co-authors.
- Do not rewrite published history. Rewriting local, unpushed commits to remove
  machine-specific content before publishing is correct and encouraged.
