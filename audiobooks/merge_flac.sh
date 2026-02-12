#!/bin/bash
# This script is used to merge multiple FLAC files into a single FLAC file and create a chapter file
# This can be used as a preparation for a packing into a .mka with MKVToolNix
# Beware: The flacs should be named in a way that they are sorted in the correct order when using ls
# Usage: ./merge_flac.sh <directory>

# Require one argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <directory>"
  exit 1
fi

# Remove trailing slash from first argument if present and store it in path variable
path=$(echo "$1" | sed 's:/*$::')

# Prepare lists of files
> "./chapters.txt"
> "$path/ffmpeg_input.txt"
current_time=0
current_chapter=1

# Use version sort to get files in human-friendly order
while IFS= read -r FILE; do
  # Prepare input file for ffmpeg
  printf "file '%s'\n" "$(basename "$FILE" | sed "s/'/'\\\\''/g")" >> "$path/ffmpeg_input.txt"

  # Read title and length in milliseconds from the file via ffmpeg
  metadata=$(ffmpeg -i "$FILE" 2>&1)
  title=$(echo "$metadata" | grep -oP 'TITLE\s*:\s*\K.*')
  length=$(echo "$metadata" | grep -oP 'Duration:\s*\K[0-9:.]*' | awk -F: '{ print (($1 * 3600) + ($2 * 60) + $3) * 1000 }')

  # Convert milliseconds to hours, minutes, seconds, and milliseconds
  milliseconds=$(($current_time % 1000))
  seconds=$(($current_time / 1000 % 60))
  minutes=$(($current_time / (1000 * 60) % 60))
  hours=$(($current_time / (1000 * 60 * 60)))

  # Write chapters
  printf -v formatted_time "%02d:%02d:%02d.%03d" $hours $minutes $seconds $milliseconds
  echo "CHAPTER$current_chapter=$formatted_time" >> "./chapters.txt"
  echo "CHAPTER${current_chapter}NAME=$title" >> "./chapters.txt"

  current_time=$(($current_time + $length))
  current_chapter=$(($current_chapter + 1))
done < <(find "$path" -maxdepth 1 -name '*.flac' | sort -V)

ffmpeg -f concat -safe 0 -i "$path/ffmpeg_input.txt" -vn ./merged.flac

# Clean up
rm "$path/ffmpeg_input.txt" 
