## Pack a folder of per-chapter FLAC files and a cover image into a chaptered
## source .mka. Asks for language, series naming, title and output file name
## interactively.
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
import Naming
import Series

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

parse_number : Str -> Try(U64, Str)
parse_number = |answer| U64.from_str(answer).map_err(|_| "'${answer}' is not a number.")

parse_yes_no : Str -> Try(Bool, Str)
parse_yes_no = |answer|
	if Str.caseless_ascii_equals(answer, "y") {
		Ok(True)
	} else if Str.caseless_ascii_equals(answer, "n") {
		Ok(False)
	} else {
		Err("Answer y or n.")
	}

non_empty : Str -> Try(Str, Str)
non_empty = |answer| if (Str.is_empty(answer)) Err("This can't be empty.") else Ok(answer)

## Settings of a series not set up yet are asked once and offered for saving.
ask_series_settings! : List({ name : Str, file_name : Str, padding : U64 }), Str => Try({ name : Str, file_name : Str, padding : U64 }, _)
ask_series_settings! = |known, series|
	match Series.find(known, series) {
		Ok(settings) => Ok(settings)
		Err(NotFound) => {
			file_name = match Naming.check_file_name(series) {
				Ok(_) => series
				Err(_) => Prompt.ask_parsed!("'${series}' can't be used in file names. File-safe series name", "", Naming.check_file_name)?
			}
			padding = Prompt.ask_parsed!("Pad the number in file names to how many digits", Series.default_padding.to_str(), parse_number)?
			settings = { name: series, file_name, padding }
			remember = Prompt.ask_parsed!("Remember this for '${series}' in ${Series.config_file!()?.display()}? (y/n)", "y", parse_yes_no)?
			if remember {
				Series.save!(settings)?
			}
			Ok(settings)
		}
	}

## Tags only seed the defaults, since they vary between releases.
ask_naming! : List({ album : Try(Str, _), album_artist : Try(Str, _), .. }), Path => Try({ title : Str, file_stem : Str }, _)
ask_naming! = |infos, folder| {
	known = Series.load!()?
	tagged_series = match infos.first() {
		Ok({ album_artist: Ok(artist), .. }) => Series.find(known, artist).map_ok(|settings| settings.name) ?? artist
		_ => ""
	}
	series = Prompt.ask!("Series (empty for a standalone book)", tagged_series)?
	if Str.is_empty(series) {
		title = Prompt.ask_parsed!("Title", default_title(infos, folder), non_empty)?
		return Ok({ title, file_stem: title })
	}
	settings = ask_series_settings!(known, series)?
	guess = match infos.first() {
		Ok({ album: Ok(album), .. }) => Naming.parse_album(album)
		_ => Err(NoMatch)
	}
	number = Prompt.ask_parsed!("Number", guess.map_ok(|parsed| parsed.number.to_str()) ?? "", parse_number)?
	episode = Naming.elide_series(Prompt.ask_parsed!("Episode title", guess.map_ok(|parsed| parsed.episode) ?? "", non_empty)?, settings.name)
	Ok({
		title: Naming.title({ series: settings.name, number, episode }),
		file_stem: Naming.file_stem({ file_series: settings.file_name, padding: settings.padding, number, episode }),
	})
}

## An invalid default would only be rejected again, so none is offered.
default_output : Str -> Str
default_output = |file_stem| {
	file = "${file_stem}.mka"
	if (Naming.check_file_name(file).is_ok()) file else ""
}

ask_output! : Str => Try(Path, _)
ask_output! = |default|
	Prompt.ask_valid!(
		"Output file",
		default,
		|answer| {
			_ = Naming.check_file_name(Str.split_last(answer, "/").map_ok(|parts| parts.after) ?? answer)?
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
	naming = ask_naming!(infos, folder)?
	title = naming.title
	output = ask_output!(default_output(naming.file_stem))?

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
		BadSeriesConfig(path, line, message) => "${path.display()}, line ${line.to_str()}: ${message}"
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
