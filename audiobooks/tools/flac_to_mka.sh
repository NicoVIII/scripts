#!/bin/bash
# Pack a folder of per-chapter FLAC files and a cover into a chaptered .mka.
# Usage: ./flac_to_mka.sh [--title <title>] [--language <code>] [--keep-chapter-names] <flac_folder> <cover_image> <output.mka>
exec roc "$(dirname "$(realpath "$0")")/flac_to_mka/main.roc" -- "$@"
