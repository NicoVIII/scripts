## Pack a folder of per-chapter FLAC files and a cover image into a chaptered
## source .mka. Asks for language, title and output file name interactively.
##
## Usage: flac_to_mka.sh <flac_folder> <cover_image>
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	shared: "../shared/main.roc",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Stderr
import shared.Chapters
import shared.Cover
import shared.Ffmpeg
import shared.Mkvmerge
import shared.Prompt
import shared.WorkDir
import Flac

parse_args : List(OsStr) -> Try({ folder : Path, cover : Path }, [Usage])
parse_args = |args|
	match args {
		[folder, cover] => Ok({ folder: Path.from_os_str(folder), cover: Path.from_os_str(cover) })
		_ => Err(Usage)
	}

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

default_title : List({ album : Try(Str, _), .. }), Path -> Str
default_title = |infos, folder|
	match infos.first() {
		Ok({ album: Ok(album), .. }) => album
		_ => folder.filename().map_ok(Path.display) ?? ""
	}

## Validated before the slow merge so a typo doesn't waste it.
ask_language! : () => Try(Str, _)
ask_language! = || {
	known = Mkvmerge.known_languages!()?
	Prompt.ask_valid!(
		"Language (ISO 639 code, e.g. ger or de; empty to skip)",
		"",
		|answer|
			if Str.is_empty(answer) or known.contains(answer) {
				Ok(answer)
			} else {
				Err("Unknown language code '${answer}', see `mkvmerge --list-languages`.")
			},
	)
}

ask_output! : Str => Try(Path, _)
ask_output! = |default|
	Prompt.ask_valid!(
		"Output file",
		default,
		|answer| {
			output = Path.unix(answer)
			match output.exists!() {
				Ok(False) => Ok(output)
				Ok(True) => Err("'${answer}' already exists, choose another name.")
				Err(err) => Err("Can't check '${answer}': ${Str.inspect(err)}")
			}
		},
	)

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args)?
	cover = Cover.from_path!(parsed.cover)?
	# The concat demuxer resolves relative entries against the list file's
	# directory, which is the work dir.
	folder = parsed.folder.absolute!()?
	infos = Flac.files!(folder)?.map_try!(Flac.info!)?
	Flac.check_sample_rates(infos)?
	warn_missing_titles!(infos)?

	language = ask_language!()?
	title = Prompt.ask!("Title", default_title(infos, folder))?
	output = ask_output!("${Str.replace_each(title, "/", "-")}.mka")?

	WorkDir.in_cwd!(
		|work_dir| {
			chapters = work_dir.join("chapters.txt")
			chapters.write_utf8!(Chapters.to_ogm(infos.map(|info| { title: info.title ?? filename_stem(info.path), duration: info.duration })))?
			audio = work_dir.join("merged.flac")
			Ffmpeg.concat!(infos.map(|info| info.path), work_dir, audio)?
			Mkvmerge.mux!({ output, title, language, audio, chapters, cover })
		},
	)?
	Stdout.line!("Created ${output.display()}")
}

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => "Usage: flac_to_mka.sh <flac_folder> <cover_image>"
		NoFlacFiles(folder) => "No .flac files in '${folder.display()}'. Only FLAC input is supported for now."
		CoverNotFound(cover) => "Cover '${cover.display()}' is not a file."
		UnsupportedCover(cover) => "Cover '${cover.display()}' must be a .jpg, .jpeg or .png."
		MixedSampleRates(rates) => "The FLAC files have different sample rates (${Str.inspect(rates)}); they can't be concatenated."
		PathErr(NotFound, path) => "'${path.display()}' does not exist."
		NonUtf8Path(path) => "Path '${path.display()}' is not valid UTF-8."
		other => Str.inspect(other)
	}

main! : List(OsStr) => Try({}, _)
main! = |args|
	match run!(args) {
		Ok({}) => Ok({})
		Err(Interrupted) => Err(Interrupted)
		Err(err) => {
			Stderr.line!(describe_error(err))?
			Err(Exit(1))
		}
	}

expect filename_stem("/a/b/10 - it's.flac") == "10 - it's"
