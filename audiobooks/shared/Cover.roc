import pf.Path

Cover :: {}.{
	has_ext : Path, Str -> Bool
	has_ext = |path, ext|
		match path.ext() {
			Ok(found) => Str.caseless_ascii_equals(found.display(), ext)
			Err(_) => False
		}

	## Validates the cover up front, before any slow work.
	from_path! : Path => Try({ path : Path, mime_type : Str, attachment_name : Str }, _)
	from_path! = |path| {
		if !path.is_file!()? {
			return Err(CoverNotFound(path))
		}
		# Matroska players look for an attachment literally named cover.<ext>.
		if has_ext(path, "jpg") or has_ext(path, "jpeg") {
			Ok({ path, mime_type: "image/jpeg", attachment_name: "cover.jpg" })
		} else if has_ext(path, "png") {
			Ok({ path, mime_type: "image/png", attachment_name: "cover.png" })
		} else {
			Err(UnsupportedCover(path))
		}
	}
}
