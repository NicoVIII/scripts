# scripts

This is a collection of useful scripts I use for various purposes. They are organized into different categories based on their functionality.

## Roc scripts

The Roc scripts need the new Roc compiler (nightly-2026-10-12 or later, from [roc-lang/nightlies](https://github.com/roc-lang/nightlies/releases)) as `roc` on the PATH. They target [basic-cli](https://github.com/roc-lang/basic-cli) 0.26.0.

Each script is a folder with a `main.roc` entry point and a `<script>.sh` wrapper next to it, which is what you run. Modules used by several scripts of a category live in that category's `shared/` package (e.g. `audiobooks/shared/`), which apps import with `shared: "../shared/main.roc"`.

The basic-cli URL is repeated in every app header and every `shared/main.roc`. `./roc-upgrade-basic-cli.sh <version>` replaces all of them, shows which compiler nightly the release needs, and checks and tests every app; fixing what the new version breaks stays manual. Check a script with `roc check <script>/main.roc` and `roc test <script>/main.roc`; the tests include the shared modules it imports.
