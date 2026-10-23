#!/bin/bash
# Encode a .mka into an AAC HE v2 .m4a (ffmpeg in Docker), keeping the cover.
# Usage: ./mka_to_aac.sh [--no-cover] <input.mka> <bitrate> [<output.m4a>]
exec roc "$(dirname "$(realpath "$0")")/mka_to_aac/main.roc" -- "$@"
