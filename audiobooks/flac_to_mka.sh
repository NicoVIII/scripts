#!/bin/bash
# Pack a folder of per-chapter FLAC files and a cover into a chaptered .mka.
# Usage: ./flac_to_mka.sh <flac_folder> <cover_image>
exec roc "$(dirname "$(realpath "$0")")/flac_to_mka/main.roc" -- "$@"
