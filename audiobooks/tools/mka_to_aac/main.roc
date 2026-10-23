## Encode a .mka into an AAC HE v2 .m4a, keeping the cover. The output defaults
## to the input's name with .m4a, next to it.
##
## Usage: mka_to_aac.sh [--no-cover] <input.mka> <bitrate> [<output.m4a>]
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	shared: "../../shared/main.roc",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Stderr
import shared.Aac

usage : Str
usage = "Usage: mka_to_aac.sh [--no-cover] <input.mka> <bitrate> [<output.m4a>]"

default_output : Path -> Try(Path, _)
default_output = |input| {
	path = input.to_str().map_err(|_| NonUtf8Path(input))?
	match Str.split_last(path, ".") {
		Ok(parts) if !Str.contains(parts.after, "/") => Ok(Path.unix("${parts.before}.m4a"))
		_ => Ok(Path.unix("${path}.m4a"))
	}
}

parse_args : List(OsStr), Bool -> Try({ input : Path, bitrate : Str, output : Path, cover : Bool }, _)
parse_args = |args, cover|
	match args {
		[flag, .. as rest] if flag == OsStr.from_str("--no-cover") => parse_args(rest, False)
		[input, bitrate] => {
			input_path = Path.from_os_str(input)
			Ok({ input: input_path, bitrate: bitrate.to_str_try()?, output: default_output(input_path)?, cover })
		}
		[input, bitrate, output] => Ok({ input: Path.from_os_str(input), bitrate: bitrate.to_str_try()?, output: Path.from_os_str(output), cover })
		_ => Err(Usage)
	}

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args, True)?
	bitrate = Aac.check_bitrate(parsed.bitrate).map_err(|message| BadBitrate(message))?
	if !parsed.input.is_file!()? {
		return Err(InputNotFound(parsed.input))
	}
	Aac.encode!({ ..parsed, bitrate })?
	Stdout.line!("Created ${parsed.output.display()}")
}

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => usage
		BadBitrate(message) => message
		InputNotFound(input) => "'${input.display()}' is not a file."
		NonUtf8Path(path) => "Path '${path.display()}' is not valid UTF-8."
		PathErr(NotFound, path) => "'${path.display()}' does not exist."
		other => Aac.describe_error(other) ?? Str.inspect(other)
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

expect default_output(Path.unix("a/b.c/book.mka")) == Ok(Path.unix("a/b.c/book.m4a"))
expect default_output(Path.unix("a.b/book")) == Ok(Path.unix("a.b/book.m4a"))
