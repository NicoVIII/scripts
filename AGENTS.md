# Agent notes

## Tools and workflows (audiobooks)

- `tools/` scripts take all input as arguments and never prompt. `workflows/` prompt and compose tools.
- A Roc tool's logic lives in a `shared/` module; its `main.roc` only parses arguments. Roc workflows import that module instead of spawning the tool's script, so errors stay typed. A new shared module must be added to `package [...]` in `shared/main.roc`.
- Each module with its own error tags has a `describe_error : _ -> Try(Str, [Unknown])`; an app's `describe_error` falls back to them before `Str.inspect`.
- A change to what `Aac.encode!` produces (image, ffmpeg arguments) bumps `Aac.version`, or the library's existing working copies stay on the old encoding.
- `just check` only type-checks and runs `expect`s. Verify media changes by running the script on real input (the user's rips are in `~/Downloads`), in a scratch directory with `XDG_CONFIG_HOME` pointed at a scratch config, and inspect the result with `ffprobe`/`mkvmerge -J`.

## Roc

The scripts use a new-compiler nightly whose syntax and builtins differ from older Roc docs. Look things up instead of guessing:

- Builtin signatures are embedded in the binary: `strings -n 3 "$(command -v roc)" | grep -E '^\t\t<name> :'`.
- basic-cli sources are in `~/.cache/roc/packages/<hash>/`, where `<hash>` is the file name in the platform URL.

Pitfalls hit so far:

- A pure function (`->`) is rejected where an effectful one (`=>`) is expected; that's why `Prompt.ask_parsed!` exists next to `Prompt.ask_valid!`.
- An assignment inside a `match` branch needs a `{ }` block.
- Tags aren't functions: `map_ok(|x| Table(x))`, not `map_ok(Table)`.
- An expression statement must be `{}`; discard other values with `_ =`.
- `{ ..record, field }` can't add fields that `record` doesn't have.
- `U64` subtraction below zero crashes at runtime; compare before subtracting.
- `Path.ext` is everything after the *first* dot, so `a ... b.mka` has no `mka` extension; check extensions with `shared.Extension.matches`.
