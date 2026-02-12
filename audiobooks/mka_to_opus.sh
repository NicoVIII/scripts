#!/bin/bash
set -e

# This script is used to convert a .mka file to a smaller .mka file with libopus codec inside
# I use 32k for podcasts / audiobooks and 48k for radio plays
# Have a look at https://wiki.xiph.org/Opus_Recommended_Settings for recommended settings
# for different types of audio

if [ "$#" -ne 2 ]; then
  echo "Usage: ./mka_to_opus.sh <input_file> <bit_rate>"
  exit 1
fi

input_file="$1"
bitrate="$2"

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
