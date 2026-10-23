# Audiobooks

I keep two copies of every audiobook: a source copy in the best quality I have, for storage, and a small working copy for my devices. The working copy is always made from the source, so it can be redone later as codecs and encoders improve.

The scripts come in two kinds:

- `tools/`: do one thing, take everything as arguments and never ask questions, so they can be run by hand or from a workflow.
- `workflows/`: chain tools together and ask for whatever they need, such as names.

`shared/` holds the Roc modules both kinds are built from; it contains nothing to run.

The Roc scripts need `roc` on the PATH (see the [README](../README.md#roc-scripts)).

## Workflows

### flac_to_library

For a folder with one flac file per chapter (named so that `sort -V` puts them in order):

```sh
workflows/flac_to_library.sh <input_folder> <cover_image>
```

It asks for language, title and output file name, then packs the book with [`flac_to_mka`](#flac_to_mka).

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

### encode_audio_on_nas

`workflows/encode_audio_on_nas.py` creates the missing m4a working copies on the NAS from the source mka files in `source/` folders, using [`mka_to_aac`](#mka_to_aac). Its settings are at the top of the file.

## Tools

### flac_to_mka

```sh
tools/flac_to_mka.sh [--title <title>] [--language <code>] <flac_folder> <cover_image> <output.mka>
```

Merges the flacs into a chaptered mka with the cover (jpg or png) attached. Chapter names come from the `TITLE` tags, falling back to the file name; the title defaults to the `ALBUM` tag, else the folder name.

Requires ffmpeg, metaflac and mkvmerge. Intermediate files go into a hidden folder in the current directory, so it needs free space for one more copy of the book.

### m4b_to_mka

`tools/m4b_to_mka.sh <input_file>` converts a chaptered m4b into an mka without re-encoding. Add the cover again with the MKVToolNix header editor if you want it.

### mka_to_aac

`tools/mka_to_aac.py <input.mka> <bitrate>` encodes AAC HE v2 into an m4a next to the input, keeping the cover. It runs ffmpeg in Docker (`jrottenberg/ffmpeg`), since distribution builds lack libfdk_aac.

### mka_to_opus

`tools/mka_to_opus.sh <input_file> <bitrate>` encodes opus, which gives great quality at small sizes if your devices support it. I use 32k for audiobooks and 64k for radio plays. Add the cover again with the MKVToolNix header editor if you want it.
