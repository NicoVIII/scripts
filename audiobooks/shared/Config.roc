import pf.Env
import pf.Path

## Settings files of the audiobook scripts, in a TOML subset: `key = value`
## lines, `["<name>"]` tables and `#` comment lines.
Config :: {}.{

	## `$XDG_CONFIG_HOME/audiobooks`, falling back to `~/.config/audiobooks`.
	dir! : () => Try(Path, _)
	dir! = || {
		base = match Env.var_str!("XDG_CONFIG_HOME") {
			Ok(dir) if !Str.is_empty(dir) => Path.unix(dir)
			_ => Path.unix(Env.var_str!("HOME")?).join(".config")
		}
		Ok(base.join("audiobooks"))
	}

	quote_byte : U8
	quote_byte = 34

	backslash_byte : U8
	backslash_byte = 92

	## Only the `\"` and `\\` escapes; nothing else the settings need.
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
				Err(_) => Err("expected [\"<name>\"] or key = value")
			}
		}
	}
}

expect Config.parse_string(Config.quote("Die \"drei\" ???\\")) == Ok("Die \"drei\" ???\\")
expect Config.parse_line("  server = \"nas\"  ") == Ok(Entry("server", "\"nas\""))
