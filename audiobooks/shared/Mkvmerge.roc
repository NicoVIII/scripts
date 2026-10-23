import pf.Cmd
import pf.OsStr
import pf.Path

Mkvmerge :: {}.{

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

	optional_args : Str, List(Str) -> List(OsStr)
	optional_args = |value, args| if (Str.is_empty(value)) [] else args.map(OsStr.from_str)

	## Muxes one audio file with chapters and a cover. An empty `title` or
	## `language` leaves that field unset. mkvmerge exits with 1 for warnings,
	## which still produce a valid file.
	mux! : {
		output : Path,
		title : Str,
		language : Str,
		audio : Path,
		chapters : Path,
		cover : { path : Path, mime_type : Str, attachment_name : Str },
	} => Try({}, _)
	mux! = |spec| {
		result = Cmd.new("mkvmerge")
			.arg("--output")
			.arg(spec.output.to_os_str())
			.args(optional_args(spec.title, ["--title", spec.title]))
			.args(optional_args(spec.language, ["--chapter-language", spec.language]))
			.arg("--chapters")
			.arg(spec.chapters.to_os_str())
			.args(optional_args(spec.language, ["--language", "0:${spec.language}"]))
			.arg(spec.audio.to_os_str())
			.args(["--attachment-name", spec.cover.attachment_name, "--attachment-mime-type", spec.cover.mime_type].map(OsStr.from_str))
			.arg("--attach-file")
			.arg(spec.cover.path.to_os_str())
			.inherit_stdio()
			.run!()?
		match result.status {
			Exited(0) | Exited(1) => Ok({})
			_ => Err(BadExitStatus(result))
		}
	}
}
