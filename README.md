# scripts

This is a collection of useful scripts I use for various purposes. They are organized into different categories based on their functionality.

## Roc scripts

The Roc scripts need the new Roc compiler (the nightly pinned in `.devcontainer/devcontainer.json`, from [roc-lang/nightlies](https://github.com/roc-lang/nightlies/releases)) as `roc` on the PATH. They target [basic-cli](https://github.com/roc-lang/basic-cli) 0.26.0.

Each script is a folder with a `main.roc` entry point and a `<script>.sh` wrapper next to it, which is what you run. Modules used by several scripts of a category live in that category's `shared/` package (e.g. `audiobooks/shared/`), which apps import by relative path (`shared: "../../shared/main.roc"` from `audiobooks/tools/<script>/`).

The basic-cli URL is repeated in every app header and every `shared/main.roc`. `./roc-upgrade-basic-cli.sh <version>` replaces all of them, shows which compiler nightly the release needs, and checks and tests every app with `just roc`; fixing what the new version breaks stays manual.

## Checks

`just check` runs everything CI runs: `roc check` and `roc test` on every Roc app (including the shared modules it imports) and shellcheck on all `.sh` files. The Python scripts are not checked.

CI runs it inside the devcontainer, so `.devcontainer/devcontainer.json` is the only place tool versions are pinned; bump them there, not in the workflow, and commit the refreshed `devcontainer-lock.json` with it. When adding a tool, take its feature from the first source that has one: official `ghcr.io/devcontainers/features`, the tool's own maintainers, [NicoVIII/devcontainer-features](https://github.com/NicoVIII/devcontainer-features), then `ghcr.io/devcontainers-extra/features`. The container holds only the check tools; the media scripts themselves run on the host.

Dependabot (`.github/dependabot.yml`) opens weekly PRs for the workflow's actions and the devcontainer feature references. It does not see the tool versions in the feature options, the base image tag, or the basic-cli platform URL; bump those by hand.
