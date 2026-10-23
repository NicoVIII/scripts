## Pack a folder of per-chapter FLAC files and a cover image into a chaptered
## .mka. The title defaults to the ALBUM tag, else the folder name. What all
## chapter names repeat is dropped unless `--keep-chapter-names` is given.
##
## Usage: flac_to_mka.sh [--title <title>] [--language <code>] [--keep-chapter-names] <flac_folder> <cover_image> <output.mka>
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	shared: "../../shared/main.roc",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Stderr
import shared.Chapters
import shared.FlacToMka
import shared.Mkvmerge

usage : Str
usage = "Usage: flac_to_mka.sh [--title <title>] [--language <code>] [--keep-chapter-names] <flac_folder> <cover_image> <output.mka>"

parse_args : List(OsStr), { title : Try(Str, [Unset]), language : Str, keep_chapter_names : Bool } -> Try({ title : Try(Str, [Unset]), language : Str, keep_chapter_names : Bool, folder : Path, cover : Path, output : Path }, _)
parse_args = |args, options|
	match args {
		[flag, value, .. as rest] if flag == OsStr.from_str("--title") => parse_args(rest, { ..options, title: Ok(value.to_str_try()?) })
		[flag, value, .. as rest] if flag == OsStr.from_str("--language") => parse_args(rest, { ..options, language: value.to_str_try()? })
		[flag, .. as rest] if flag == OsStr.from_str("--keep-chapter-names") => parse_args(rest, { ..options, keep_chapter_names: True })
		[folder, cover, output] => Ok({ title: options.title, language: options.language, keep_chapter_names: options.keep_chapter_names, folder: Path.from_os_str(folder), cover: Path.from_os_str(cover), output: Path.from_os_str(output) })
		_ => Err(Usage)
	}

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args, { title: Err(Unset), language: "", keep_chapter_names: False })?
	_ = Mkvmerge.check_language(Mkvmerge.known_languages!()?, parsed.language).map_err(|message| BadLanguage(message))?
	if parsed.output.exists!()? {
		return Err(OutputExists(parsed.output))
	}
	prepared = FlacToMka.prepare!(parsed.folder, parsed.cover)?
	title = parsed.title ?? FlacToMka.default_title(prepared)
	names = FlacToMka.chapter_names(prepared)
	chapter_names = if (parsed.keep_chapter_names) names else Chapters.clean(names)
	FlacToMka.write!(prepared, { output: parsed.output, title, language: parsed.language, chapter_names })?
	Stdout.line!("Created ${parsed.output.display()}")
}

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => usage
		BadLanguage(message) => message
		OutputExists(output) => "'${output.display()}' already exists."
		PathErr(NotFound, path) => "'${path.display()}' does not exist."
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
