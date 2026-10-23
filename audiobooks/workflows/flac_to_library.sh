#!/bin/bash
# Interactively name a folder of per-chapter FLAC files and pack it with a cover
# into a chaptered .mka.
# Usage: ./flac_to_library.sh <flac_folder> <cover_image>
exec roc "$(dirname "$(realpath "$0")")/flac_to_library/main.roc" -- "$@"
