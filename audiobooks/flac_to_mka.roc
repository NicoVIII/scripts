## Pack a folder of per-chapter FLAC files and a cover image into a chaptered
## source .mka. Asks for language, title and output file name interactively.
##
## Usage: roc flac_to_mka.roc -- <flac_folder> <cover_image>
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Cmd
import pf.Env
import pf.Stdin
import pf.Stdout
import pf.Stderr

parse_args : List(OsStr) -> Try({ folder : Path, cover : Path }, [Usage])
parse_args = |args|
	match args {
		[folder, cover] => Ok({ folder: Path.from_os_str(folder), cover: Path.from_os_str(cover) })
		_ => Err(Usage)
	}

## The ffmpeg concat demuxer and metaflac need text paths, so non-UTF-8 paths
## are rejected up front instead of being mangled.
path_str : Path -> Try(Str, [NonUtf8Path(Path)])
path_str = |path|
	match path.to_str() {
		Ok(str) => Ok(str)
		Err(InvalidStr(_)) => Err(NonUtf8Path(path))
	}

has_ext : Path, Str -> Bool
has_ext = |path, ext|
	match path.ext() {
		Ok(found) => Str.caseless_ascii_equals(found.display(), ext)
		Err(_) => False
	}

cover_mime_type : Path -> Try(Str, [UnsupportedCover(Path)])
cover_mime_type = |cover|
	if has_ext(cover, "jpg") or has_ext(cover, "jpeg") {
		Ok("image/jpeg")
	} else if has_ext(cover, "png") {
		Ok("image/png")
	} else {
		Err(UnsupportedCover(cover))
	}

## Matroska players look for an attachment literally named cover.<ext>.
cover_attachment_name : Path -> Str
cover_attachment_name = |cover|
	if (has_ext(cover, "png")) "cover.png" else "cover.jpg"

## `sort -V` keeps the chapter order identical to merge_flac.sh, so
## "2.flac" sorts before "10.flac".
version_sort! : List(Str) => Try(List(Str), _)
version_sort! = |names| {
	input = Str.to_utf8(Str.join_with(names.map(|name| "${name}\u(0)"), ""))
	output = Cmd.new("sort").args(["-V", "-z"]).stdin(Bytes(input)).run!()?.require_success()?
	sorted = output.stdout_utf8()?
	Ok(sorted.split_on("\u(0)").drop_if(Str.is_empty))
}

flac_files! : Path => Try(List(Str), _)
flac_files! = |folder| {
	entries = folder.list!()?
	flacs = entries.keep_if(|entry| has_ext(entry, "flac")).map_try(path_str)?
	if flacs.is_empty() {
		Err(NoFlacFiles(folder))
	} else {
		version_sort!(flacs)
	}
}

FlacInfo : { path : Str, samples : U64, sample_rate : U64, title : Try(Str, [NoTitle]), album : Try(Str, [NoAlbum]) }

tag_value : List(Str), Str -> Try(Str, [NotFound])
tag_value = |lines, tag|
	lines
		.keep_oks(|line| Str.drop_prefix_caseless_ascii(line, "${tag}="))
		.first()
		.map_err(|_| NotFound)

## Sample counts instead of ffmpeg's rounded durations keep chapter marks
## from drifting over long books.
read_flac_info! : Str => Try(FlacInfo, _)
read_flac_info! = |path| {
	output = Cmd.new("metaflac")
		.args(["--show-total-samples", "--show-sample-rate", "--show-tag=TITLE", "--show-tag=ALBUM"])
		.arg(OsStr.from_str(path))
		.capture!()?
	lines = output.trim_end().split_on("\n")
	match lines {
		[samples, rate, .. as tags] =>
			Ok({
				path,
				samples: U64.from_str(samples)?,
				sample_rate: U64.from_str(rate)?,
				title: tag_value(tags, "TITLE").map_err(|_| NoTitle),
				album: tag_value(tags, "ALBUM").map_err(|_| NoAlbum),
			})
		_ => Err(UnexpectedMetaflacOutput(path, output))
	}
}

## The concat demuxer assumes all files share one stream layout, and the
## chapter marks need a single sample rate.
check_sample_rates : List(FlacInfo) -> Try(U64, [MixedSampleRates(List(U64))])
check_sample_rates = |infos| {
	rates = infos.map(|info| info.sample_rate)
	match rates {
		[first, ..] if rates.all(|rate| rate == first) => Ok(first)
		_ => Err(MixedSampleRates(rates))
	}
}

pad_left : U64, U64 -> Str
pad_left = |n, width| {
	digits = n.to_str()
	missing = width - Str.to_utf8(digits).len()
	"${Str.repeat("0", missing)}${digits}"
}

format_timestamp : U64 -> Str
format_timestamp = |ms|
	"${pad_left(ms // 3_600_000, 2)}:${pad_left((ms // 60_000) % 60, 2)}:${pad_left((ms // 1000) % 60, 2)}.${pad_left(ms % 1000, 3)}"

filename_stem : Str -> Str
filename_stem = |path| {
	name = Str.split_last(path, "/").map_ok(|parts| parts.after) ?? path
	Str.split_last(name, ".").map_ok(|parts| parts.before) ?? name
}

chapter_title : FlacInfo -> Str
chapter_title = |info| info.title ?? filename_stem(info.path)

## OGM chapter format, as merge_flac.sh wrote it; mkvmerge reads it directly.
ogm_chapters : List(FlacInfo), U64 -> Str
ogm_chapters = |infos, sample_rate| {
	var $start_samples = 0
	var $lines = []
	for info in infos {
		number = ($lines.len() // 2 + 1).to_str()
		$lines = $lines.append("CHAPTER${number}=${format_timestamp($start_samples * 1000 // sample_rate)}")
		$lines = $lines.append("CHAPTER${number}NAME=${chapter_title(info)}")
		$start_samples = $start_samples + info.samples
	}
	"${Str.join_with($lines, "\n")}\n"
}

concat_list : List(FlacInfo) -> Str
concat_list = |infos|
	Str.join_with(infos.map(|info| "file '${Str.replace_each(info.path, "'", "'\\''")}'\n"), "")

ask! : Str, Str => Try(Str, _)
ask! = |question, default| {
	hint = if (Str.is_empty(default)) "" else " [${default}]"
	Stdout.write!("${question}${hint}: ")?
	answer = Stdin.line!()?.trim()
	Ok(if (Str.is_empty(answer)) default else answer)
}

## Codes from `mkvmerge --list-languages`: name | ISO 639-3 | ISO 639-2 | ISO 639-1.
known_languages! : () => Try(List(Str), _)
known_languages! = || {
	table = Cmd.new("mkvmerge").arg("--list-languages").capture!()?
	codes = table
		.split_on("\n")
		.drop_first(2)
		.join_map(|row| row.split_on("|").drop_first(1).map(Str.trim))
		.drop_if(Str.is_empty)
	Ok(codes)
}

## Validated before the slow merge so a typo doesn't waste it.
ask_language! : List(Str) => Try(Str, _)
ask_language! = |known| {
	answer = ask!("Language (ISO 639 code, e.g. ger or de; empty to skip)", "")?
	if Str.is_empty(answer) or known.contains(answer) {
		Ok(answer)
	} else {
		Stderr.line!("Unknown language code '${answer}', see `mkvmerge --list-languages`.")?
		ask_language!(known)
	}
}

ask_output! : Str => Try(Path, _)
ask_output! = |default| {
	answer = ask!("Output file", default)?
	output = Path.unix(answer)
	if output.exists!()? {
		Stderr.line!("'${answer}' already exists, choose another name.")?
		ask_output!(default)
	} else {
		Ok(output)
	}
}

merge_flacs! : List(FlacInfo), Path => Try(Path, _)
merge_flacs! = |infos, work_dir| {
	list_file = work_dir.join("concat.txt")
	merged = work_dir.join("merged.flac")
	list_file.write_utf8!(concat_list(infos))?
	Cmd.new("ffmpeg")
		.args(["-v", "warning", "-stats", "-f", "concat", "-safe", "0"])
		.arg("-i")
		.arg(list_file.to_os_str())
		.arg("-vn")
		.arg(merged.to_os_str())
		.inherit_stdio()
		.call!()?
	Ok(merged)
}

Metadata : { language : Str, title : Str, output : Path, cover : Path, cover_mime : Str }

optional_args : Str, List(Str) -> List(OsStr)
optional_args = |value, args| if (Str.is_empty(value)) [] else args.map(OsStr.from_str)

## mkvmerge exits with 1 for warnings, which still produce a valid file.
mux! : Path, Path, Metadata => Try({}, _)
mux! = |merged, chapters, meta| {
	result = Cmd.new("mkvmerge")
		.arg("--output")
		.arg(meta.output.to_os_str())
		.args(optional_args(meta.title, ["--title", meta.title]))
		.args(optional_args(meta.language, ["--chapter-language", meta.language]))
		.arg("--chapters")
		.arg(chapters.to_os_str())
		.args(optional_args(meta.language, ["--language", "0:${meta.language}"]))
		.arg(merged.to_os_str())
		.args(["--attachment-name", cover_attachment_name(meta.cover), "--attachment-mime-type", meta.cover_mime].map(OsStr.from_str))
		.arg("--attach-file")
		.arg(meta.cover.to_os_str())
		.inherit_stdio()
		.run!()?
	match result.status {
		Exited(0) | Exited(1) => Ok({})
		_ => Err(BadExitStatus(result))
	}
}

default_title : List(FlacInfo), Path -> Str
default_title = |infos, folder|
	match infos.first() {
		Ok({ album: Ok(album), .. }) => album
		_ => folder.filename().map_ok(Path.display) ?? ""
	}

ask_metadata! : List(FlacInfo), Path, Path, Str => Try(Metadata, _)
ask_metadata! = |infos, folder, cover, cover_mime| {
	language = ask_language!(known_languages!()?)?
	title = ask!("Title", default_title(infos, folder))?
	output = ask_output!("${Str.replace_each(title, "/", "-")}.mka")?
	Ok({ language, title, output, cover, cover_mime })
}

warn_missing_titles! : List(FlacInfo) => Try({}, _)
warn_missing_titles! = |infos| {
	for info in infos.keep_if(|info| info.title.is_err()) {
		Stderr.line!("No TITLE tag in '${info.path}', using the file name as chapter name.")?
	}
	Ok({})
}

## In the current directory instead of /tmp, which is often a RAM-backed
## tmpfs too small for a merged book.
in_work_dir! : (Path => Try(a, err)) => Try(a, _)
in_work_dir! = |callback!| {
	work_dir = Env.create_temp_dir_in!(Env.cwd!()?, ".flac_to_mka-")?
	result = callback!(work_dir)
	work_dir.delete_all!()?
	result
}

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args)?
	cover = parsed.cover
	# The concat demuxer resolves relative entries against the list file's
	# directory, which is the work dir.
	folder = parsed.folder.absolute!()?
	if !cover.is_file!()? {
		return Err(CoverNotFound(cover))
	}
	cover_mime = cover_mime_type(cover)?
	infos = flac_files!(folder)?.map_try!(read_flac_info!)?
	sample_rate = check_sample_rates(infos)?
	warn_missing_titles!(infos)?
	meta = ask_metadata!(infos, folder, cover, cover_mime)?
	in_work_dir!(
		|work_dir| {
			chapters = work_dir.join("chapters.txt")
			chapters.write_utf8!(ogm_chapters(infos, sample_rate))?
			merged = merge_flacs!(infos, work_dir)?
			mux!(merged, chapters, meta)
		},
	)?
	Stdout.line!("Created ${meta.output.display()}")
}

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => "Usage: roc flac_to_mka.roc -- <flac_folder> <cover_image>"
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
