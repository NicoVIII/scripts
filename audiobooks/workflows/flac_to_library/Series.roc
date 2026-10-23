import pf.Env
import pf.Path
import Naming

## Per-series naming settings, remembered so each series is set up only once.
## Stored as a TOML subset: a `["<series>"]` table per series with `file_name`
## (string) and `padding` (integer), plus `#` comment lines.
Series :: {}.{

	default_padding : U64
	default_padding = 3

	## `$XDG_CONFIG_HOME/audiobooks`, falling back to `~/.config/audiobooks`.
	config_dir! : () => Try(Path, _)
	config_dir! = || {
		base = match Env.var_str!("XDG_CONFIG_HOME") {
			Ok(dir) if !Str.is_empty(dir) => Path.unix(dir)
			_ => Path.unix(Env.var_str!("HOME")?).join(".config")
		}
		Ok(base.join("audiobooks"))
	}

	config_file! : () => Try(Path, _)
	config_file! = || Ok(config_dir!()?.join("series.toml"))

	quote_byte : U8
	quote_byte = 34

	backslash_byte : U8
	backslash_byte = 92

	## Only the `\"` and `\\` escapes; nothing else a series name needs.
	parse_string : Str -> Try(Str, Str)
	parse_string = |text| {
		bytes = Str.to_utf8(text)
		if bytes.len() < 2 or !Str.starts_with(text, "\"") or !Str.ends_with(text, "\"") {
			return Err("expected a \"quoted\" string, got ${text}")
		}
		var $out = []
		var $escaped = False
		for byte in bytes.sublist({ start: 1, len: bytes.len() - 2 }) {
			if $escaped {
				if byte != quote_byte and byte != backslash_byte {
					return Err("only the \\\" and \\\\ escapes are supported")
				}
				$out = $out.append(byte)
				$escaped = False
			} else if byte == backslash_byte {
				$escaped = True
			} else if byte == quote_byte {
				return Err("unescaped \" inside ${text}")
			} else {
				$out = $out.append(byte)
			}
		}
		if $escaped {
			Err("${text} ends inside an escape")
		} else {
			Str.from_utf8($out).map_err(|_| "invalid UTF-8 in ${text}")
		}
	}

	quote : Str -> Str
	quote = |text| "\"${Str.replace_each(Str.replace_each(text, "\\", "\\\\"), "\"", "\\\"")}\""

	parse_line : Str -> Try([Blank, Table(Str), Entry(Str, Str)], Str)
	parse_line = |line| {
		text = Str.trim(line)
		if Str.is_empty(text) or Str.starts_with(text, "#") {
			Ok(Blank)
		} else if Str.starts_with(text, "[") and Str.ends_with(text, "]") {
			parse_string(Str.trim(Str.drop_suffix(Str.drop_prefix(text, "["), "]"))).map_ok(|name| Table(name))
		} else {
			match Str.split_first(text, "=") {
				Ok(parts) => Ok(Entry(Str.trim(parts.before), Str.trim(parts.after)))
				Err(_) => Err("expected [\"<series>\"] or key = value")
			}
		}
	}

	set_key : { name : Str, file_name : Str, padding : U64 }, Str, Str -> Try({ name : Str, file_name : Str, padding : U64 }, Str)
	set_key = |series, key, value|
		match key {
			"file_name" => {
				file_name = parse_string(value)?
				Ok({ ..series, file_name: Naming.check_file_name(file_name)? })
			}
			"padding" => Ok({ ..series, padding: U64.from_str(value).map_err(|_| "padding must be a number, got ${value}")? })
			_ => Err("unknown key ${key}, expected file_name or padding")
		}

	parse : Str -> Try(List({ name : Str, file_name : Str, padding : U64 }), [BadSeriesConfig(U64, Str)])
	parse = |content| {
		var $series = []
		var $line_nr = 0
		for line in Str.split_on(content, "\n") {
			$line_nr = $line_nr + 1
			nr = $line_nr
			match parse_line(line) {
				Ok(Blank) => {}
				Ok(Table(name)) => {
					# A name that is already file-safe needs no file_name.
					$series = $series.append({ name, file_name: name, padding: default_padding })
				}
				Ok(Entry(key, value)) => {
					current = $series.last().map_err(|_| BadSeriesConfig(nr, "${key} is outside a [\"<series>\"] table"))?
					updated = set_key(current, key, value).map_err(|message| BadSeriesConfig(nr, message))?
					$series = $series.take_first($series.len() - 1).append(updated)
				}
				Err(message) => return Err(BadSeriesConfig(nr, message))
			}
		}
		Ok($series)
	}

	## A missing file means no series is set up yet.
	load! : () => Try(List({ name : Str, file_name : Str, padding : U64 }), _)
	load! = || {
		path = config_file!()?
		match path.read_utf8!() {
			Ok(content) =>
				match parse(content) {
					Ok(known) => Ok(known)
					Err(BadSeriesConfig(nr, message)) => Err(BadSeriesConfig(path, nr, message))
				}
			Err(PathErr(NotFound, _)) => Ok([])
			Err(err) => Err(err)
		}
	}

	## The table names keep the user's spelling; tags often differ in case.
	find : List({ name : Str, file_name : Str, padding : U64 }), Str -> Try({ name : Str, file_name : Str, padding : U64 }, [NotFound])
	find = |known, name| known.find_first(|series| Str.caseless_ascii_equals(series.name, name))

	render : { name : Str, file_name : Str, padding : U64 } -> Str
	render = |series| "\n[${quote(series.name)}]\nfile_name = ${quote(series.file_name)}\npadding = ${series.padding.to_str()}\n"

	## Appends, so comments and edits in the file survive.
	save! : { name : Str, file_name : Str, padding : U64 } => Try({}, _)
	save! = |series| {
		config_dir!()?.create_all!()?
		config_file!()?.append_bytes!(Str.to_utf8(render(series)))
	}
}

expect {
	series = { name: "Die \"drei\" ???\\", file_name: "Die drei Fragezeichen", padding: 2 }
	Series.parse(Series.render(series)) == Ok([series])
}

expect Series.parse("# comment\n[\"TKKG\"]\n") == Ok([{ name: "TKKG", file_name: "TKKG", padding: 3 }])
expect Series.parse("padding = 2") == Err(BadSeriesConfig(1, "padding is outside a [\"<series>\"] table"))
expect Series.parse("[\"X\"]\nfile_name = \"a?\"").is_err()
expect Series.find([{ name: "Die drei ???", file_name: "f", padding: 3 }], "Die Drei ???").is_ok()
