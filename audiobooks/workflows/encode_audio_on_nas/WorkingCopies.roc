import pf.Path
import shared.Aac
import shared.Cover
import shared.WorkDir

## Library entries keep their source mka in a "source/" folder and the m4a
## working copy next to that folder.
WorkingCopies :: {}.{

	file_name : Path -> Str
	file_name = |path| path.filename().map_ok(|name| name.display()) ?? ""

	stem : Str -> Str
	stem = |name|
		match Str.split_last(name, ".") {
			Ok(parts) => parts.before
			Err(_) => name
		}

	## Walks `dir`, whose parent is `entry`. Symlinks aren't followed.
	scan_dir! : Path, Path, List({ mka : Path, entry : Path }) => Try(List({ mka : Path, entry : Path }), _)
	scan_dir! = |dir, entry, found| {
		in_source = file_name(dir) == "source"
		var $found = found
		for path in dir.list!()? {
			match path.type!()? {
				IsDir => {
					$found = scan_dir!(path, dir, $found)?
				}
				IsFile if in_source and Cover.has_ext(path, "mka") => {
					$found = $found.append({ mka: path, entry })
				}
				_ => {}
			}
		}
		Ok($found)
	}

	## The source mkas below `root`.
	scan! : Path => Try(List({ mka : Path, entry : Path }), _)
	scan! = |root| scan_dir!(root, root, [])

	m4a_name : { mka : Path, entry : Path } -> Str
	m4a_name = |source| "${stem(file_name(source.mka))}.m4a"

	## Only the m4a next to the source folder counts, since that's where
	## `encode!` puts it.
	has_working_copy! : { mka : Path, entry : Path } => Try(Bool, _)
	has_working_copy! = |source| source.entry.join(m4a_name(source)).exists!()

	## Encodes a local copy rather than reading the share for the whole
	## encode. The m4a replaces working copies of the same name in older
	## formats.
	encode! : { mka : Path, entry : Path }, Str => Try({}, _)
	encode! = |source, bitrate|
		WorkDir.in_cwd!(
			|work_dir| {
				name = m4a_name(source)
				local_mka = work_dir.join(file_name(source.mka))
				local_m4a = work_dir.join(name)
				source.mka.copy!(local_mka)?
				Aac.encode!({ input: local_mka, output: local_m4a, bitrate, cover: True })?
				m4a = source.entry.join(name)
				# A partial copy would count as done on the next run.
				match local_m4a.copy!(m4a) {
					Ok({}) => {}
					Err(err) => {
						Aac.remove_if_exists!(m4a)?
						return Err(err)
					}
				}
				for ext in ["opus", "mka"] {
					Aac.remove_if_exists!(source.entry.join("${stem(name)}.${ext}"))?
				}
				Ok({})
			},
		)

	describe_error : _ -> Try(Str, [Unknown])
	describe_error = |err|
		match err {
			CopyErr(copy) => Ok("Copying '${copy.source.display()}' to '${copy.destination.display()}' failed: ${Str.inspect(copy.error)}")
			_ => Err(Unknown)
		}
}

expect WorkingCopies.stem("Die drei ??? 1 - a.b.mka") == "Die drei ??? 1 - a.b"
expect WorkingCopies.m4a_name({ mka: Path.unix("/x/source/book.mka"), entry: Path.unix("/x") }) == "book.m4a"
