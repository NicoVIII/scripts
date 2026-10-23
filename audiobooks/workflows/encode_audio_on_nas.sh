#!/bin/bash
# Create the missing m4a working copies on the NAS from the source mkas.
# Usage: ./encode_audio_on_nas.sh
exec roc "$(dirname "$(realpath "$0")")/encode_audio_on_nas/main.roc" -- "$@"
