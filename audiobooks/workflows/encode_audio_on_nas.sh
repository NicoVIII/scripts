#!/bin/bash
# Create the missing or outdated m4a working copies on the NAS from the source mkas.
# Usage: ./encode_audio_on_nas.sh [--dry-run]
exec roc "$(dirname "$(realpath "$0")")/encode_audio_on_nas/main.roc" -- "$@"
