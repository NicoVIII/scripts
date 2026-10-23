## Turn a folder of per-chapter FLAC files and a cover image into a library
## entry: "<library>/<series>/<number> - <episode>/" holding the AAC working
## copy, with the chaptered source .mka in its "source/" folder. Asks for
## language, naming, bitrate and library folder interactively.
##
## Usage: flac_to_library.sh <flac_folder> <cover_image>
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	shared: "../../shared/main.roc",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Stderr
import shared.Aac
import shared.Chapters
import shared.FlacToMka
import shared.Mkvmerge
import shared.Prompt
import Naming
import Series

parse_args : List(OsStr) -> Try({ folder : Path, cover : Path }, [Usage])
parse_args = |args|
	match args {
		[folder, cover] => Ok({ folder: Path.from_os_str(folder), cover: Path.from_os_str(cover) })
		_ => Err(Usage)
	}

## Validated before the slow merge so a typo doesn't waste it.
ask_language! : () => Try(Str, _)
ask_language! = || {
	known = Mkvmerge.known_languages!()?
	Prompt.ask_valid!(
		"Language (ISO 639 code, e.g. ger or de; empty to skip)",
		"",
		|answer| Mkvmerge.check_language(known, answer),
	)
}

parse_number : Str -> Try(U64, Str)
parse_number = |answer| U64.from_str(answer).map_err(|_| "'${answer}' is not a number.")

## Shows the shortened chapter names, if the cleanup changes any, and lets
## them be declined.
ask_chapter_names! : List(Str) => Try(List(Str), _)
ask_chapter_names! = |names| {
	cleaned = Chapters.clean(names)
	if cleaned == names {
		return Ok(names)
	}
	Stdout.line!("Chapter names without what they all repeat:")?
	Stdout.line!(Str.join_with(cleaned.map_with_index(|name, index| "  ${(index + 1).to_str()}) ${name}"), "\n"))?
	use_cleaned = Prompt.ask_parsed!("Use these instead of e.g. '${names.first() ?? ""}'? (y/n)", "y", Prompt.parse_yes_no)?
	Ok(if (use_cleaned) cleaned else names)
}

## The same split as encode_audio_on_nas uses for audiobooks and audio dramas.
presets : List({ label : Str, detail : Str, value : Str })
presets = [
	{ label: "audiobook", detail: "48k", value: "48k" },
	{ label: "audio drama", detail: "64k", value: "64k" },
]

ask_bitrate! : () => Try(Str, _)
ask_bitrate! = || Prompt.choose!("Working copy bitrate", presets, "enter a bitrate like 56k", Aac.check_bitrate)

## Only asks when `value` can't be used as is.
ask_file_safe! : Str, Str => Try(Str, _)
ask_file_safe! = |what, value|
	match Naming.check_file_name(value) {
		Ok(_) => Ok(value)
		Err(_) => Prompt.ask_parsed!("'${value}' can't be used in file names. File-safe ${what}", "", Naming.check_file_name)
	}

## Settings of a series not set up yet are asked once and offered for saving.
ask_series_settings! : List({ name : Str, file_name : Str, padding : U64, bitrate : Str }), Str => Try({ name : Str, file_name : Str, padding : U64, bitrate : Str }, _)
ask_series_settings! = |known, series|
	match Series.find(known, series) {
		Ok(settings) => Ok(settings)
		Err(NotFound) => {
			file_name = ask_file_safe!("series name", series)?
			padding = Prompt.ask_parsed!("Pad the number in file names to how many digits", Series.default_padding.to_str(), parse_number)?
			bitrate = ask_bitrate!()?
			settings = { name: series, file_name, padding, bitrate }
			remember = Prompt.ask_parsed!("Remember this for '${series}' in ${Series.config_file!()?.display()}? (y/n)", "y", Prompt.parse_yes_no)?
			if remember {
				Series.save!(settings)?
			}
			Ok(settings)
		}
	}

## Tags only seed the defaults, since they vary between releases. `folder` is
## the entry's path below the library folder.
ask_naming! : { folder : Path, infos : List({ album : Try(Str, _), album_artist : Try(Str, _), .. }), .. } => Try({ title : Str, file_stem : Str, folder : List(Str), bitrate : Str }, _)
ask_naming! = |prepared| {
	infos = prepared.infos
	known = Series.load!()?
	tagged_series = match infos.first() {
		Ok({ album_artist: Ok(artist), .. }) => Series.find(known, artist).map_ok(|settings| settings.name) ?? artist
		_ => ""
	}
	series = Prompt.ask!("Series (empty for a standalone book)", tagged_series)?
	if Str.is_empty(series) {
		title = Prompt.ask_parsed!("Title", FlacToMka.default_title(prepared), Prompt.non_empty)?
		file_title = ask_file_safe!("title", title)?
		return Ok({ title, file_stem: file_title, folder: [file_title], bitrate: ask_bitrate!()? })
	}
	settings = ask_series_settings!(known, series)?
	guess = match infos.first() {
		Ok({ album: Ok(album), .. }) => Naming.parse_album(album)
		_ => Err(NoMatch)
	}
	number = Prompt.ask_parsed!("Number", guess.map_ok(|parsed| parsed.number.to_str()) ?? "", parse_number)?
	episode = Naming.elide_series(Prompt.ask_parsed!("Episode title", guess.map_ok(|parsed| parsed.episode) ?? "", Prompt.non_empty)?, settings.name)
	file_episode = ask_file_safe!("episode title", episode)?
	Ok({
		title: Naming.title({ series: settings.name, number, episode }),
		file_stem: Naming.file_stem({ file_series: settings.file_name, padding: settings.padding, number, episode: file_episode }),
		folder: [settings.file_name, Naming.episode_folder({ padding: settings.padding, number, episode: file_episode })],
		bitrate: settings.bitrate,
	})
}

join_all : Path, List(Str) -> Path
join_all = |base, parts| parts.fold(base, |path, part| path.join(part))

## The library folder must exist, so a typo doesn't create a stray tree.
ask_entry! : List(Str) => Try(Path, _)
ask_entry! = |folder|
	Prompt.ask_valid!(
		"Library folder",
		".",
		|answer| {
			entry = join_all(Path.unix(answer), folder)
			match (Path.unix(answer).is_dir!(), entry.exists!()) {
				(Ok(True), Ok(False)) => Ok(entry)
				(Ok(True), Ok(True)) => Err("'${entry.display()}' already exists.")
				(Ok(False), _) => Err("'${answer}' is not a folder.")
				(Err(err), _) | (_, Err(err)) => Err("Can't check '${answer}': ${Str.inspect(err)}")
			}
		},
	)

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args)?
	prepared = FlacToMka.prepare!(parsed.folder, parsed.cover)?
	chapter_names = ask_chapter_names!(FlacToMka.chapter_names(prepared))?
	language = ask_language!()?
	naming = ask_naming!(prepared)?
	entry = ask_entry!(naming.folder)?

	source = entry.join("source")
	source.create_all!()?
	# The NAS library skips folders marked like this, so it lists only the
	# working copy.
	source.join(".ignore").write_bytes!([])?
	mka = source.join("${naming.file_stem}.mka")
	# A half-made entry would block the next attempt.
	match FlacToMka.write!(prepared, { output: mka, title: naming.title, language, chapter_names }) {
		Ok({}) => {}
		Err(err) => {
			entry.delete_all!()?
			return Err(err)
		}
	}
	# A failed encode keeps the entry: the source is the slow part to make.
	m4a = entry.join("${naming.file_stem}.m4a")
	Aac.encode!({ input: mka, output: m4a, bitrate: naming.bitrate, cover: True }).map_err(|err| EncodeFailed(mka, m4a, naming.bitrate, err))?
	Stdout.line!("Created ${entry.display()}")
}

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => "Usage: flac_to_library.sh <flac_folder> <cover_image>"
		PathErr(NotFound, path) => "'${path.display()}' does not exist."
		BadSeriesConfig(path, line, message) => "${path.display()}, line ${line.to_str()}: ${message}"
		EncodeFailed(mka, m4a, bitrate, cause) => {
			reason = Aac.describe_error(cause) ?? Str.inspect(cause)
			"Encoding failed: ${reason}\nThe source is kept; retry with: tools/mka_to_aac.sh '${mka.display()}' ${bitrate} '${m4a.display()}'"
		}
		other => FlacToMka.describe_error(other) ?? Str.inspect(other)
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
