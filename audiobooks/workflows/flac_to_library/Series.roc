import pf.Path
import shared.Aac
import shared.Config
import Naming

## Per-series naming settings, remembered so each series is set up only once.
## Stored in `Config`'s TOML subset: a `["<series>"]` table per series with
## `file_name` (string), `padding` (integer) and `bitrate` (string).
Series :: {}.{

	default_padding : U64
	default_padding = 3

	config_file! : () => Try(Path, _)
	config_file! = || Ok(Config.dir!()?.join("series.toml"))

	set_key : { name : Str, file_name : Str, padding : U64, bitrate : Try(Str, [Missing]), line : U64 }, Str, Str -> Try({ name : Str, file_name : Str, padding : U64, bitrate : Try(Str, [Missing]), line : U64 }, Str)
	set_key = |series, key, value|
		match key {
			"file_name" => {
				file_name = Config.parse_string(value)?
				Ok({ ..series, file_name: Naming.check_file_name(file_name)? })
			}
			"padding" => Ok({ ..series, padding: U64.from_str(value).map_err(|_| "padding must be a number, got ${value}")? })
			"bitrate" => {
				bitrate = Config.parse_string(value)?
				Ok({ ..series, bitrate: Ok(Aac.check_bitrate(bitrate)?) })
			}
			_ => Err("unknown key ${key}, expected file_name, padding or bitrate")
		}

	## Unlike the others, the bitrate has no sensible default.
	require_bitrate : { name : Str, file_name : Str, padding : U64, bitrate : Try(Str, [Missing]), line : U64 } -> Try({ name : Str, file_name : Str, padding : U64, bitrate : Str }, [BadSeriesConfig(U64, Str)])
	require_bitrate = |series|
		match series.bitrate {
			Ok(bitrate) => Ok({ name: series.name, file_name: series.file_name, padding: series.padding, bitrate })
			Err(Missing) => Err(BadSeriesConfig(series.line, "${Config.quote(series.name)} has no bitrate"))
		}

	parse : Str -> Try(List({ name : Str, file_name : Str, padding : U64, bitrate : Str }), [BadSeriesConfig(U64, Str)])
	parse = |content| {
		var $series = []
		var $line_nr = 0
		for line in Str.split_on(content, "\n") {
			$line_nr = $line_nr + 1
			nr = $line_nr
			match Config.parse_line(line) {
				Ok(Blank) => {}
				Ok(Table(name)) => {
					# A name that is already file-safe needs no file_name.
					$series = $series.append({ name, file_name: name, padding: default_padding, bitrate: Err(Missing), line: nr })
				}
				Ok(Entry(key, value)) => {
					current = $series.last().map_err(|_| BadSeriesConfig(nr, "${key} is outside a [\"<series>\"] table"))?
					updated = set_key(current, key, value).map_err(|message| BadSeriesConfig(nr, message))?
					$series = $series.take_first($series.len() - 1).append(updated)
				}
				Err(message) => return Err(BadSeriesConfig(nr, message))
			}
		}
		$series.map_try(require_bitrate)
	}

	## A missing file means no series is set up yet.
	load! : () => Try(List({ name : Str, file_name : Str, padding : U64, bitrate : Str }), _)
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
	find : List({ name : Str, file_name : Str, padding : U64, bitrate : Str }), Str -> Try({ name : Str, file_name : Str, padding : U64, bitrate : Str }, [NotFound])
	find = |known, name| known.find_first(|series| Str.caseless_ascii_equals(series.name, name))

	render : { name : Str, file_name : Str, padding : U64, bitrate : Str } -> Str
	render = |series| "\n[${Config.quote(series.name)}]\nfile_name = ${Config.quote(series.file_name)}\npadding = ${series.padding.to_str()}\nbitrate = ${Config.quote(series.bitrate)}\n"

	## Appends, so comments and edits in the file survive.
	save! : { name : Str, file_name : Str, padding : U64, bitrate : Str } => Try({}, _)
	save! = |series| {
		Config.dir!()?.create_all!()?
		config_file!()?.append_bytes!(Str.to_utf8(render(series)))
	}
}

expect {
	series = { name: "Die \"drei\" ???\\", file_name: "Die drei Fragezeichen", padding: 2, bitrate: "64k" }
	Series.parse(Series.render(series)) == Ok([series])
}

expect Series.parse("# comment\n[\"TKKG\"]\nbitrate = \"64k\"\n") == Ok([{ name: "TKKG", file_name: "TKKG", padding: 3, bitrate: "64k" }])
expect Series.parse("\n[\"TKKG\"]\n") == Err(BadSeriesConfig(2, "\"TKKG\" has no bitrate"))
expect Series.parse("padding = 2") == Err(BadSeriesConfig(1, "padding is outside a [\"<series>\"] table"))
expect Series.parse("[\"X\"]\nfile_name = \"a?\"").is_err()
expect Series.find([{ name: "Die drei ???", file_name: "f", padding: 3, bitrate: "64k" }], "Die Drei ???").is_ok()
