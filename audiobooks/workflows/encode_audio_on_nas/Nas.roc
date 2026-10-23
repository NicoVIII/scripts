import pf.Path
import shared.Config

## Which NAS to log in to, from `nas.toml` in `Config`'s TOML subset:
## `server` (string), and the optional `username` (string, the login
## prompt's default) and `domain` (string, the SMB domain or workgroup).
## Kept outside the repository, which is public.
Nas :: {}.{

	config_file! : () => Try(Path, _)
	config_file! = || Ok(Config.dir!()?.join("nas.toml"))

	set_key : { server : Try(Str, [Missing]), username : Str, domain : Str }, Str, Str -> Try({ server : Try(Str, [Missing]), username : Str, domain : Str }, Str)
	set_key = |nas, key, value| {
		text = Config.parse_string(value)?
		match key {
			"server" => Ok({ ..nas, server: Ok(text) })
			"username" => Ok({ ..nas, username: text })
			"domain" => Ok({ ..nas, domain: text })
			_ => Err("unknown key ${key}, expected server, username or domain")
		}
	}

	## An empty `username` or `domain` means none is set.
	parse : Str -> Try({ server : Str, username : Str, domain : Str }, [BadNasConfig(U64, Str)])
	parse = |content| {
		var $nas = { server: Err(Missing), username: "", domain: "" }
		var $line_nr = 0
		for line in Str.split_on(content, "\n") {
			$line_nr = $line_nr + 1
			nr = $line_nr
			match Config.parse_line(line) {
				Ok(Blank) => {}
				Ok(Table(_)) => return Err(BadNasConfig(nr, "expected key = value, this file has no tables"))
				Ok(Entry(key, value)) => {
					$nas = set_key($nas, key, value).map_err(|message| BadNasConfig(nr, message))?
				}
				Err(message) => return Err(BadNasConfig(nr, message))
			}
		}
		match $nas.server {
			Ok(server) if !Str.is_empty(server) => Ok({ server, username: $nas.username, domain: $nas.domain })
			_ => Err(BadNasConfig($line_nr, "server is missing"))
		}
	}

	## A missing file means the NAS isn't set up yet.
	load! : () => Try([Missing, Found({ server : Str, username : Str, domain : Str })], _)
	load! = || {
		path = config_file!()?
		match path.read_utf8!() {
			Ok(content) =>
				match parse(content) {
					Ok(nas) => Ok(Found(nas))
					Err(BadNasConfig(nr, message)) => Err(BadNasConfig(path, nr, message))
				}
			Err(PathErr(NotFound, _)) => Ok(Missing)
			Err(err) => Err(err)
		}
	}

	render : { server : Str, username : Str, domain : Str } -> Str
	render = |nas| {
		domain = if (Str.is_empty(nas.domain)) "# domain = \"WORKGROUP\"\n" else "domain = ${Config.quote(nas.domain)}\n"
		"server = ${Config.quote(nas.server)}\nusername = ${Config.quote(nas.username)}\n${domain}"
	}

	save! : { server : Str, username : Str, domain : Str } => Try({}, _)
	save! = |nas| {
		Config.dir!()?.create_all!()?
		config_file!()?.write_utf8!(render(nas))
	}
}

expect {
	nas = { server: "192.168.1.10", username: "jane", domain: "" }
	Nas.parse(Nas.render(nas)) == Ok(nas)
}

expect Nas.parse("server = \"nas\"\ndomain = \"WG\"") == Ok({ server: "nas", username: "", domain: "WG" })
expect Nas.parse("username = \"jane\"\n") == Err(BadNasConfig(2, "server is missing"))
expect Nas.parse("[\"x\"]") == Err(BadNasConfig(1, "expected key = value, this file has no tables"))
expect Nas.parse("port = \"1\"").is_err()
