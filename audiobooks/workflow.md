# Workflow

## flac input

This describes the workflow I typically use to create a flac-mka and a opus-mka from
a list of flac files for each chapter of a audiobook.

1. Run `merge_flac.sh` to merge the flac files into a single flac file and create chapters
2. Use MKVToolNix to create the flac-mka
    * Add the flac file
    * Change the language on the audiostream (optional)
    * Set the file title (optional)
    * Add chapter file
    * Set chapter language (optional)
    * Add the cover image (optional)
    * Set the file name
3. Use `mka_to_opus.sh` to create the opus-mka
4. Use MKVToolNix header editor to add the cover image again (optional)

## m4b input

If you already have a single chaptered m4b file you can simply use ffmpeg to convert it into an mka file and work from there:

1. Run `ffmpeg -i <input_file> -c copy <output_file>.mka`
2. Use MKVToolNix header editor to add the cover image again (optional)
3. Use `mka_to_opus.sh` to create the opus-mka
4. Use MKVToolNix header editor to add the cover image again (optional)
