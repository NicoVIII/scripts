#!/bin/bash
# This script is used to convert a .mka file to a smaller .mka file with libopus codec inside
# The bitrate defaults to 32k which is ideal for podcasts / audiobooks
# Have a look at https://wiki.xiph.org/Opus_Recommended_Settings for recommended settings
# for different types of audio
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "Usage: ./mka_to_opus.sh <input_file> [bit_rate]"

input_file="$1"
bitrate="${2:-32k}"

filename=$(basename --suffix=".mka" "$input_file")
output_file="$filename-small.mka"

echo "Converting '$input_file' to '$output_file' with bitrate $bitrate..."
ffmpeg -v warning -stats -i "$input_file" -c:a libopus -b:a "$bitrate" "$output_file"
echo "Done."
