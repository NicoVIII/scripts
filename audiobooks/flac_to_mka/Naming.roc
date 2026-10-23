import shared.Chapters

## The scheme for series episodes: title "<series> <number> - <episode>", file
## name the same but with a file-safe series name and a zero-padded number.
Naming :: {}.{

	## Characters Windows and SMB shares reject in file names.
	forbidden_chars : List(Str)
	forbidden_chars = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]

	## The `Err` explains the problem so a prompt can ask again.
	check_file_name : Str -> Try(Str, Str)
	check_file_name = |name| {
		found = forbidden_chars.keep_if(|char| Str.contains(name, char))
		if Str.is_empty(name) {
			Err("The file name is empty.")
		} else if !found.is_empty() {
			Err("'${name}' contains ${Str.join_with(found, " ")}, which Windows/SMB reject in file names.")
		} else if Str.to_utf8(name).any(|byte| byte < 32) {
			Err("'${name}' contains control characters.")
		} else if Str.ends_with(name, ".") or Str.ends_with(name, " ") {
			Err("'${name}' ends with a dot or space, which Windows drops.")
		} else {
			Ok(name)
		}
	}

	## Episode titles often start with the series name ("Die drei ??? und der
	## Geisterbunker"), which the full title would repeat.
	elide_series : Str, Str -> Str
	elide_series = |episode, series|
		match Str.drop_prefix_caseless_ascii(episode, series) {
			Ok(rest) if !Str.is_empty(series) and Str.starts_with(rest, " ") => "...${rest}"
			_ => episode
		}

	starts_lowercase : Str -> Bool
	starts_lowercase = |text|
		match Str.to_utf8(text).first() {
			Ok(byte) => byte >= 97 and byte <= 122
			Err(_) => False
		}

	## Releases tag e.g. "Folge 214: und der Geisterbunker" or "Folge 238:
	## Falsche Schuld (Folge 238)". Tags vary between releases, so this only
	## suggests prompt defaults. German titles start capitalized, so a lowercase
	## start means the release cut off the series name.
	parse_album : Str -> Try({ number : U64, episode : Str }, [NoMatch])
	parse_album = |album| {
		parts = Str.split_first(album, ": ").map_err(|_| NoMatch)?
		number = U64.from_str(Str.drop_prefix(parts.before, "Folge ")).map_err(|_| NoMatch)?
		episode = Str.drop_suffix(parts.after, " (Folge ${number.to_str()})")
		Ok({ number, episode: if (starts_lowercase(episode)) "... ${episode}" else episode })
	}

	title : { series : Str, number : U64, episode : Str } -> Str
	title = |parts| "${parts.series} ${parts.number.to_str()} - ${parts.episode}"

	file_stem : { file_series : Str, padding : U64, number : U64, episode : Str } -> Str
	file_stem = |parts| "${parts.file_series} ${Chapters.pad_left(parts.number, parts.padding)} - ${parts.episode}"
}

expect Naming.check_file_name("Die drei ??? 214").is_err()
expect Naming.check_file_name("a.") == Err("'a.' ends with a dot or space, which Windows drops.")
expect Naming.check_file_name("Die drei Fragezeichen 214 - ... und der Geisterbunker.mka") == Ok("Die drei Fragezeichen 214 - ... und der Geisterbunker.mka")

expect Naming.elide_series("Die drei ??? und der Geisterbunker", "Die drei ???") == "... und der Geisterbunker"
expect Naming.elide_series("TKKGs Geheimnis", "TKKG") == "TKKGs Geheimnis"

expect Naming.parse_album("Folge 214: und der Geisterbunker") == Ok({ number: 214, episode: "... und der Geisterbunker" })
expect Naming.parse_album("Folge 238: Falsche Schuld (Folge 238)") == Ok({ number: 238, episode: "Falsche Schuld" })
expect Naming.parse_album("Der Hobbit") == Err(NoMatch)

expect Naming.file_stem({ file_series: "Die drei Fragezeichen", padding: 3, number: 7, episode: "x" }) == "Die drei Fragezeichen 007 - x"
