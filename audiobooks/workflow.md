# Workflow

I personally recommend to have two copies of your audiobooks. The original one for storage in the best quality you have available and one working copy with the opus codec for a small file size which you can easily use on your devices without juggling gigabytes of data for just one simple audiobook. Therefore we first create the source mka for storage and use it after that to create the working copy. You can repeat the creation of the working copy at a later point in time to get better ones as codecs and technology evolve.

## Create source mka

### flac input

If you have a folder with one flac file per chapter (named so that `sort -V` puts them in order), run:

```sh
./flac_to_mka.sh <input_folder> <cover_image>
```

It merges the flacs, takes chapter names from their `TITLE` tags (falling back to the file name), asks for language, title and output file name, and writes the mka with the cover (jpg or png) attached.

For a series episode it builds the names from series, number and episode title, which it suggests from the `ALBUMARTIST` and `ALBUM` tags:

- Title: `Die drei ??? 214 - ... und der Geisterbunker`. An episode title starting with the series name gets it replaced by `...`.
- File name: `Die drei Fragezeichen 214 - ... und der Geisterbunker.mka`, with a file-safe series name and the number zero-padded. Names with characters Windows/SMB reject (`\ / : * ? " < > |`) or a trailing dot or space are refused.

Leave the series empty for a standalone book; you're then asked for the title directly.

The first time a series comes up, it asks for its file-safe name (only if needed) and the padding (default 3), and offers to remember them in `~/.config/audiobooks/series.toml` (`$XDG_CONFIG_HOME` is honoured). Later runs skip those questions; the series name is matched ignoring case, so the spelling you saved wins over the tag's. The file is plain TOML you can edit:

```toml
["Die drei ???"]
file_name = "Die drei Fragezeichen"
padding = 3
```

Requires `roc` on the PATH (see the [README](../README.md#roc-scripts)), ffmpeg, metaflac and mkvmerge. Intermediate files go into a hidden folder in the current directory, so it needs free space for one more copy of the book.

### m4b input

If you already have a single chaptered m4b file you can simply use ffmpeg to convert it into an mka file and work from there:

1. Run `m4b_to_mka.sh <input_file>` to convert the m4b file into an mka file
2. Use MKVToolNix header editor to add the cover image again (optional)

## Create working copy mka

For now I recommend using opus, if your devices support it because it offers great quality in small file sizes.

1. Use `mka_to_opus.sh <input_file> [bitrate]` to create the opus mka from your source mka (You can provide the bitrate as second parameter: I recommend using 32k bitrate for audiobooks and 64k für radio plays)
2. Use MKVToolNix header editor to add the cover image again (optional)
