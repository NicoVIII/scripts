import pf.Duration
import pf.Path
import pf.Stderr
import Chapters
import Cover
import Ffmpeg
import Flac
import Mkvmerge
import WorkDir

## Merges a folder of per-chapter FLAC files and a cover into a chaptered .mka.
FlacToMka :: {}.{

	warn_missing_titles! : List({ path : Str, title : Try(Str, _), .. }) => Try({}, _)
	warn_missing_titles! = |infos| {
		for info in infos.keep_if(|info| info.title.is_err()) {
			Stderr.line!("No TITLE tag in '${info.path}', using the file name as chapter name.")?
		}
		Ok({})
	}

	filename_stem : Str -> Str
	filename_stem = |path| {
		name = Str.split_last(path, "/").map_ok(|parts| parts.after) ?? path
		Str.split_last(name, ".").map_ok(|parts| parts.before) ?? name
	}

	## Reads and validates the input, so callers can fail before slow work or
	## prompts.
	prepare! : Path, Path => Try(_, _)
	prepare! = |folder, cover_path| {
		cover = Cover.from_path!(cover_path)?
		# The concat demuxer resolves relative entries against the list file's
		# directory, which is the work dir.
		absolute = folder.absolute!()?
		infos = Flac.files!(absolute)?.map_try!(Flac.info!)?
		Flac.check_sample_rates(infos)?
		warn_missing_titles!(infos)?
		Ok({ folder: absolute, infos, cover })
	}

	default_title : { folder : Path, infos : List({ album : Try(Str, _), .. }), .. } -> Str
	default_title = |prepared|
		match prepared.infos.first() {
			Ok({ album: Ok(album), .. }) => album
			_ => prepared.folder.filename().map_ok(Path.display) ?? ""
		}

	## An empty `title` or `language` leaves that field unset.
	write! : {
		infos : List({ path : Str, title : Try(Str, _), duration : Duration, .. }),
		cover : { path : Path, mime_type : Str, attachment_name : Str },
		..
	}, { output : Path, title : Str, language : Str } => Try({}, _)
	write! = |prepared, spec|
		WorkDir.in_cwd!(
			|work_dir| {
				chapters = work_dir.join("chapters.txt")
				chapters.write_utf8!(Chapters.to_ogm(prepared.infos.map(|info| { title: info.title ?? filename_stem(info.path), duration: info.duration })))?
				audio = work_dir.join("merged.flac")
				Ffmpeg.concat!(prepared.infos.map(|info| info.path), work_dir, audio)?
				Mkvmerge.mux!({ output: spec.output, title: spec.title, language: spec.language, audio, chapters, cover: prepared.cover })
			},
		)

	describe_error : _ -> Try(Str, [Unknown])
	describe_error = |err|
		match err {
			NoFlacFiles(folder) => Ok("No .flac files in '${folder.display()}'. Only FLAC input is supported for now.")
			CoverNotFound(cover) => Ok("Cover '${cover.display()}' is not a file.")
			UnsupportedCover(cover) => Ok("Cover '${cover.display()}' must be a .jpg, .jpeg or .png.")
			MixedSampleRates(rates) => Ok("The FLAC files have different sample rates (${Str.inspect(rates)}); they can't be concatenated.")
			NonUtf8Path(path) => Ok("Path '${path.display()}' is not valid UTF-8.")
			_ => Err(Unknown)
		}
}

expect FlacToMka.filename_stem("/a/b/10 - it's.flac") == "10 - it's"
