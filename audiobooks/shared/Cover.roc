import pf.Path
import Extension

Cover :: {}.{
	## Validates the cover up front, before any slow work.
	from_path! : Path => Try({ path : Path, mime_type : Str, attachment_name : Str }, _)
	from_path! = |path| {
		if !path.is_file!()? {
			return Err(CoverNotFound(path))
		}
		# Matroska players look for an attachment literally named cover.<ext>.
		if Extension.matches(path, "jpg") or Extension.matches(path, "jpeg") {
			Ok({ path, mime_type: "image/jpeg", attachment_name: "cover.jpg" })
		} else if Extension.matches(path, "png") {
			Ok({ path, mime_type: "image/png", attachment_name: "cover.png" })
		} else {
			Err(UnsupportedCover(path))
		}
	}
}
