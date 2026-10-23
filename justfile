# Everything CI runs.
check: roc shellcheck

# Type-check and test every Roc app, including the shared packages it imports.
roc:
    #!/usr/bin/env bash
    set -uo pipefail
    # Keep going after a failure so one run reports every broken app.
    failed=0
    while read -r app; do
        echo "== $app"
        { roc check "$app" && roc test "$app"; } || failed=1
    done < <(grep -rlE --include=main.roc '^app \[' .)
    exit "$failed"

shellcheck:
    find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +
