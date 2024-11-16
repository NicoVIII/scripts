# Workflow

I personally recommend to have to copies of your audiobooks. The original one for storage in the best quality you have available and one working copy with the opus codec for a small file size which you can easily use on your devices without juggling gigabytes of data for just one simple audiobook. Therefore we first create the source mka for storage and use it after that to create the working copy. You can repeat the creation of the working copy at a later point in time to get better ones as codecs and technology evolve.

## Create source mka

### flac input

If you have a list of flac files for each chapter of an audiobook, do this:

1. Run `merge_flac.sh <input_folder>` to merge the flac files into a single flac file and create chapters
2. Use MKVToolNix to create the flac-mka
    * Add the flac file
    * Change the language on the audiostream (optional)
    * Set the file title (optional)
    * Add chapter file
    * Set chapter language (optional)
    * Add the cover image (optional)
    * Set the file name

## m4b input

If you already have a single chaptered m4b file you can simply use ffmpeg to convert it into an mka file and work from there:

1. Run `m4b_to_mka.sh <input_file>` to convert the m4b file into an mka file
2. Use MKVToolNix header editor to add the cover image again (optional)

## Create working copy mka

For now I recommend using opus, if your devices support it because it offers great quality in small file sizes.

1. Use `mka_to_opus.sh <input_file> [bitrate]` to create the opus mka from your source mka (You can provide the bitrate as second parameter: I recommend using 32k bitrate for audiobooks and 64k für radio plays)
2. Use MKVToolNix header editor to add the cover image again (optional)
