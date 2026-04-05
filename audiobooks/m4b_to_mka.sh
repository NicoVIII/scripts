#!/bin/bash
set -e

# This script is used to convert a .m4b file to a .mka file without reencoding
[ "$#" -eq 1 ] || (echo "Usage: ./m4b_to_mka.sh <input_file>" && exit 1)

input_file="$1"

echo "Converting '$input_file' to .mka..."
ffmpeg -v warning -stats -i "$input_file" -c:a copy "${input_file%.*}.mka"
echo "Done."
