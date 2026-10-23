import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path

## Mounts Samba shares with mount.cifs through sudo.
Smb :: {}.{

	## Tried in order until the server accepts one, together with
	## `security_modes`.
	versions : List(Str)
	versions = ["3.1.1", "3.0", "2.1", "2.0", "1.0"]

	security_modes : List(Str)
	security_modes = ["ntlmssp", "ntlmv2", "ntlm"]

	## `domain` may be empty.
	credentials_file : { username : Str, password : Str, domain : Str } -> Str
	credentials_file = |credentials| {
		domain = if (Str.is_empty(credentials.domain)) "" else "domain=${credentials.domain}\n"
		"username=${credentials.username}\npassword=${credentials.password}\n${domain}"
	}

	id! : Str => Try(Str, _)
	id! = |flag| Ok(Cmd.new("id").arg(OsStr.from_str(flag)).capture!()?.trim())

	## The files are owned by the calling user, so the encode can write them.
	mount_options! : Path => Try(Str, _)
	mount_options! = |credentials_path| {
		path = credentials_path.to_str().map_err(|_| NonUtf8Path(credentials_path))?
		Ok("credentials=${path},uid=${id!("-u")?},gid=${id!("-g")?},iocharset=utf8")
	}

	## The last failure's message is kept for the error.
	mount_any! : Str, Path, Str => Try({}, _)
	mount_any! = |unc, mount_point, options| {
		var $last_error = ""
		for version in versions {
			for security in security_modes {
				output = Cmd.new("sudo")
					.args(["-n", "mount.cifs", OsStr.from_str(unc)])
					.arg(mount_point.to_os_str())
					.args(["-o", OsStr.from_str("${options},vers=${version},sec=${security}")])
					.run!()?
				match output.status {
					Exited(0) => return Ok({})
					_ => {
						$last_error = output.stderr_utf8_lossy().trim()
					}
				}
			}
		}
		Err(MountFailed(unc, $last_error))
	}

	## The password goes through a credentials file in a private temp dir, so
	## it doesn't show up in the process list.
	mount! : Str, { username : Str, password : Str, domain : Str } => Try(Path, _)
	mount! = |unc, credentials| {
		credentials_dir = Env.create_temp_dir_with_prefix!("smb_credentials_")?
		credentials_path = credentials_dir.join("credentials")
		mount_point = Env.create_temp_dir_with_prefix!("samba_mount_")?
		result = match credentials_path.write_utf8!(credentials_file(credentials)) {
			Ok({}) =>
				match mount_options!(credentials_path) {
					Ok(options) => mount_any!(unc, mount_point, options)
					Err(err) => Err(err)
				}
			Err(err) => Err(err)
		}
		credentials_dir.delete_all!()?
		match result {
			Ok({}) => Ok(mount_point)
			Err(err) => {
				mount_point.delete_empty!()?
				Err(err)
			}
		}
	}

	## Removes only an empty mount point, so a failed unmount can't take the
	## share's files with it.
	unmount! : Path => Try({}, _)
	unmount! = |mount_point| {
		Cmd.new("sudo").args(["-n", "umount"]).arg(mount_point.to_os_str()).call!()?
		mount_point.delete_empty!()
	}

	## Runs `callback!` with the share mounted and unmounts it afterward.
	with_mount! : Str, { username : Str, password : Str, domain : Str }, (Path => Try(a, err)) => Try(a, _)
	with_mount! = |unc, credentials, callback!| {
		mount_point = mount!(unc, credentials)?
		result = callback!(mount_point)
		unmount!(mount_point)?
		result
	}

	## Asks for the sudo password once, then refreshes sudo's timestamp in the
	## background while `callback!` runs, since its encodes can outlast the
	## timeout and the unmount would then wait for a password.
	with_sudo! : (() => Try(a, err)) => Try(a, _)
	with_sudo! = |callback!| {
		Cmd.new("sudo").arg("-v").inherit_stdio().call!()?
		keepalive = Cmd.new("sh")
			.args(["-c", "while sleep 60; do sudo -n true; done"])
			.stdin(Null)
			.stdout(Null)
			.stderr(Null)
			.manage_tree(True)
			.spawn!()?
		result = callback!()
		keepalive.close!()?
		result
	}

	describe_mount_failure : Str, Str -> Str
	describe_mount_failure = |unc, last_error| {
		tried = "SMB ${Str.join_with(versions, ", ")} with sec ${Str.join_with(security_modes, ", ")}"
		"Could not mount ${unc} with ${tried}. Last error: ${last_error}"
	}

	describe_error : _ -> Try(Str, [Unknown])
	describe_error = |err|
		match err {
			MountFailed(unc, last_error) => Ok(describe_mount_failure(unc, last_error))
			_ => Err(Unknown)
		}
}

expect Smb.credentials_file({ username: "u", password: "p w", domain: "" }) == "username=u\npassword=p w\n"
expect Smb.credentials_file({ username: "u", password: "p", domain: "D" }) == "username=u\npassword=p\ndomain=D\n"
