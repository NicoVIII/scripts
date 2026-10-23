import pf.Path

## basic-cli's `Path.ext` is everything after the first dot, which makes the
## extension of "215 - ... und die verlorene Zeit.mka" ".. und die verlorene
## Zeit.mka".
Extension :: {}.{

	## Whether the file name's last extension is `ext`, ignoring case. A
	## hidden file like ".mka" has none, as with `Path.ext`.
	matches : Path, Str -> Bool
	matches = |path, ext|
		match path.filename() {
			Ok(name) =>
				match Str.split_last(name.display(), ".") {
					Ok(parts) => !Str.is_empty(parts.before) and Str.caseless_ascii_equals(parts.after, ext)
					Err(_) => False
				}
			Err(_) => False
		}
}

expect Extension.matches(Path.unix("/a/215 - ... und die verlorene Zeit.mka"), "mka")
expect Extension.matches(Path.unix("03 - Teil 1. Der Anfang.FLAC"), "flac")
expect !Extension.matches(Path.unix("/a/book.mka.part"), "mka")
expect !Extension.matches(Path.unix("/a/.mka"), "mka")
expect !Extension.matches(Path.unix("/a/mka"), "mka")
