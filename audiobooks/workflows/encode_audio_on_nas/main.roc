## Create the missing or outdated m4a working copies on the NAS from the
## source mkas in the library entries' "source/" folders. Asks for the Samba
## login and sudo, which mounts the shares; the NAS itself is set up once and
## remembered. Working copies from an older encoding version or with another
## bitrate are re-encoded; `--dry-run` only lists what would be.
##
## Usage: encode_audio_on_nas.sh [--dry-run]
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
import Nas
import Smb
import WorkingCopies

## An empty subfolder scans the whole share.
shares : List({ name : Str, subfolders : List(Str), bitrate : Str })
shares = [
	{ name: "books", subfolders: [""], bitrate: "48k" },
	{ name: "audiobooks", subfolders: ["Hörspiele"], bitrate: "64k" },
]

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
		Usage => "Usage: encode_audio_on_nas.sh [--dry-run]"
		EmptyPassword => "The password can't be empty."
		BadNasConfig(path, line, message) => "${path.display()}, line ${line.to_str()}: ${message}"
		other => describe_path_error(other) ?? (Smb.describe_error(other) ?? Str.inspect(other))
	}

encode_source! : { mka : Path, entry : Path }, Str, { bitrate : Str, dry_run : Bool } => Try(Bool, _)
encode_source! = |source, shown, options| {
	if options.dry_run {
		return Ok(False)
	}
	WorkingCopies.encode!(source, options.bitrate)?
	Stdout.line!("OK   ${shown}")?
	Ok(True)
}

## Prints what happens to the source; `Ok(True)` when its working copy is
## current afterward.
process_source! : { mka : Path, entry : Path }, Str, { bitrate : Str, dry_run : Bool } => Try(Bool, _)
process_source! = |source, shown, options|
	match WorkingCopies.status!(source, options.bitrate)? {
		Current => {
			Stdout.line!("SKIP ${shown}")?
			Ok(True)
		}
		Missing => {
			Stdout.line!("RUN  ${shown}")?
			encode_source!(source, shown, options)
		}
		Outdated(why) => {
			Stdout.line!("REDO ${shown} (${why})")?
			encode_source!(source, shown, options)
		}
	}

## Counts sources whose working copy is current afterward. Failures are
## reported and skipped; only an interrupt stops the run.
encode_subfolder! : Path, { bitrate : Str, dry_run : Bool } => Try({ done : U64, total : U64 }, _)
encode_subfolder! = |root, options| {
	sources = WorkingCopies.scan!(root)?
	Stdout.line!("Found ${sources.len().to_str()} .mka file(s)")?
	var $done = 0
	for source in sources {
		shown = relative(source.mka, root)
		match process_source!(source, shown, options) {
			Ok(True) => {
				$done = $done + 1
			}
			Ok(False) => {}
			Err(Interrupted) => return Err(Interrupted)
			Err(err) => Stderr.line!("FAIL ${shown}: ${describe_file_error(err)}")?
		}
	}
	Ok({ done: $done, total: sources.len() })
}

encode_share! : Path, { name : Str, subfolders : List(Str), bitrate : Str }, Bool => Try({ done : U64, total : U64 }, _)
encode_share! = |mount_point, share, dry_run| {
	var $counts = { done: 0, total: 0 }
	for subfolder in share.subfolders {
		Stdout.line!("Subfolder ${if (Str.is_empty(subfolder)) "/" else subfolder} | bitrate ${share.bitrate}")?
		root = if (Str.is_empty(subfolder)) mount_point else mount_point.join(subfolder)
		if root.is_dir!()? {
			counts = encode_subfolder!(root, { bitrate: share.bitrate, dry_run })?
			$counts = { done: $counts.done + counts.done, total: $counts.total + counts.total }
		} else {
			Stderr.line!("Subfolder does not exist: ${root.display()}")?
		}
	}
	Ok($counts)
}

## A share that can't be mounted is skipped.
encode_shares! : Str, { username : Str, password : Str, domain : Str }, Bool => Try({ done : U64, total : U64 }, _)
encode_shares! = |server, credentials, dry_run| {
	var $counts = { done: 0, total: 0 }
	for share in shares {
		unc = "//${server}/${share.name}"
		Stdout.line!("\nShare ${unc}")?
		match Smb.with_mount!(unc, credentials, |mount_point| encode_share!(mount_point, share, dry_run)) {
			Ok(counts) => {
				$counts = { done: $counts.done + counts.done, total: $counts.total + counts.total }
			}
			Err(MountFailed(_, last_error)) => Stderr.line!("Skipping the share. ${Smb.describe_mount_failure(unc, last_error)}")?
			Err(err) => return Err(err)
		}
	}
	Ok($counts)
}

## The first time, the server and username are asked and offered for saving;
## later runs only confirm the saved username.
ask_nas! : () => Try({ server : Str, username : Str, domain : Str }, _)
ask_nas! = ||
	match Nas.load!()? {
		Found(nas) => Ok({ ..nas, username: Prompt.ask_parsed!("Samba username", nas.username, Prompt.non_empty)? })
		Missing => {
			server = Prompt.ask_parsed!("NAS server (host name or IP)", "", Prompt.non_empty)?
			username = Prompt.ask_parsed!("Samba username", "", Prompt.non_empty)?
			nas = { server, username, domain: "" }
			remember = Prompt.ask_parsed!("Remember this in ${Nas.config_file!()?.display()}? (y/n)", "y", Prompt.parse_yes_no)?
			if remember {
				Nas.save!(nas)?
			}
			Ok(nas)
		}
	}

parse_args : List(OsStr) -> Try({ dry_run : Bool }, [Usage])
parse_args = |args|
	match args {
		[] => Ok({ dry_run: False })
		[flag] if flag == OsStr.from_str("--dry-run") => Ok({ dry_run: True })
		_ => Err(Usage)
	}

summary : { done : U64, total : U64 }, Bool -> Str
summary = |counts, dry_run|
	if dry_run {
		"${(counts.total - counts.done).to_str()} of ${counts.total.to_str()} would be encoded"
	} else {
		"Done: ${counts.done.to_str()}/${counts.total.to_str()} successful"
	}

run! : List(OsStr) => Try({}, _)
run! = |args| {
	parsed = parse_args(args)?
	nas = ask_nas!()?
	password = Prompt.ask_secret!("Samba password")?
	if Str.is_empty(password) {
		return Err(EmptyPassword)
	}
	Stdout.line!("Authorizing sudo once for mount/unmount...")?
	counts = Smb.with_sudo!(|| encode_shares!(nas.server, { username: nas.username, password, domain: nas.domain }, parsed.dry_run))?
	Stdout.line!("\n${summary(counts, parsed.dry_run)}")
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
