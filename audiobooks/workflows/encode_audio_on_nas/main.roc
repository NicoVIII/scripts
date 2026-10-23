## Create the missing m4a working copies on the NAS from the source mkas in
## the library entries' "source/" folders. Asks for the Samba login and sudo,
## which mounts the shares.
##
## Usage: encode_audio_on_nas.sh
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	shared: "../../shared/main.roc",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Stderr
import shared.Aac
import shared.Prompt
import Smb
import WorkingCopies

server : Str
server = "192.168.2.8"

## Optional SMB domain/workgroup.
domain : Str
domain = ""

## An empty subfolder scans the whole share.
shares : List({ name : Str, subfolders : List(Str), bitrate : Str })
shares = [
	{ name: "books", subfolders: [""], bitrate: "48k" },
	{ name: "audiobooks", subfolders: ["Hörspiele"], bitrate: "64k" },
]

non_empty : Str -> Try(Str, Str)
non_empty = |answer| if (Str.is_empty(answer)) Err("This can't be empty.") else Ok(answer)

relative : Path, Path -> Str
relative = |path, root| Str.drop_prefix(path.display(), "${root.display()}/")

describe_path_error : _ -> Try(Str, [Unknown])
describe_path_error = |err|
	match err {
		PathErr(NotFound, path) => Ok("'${path.display()}' does not exist.")
		NonUtf8Path(path) => Ok("Path '${path.display()}' is not valid UTF-8.")
		_ => Err(Unknown)
	}

## Separate from `describe_error` because these errors are handled per file
## and never reach `run!`.
describe_file_error : _ -> Str
describe_file_error = |err| describe_path_error(err) ?? (WorkingCopies.describe_error(err) ?? (Aac.describe_error(err) ?? Str.inspect(err)))

describe_error : _ -> Str
describe_error = |err|
	match err {
		Usage => "Usage: encode_audio_on_nas.sh"
		EmptyPassword => "The password can't be empty."
		other => describe_path_error(other) ?? (Smb.describe_error(other) ?? Str.inspect(other))
	}

## Counts files whose working copy exists afterward. Failures are reported
## and skipped; only an interrupt stops the run.
encode_subfolder! : Path, Str => Try({ done : U64, total : U64 }, _)
encode_subfolder! = |root, bitrate| {
	sources = WorkingCopies.scan!(root)?
	Stdout.line!("Found ${sources.len().to_str()} .mka file(s)")?
	var $done = 0
	for source in sources {
		shown = relative(source.mka, root)
		if WorkingCopies.has_working_copy!(source)? {
			Stdout.line!("SKIP ${shown}")?
			$done = $done + 1
		} else {
			Stdout.line!("RUN  ${shown}")?
			match WorkingCopies.encode!(source, bitrate) {
				Ok({}) => {
					Stdout.line!("OK   ${shown}")?
					$done = $done + 1
				}
				Err(Interrupted) => return Err(Interrupted)
				Err(err) => Stderr.line!("FAIL ${shown}: ${describe_file_error(err)}")?
			}
		}
	}
	Ok({ done: $done, total: sources.len() })
}

encode_share! : Path, { name : Str, subfolders : List(Str), bitrate : Str } => Try({ done : U64, total : U64 }, _)
encode_share! = |mount_point, share| {
	var $counts = { done: 0, total: 0 }
	for subfolder in share.subfolders {
		Stdout.line!("Subfolder ${if (Str.is_empty(subfolder)) "/" else subfolder} | bitrate ${share.bitrate}")?
		root = if (Str.is_empty(subfolder)) mount_point else mount_point.join(subfolder)
		if root.is_dir!()? {
			counts = encode_subfolder!(root, share.bitrate)?
			$counts = { done: $counts.done + counts.done, total: $counts.total + counts.total }
		} else {
			Stderr.line!("Subfolder does not exist: ${root.display()}")?
		}
	}
	Ok($counts)
}

## A share that can't be mounted is skipped.
encode_shares! : { username : Str, password : Str, domain : Str } => Try({ done : U64, total : U64 }, _)
encode_shares! = |credentials| {
	var $counts = { done: 0, total: 0 }
	for share in shares {
		unc = "//${server}/${share.name}"
		Stdout.line!("\nShare ${unc}")?
		match Smb.with_mount!(unc, credentials, |mount_point| encode_share!(mount_point, share)) {
			Ok(counts) => {
				$counts = { done: $counts.done + counts.done, total: $counts.total + counts.total }
			}
			Err(MountFailed(_, last_error)) => Stderr.line!("Skipping the share. ${Smb.describe_mount_failure(unc, last_error)}")?
			Err(err) => return Err(err)
		}
	}
	Ok($counts)
}

run! : List(OsStr) => Try({}, _)
run! = |args| {
	if !args.is_empty() {
		return Err(Usage)
	}
	username = Prompt.ask_parsed!("Samba username", "", non_empty)?
	password = Prompt.ask_secret!("Samba password")?
	if Str.is_empty(password) {
		return Err(EmptyPassword)
	}
	Stdout.line!("Authorizing sudo once for mount/unmount...")?
	counts = Smb.with_sudo!(|| encode_shares!({ username, password, domain }))?
	Stdout.line!("\nDone: ${counts.done.to_str()}/${counts.total.to_str()} successful")
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
