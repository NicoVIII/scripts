#!/bin/bash
set -e

# This script is used to convert a .mka file to a smaller .mka file with libopus codec inside
# The bitrate defaults to 32k which is ideal for podcasts / audiobooks
# Have a look at https://wiki.xiph.org/Opus_Recommended_Settings for recommended settings
# for different types of audio
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || (echo "Usage: ./mka_to_opus.sh <input_file> [bit_rate]" && exit 1)

input_file="$1"
bitrate="${2:-48}"

filename=$(basename --suffix=".mka" "$input_file")
output_file="$filename.opus"

echo "Extract cover image..."
ffmpeg -v warning -i "$input_file" -map 0:v -c:v copy -y "$filename.cover.jpg" -v 0
echo "Converting '$input_file' to '$output_file' with bitrate $bitrate..."
ffmpeg -i "$input_file" -f wav - 2> /dev/null | \
 opusenc --bitrate "$bitrate" --picture "$filename.cover.jpg" - "$output_file"
echo "Removing temporary files..."
rm "$filename.cover.jpg"
echo "Done."
