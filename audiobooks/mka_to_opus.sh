#!/bin/bash
# This script is used to convert a .mka file to a smaller .mka file with libopus codec inside
# For now the bitrate is fixed at 32k which is ideal for podcasts / audiobooks
# Have a look at https://wiki.xiph.org/Opus_Recommended_Settings for recommended settings
# for different types of audio
# Usage: ./mka_to_opus.sh <input_file>

# One argument required
[ "$#" -eq 1 ] || die "1 argument required, $# provided"

input_file="$1"
filename=$(basename --suffix=".mka" "$input_file")
output_file="$filename-small.mka"

ffmpeg -i "$input_file" -c:a libopus -b:a 32k "$output_file"
