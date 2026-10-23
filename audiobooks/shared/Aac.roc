import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr

## AAC HE v2 with libfdk_aac. Distribution ffmpeg builds lack it for licensing
## reasons, so ffmpeg runs in Docker.
Aac :: {}.{

	## Accepts e.g. 48k or 64K, the form ffmpeg's -b:a takes.
	check_bitrate : Str -> Try(Str, Str)
	check_bitrate = |bitrate| {
		digits = Str.drop_suffix(Str.drop_suffix(bitrate, "k"), "K")
		if digits != bitrate and U64.from_str(digits).is_ok() {
			Ok(bitrate)
		} else {
			Err("Bitrate must look like 48k or 64k, got '${bitrate}'.")
		}
	}

	split_path : Str -> { dir : Str, name : Str }
	split_path = |path|
		match Str.split_last(path, "/") {
			Ok(parts) => { dir: if (Str.is_empty(parts.before)) "/" else parts.before, name: parts.after }
			Err(_) => { dir: ".", name: path }
		}

	## Runs as the calling user so the output isn't owned by root.
	user! : () => Try(Str, _)
	user! = || {
		uid = Cmd.new("id").arg("-u").capture!()?.trim()
		gid = Cmd.new("id").arg("-g").capture!()?.trim()
		Ok("${uid}:${gid}")
	}

	docker_args : { user : Str, input : { dir : Str, name : Str }, output : { dir : Str, name : Str }, bitrate : Str, cover : Bool } -> List(Str)
	docker_args = |spec| {
		cover_args = if (spec.cover) ["-map", "0:v:0?", "-c:v", "copy", "-disposition:v:0", "attached_pic"] else ["-vn"]
		List.concat(
			[
				"run", "--rm", "--user", spec.user,
				"-v", "${spec.input.dir}:/input:ro",
				"-v", "${spec.output.dir}:/output",
				"jrottenberg/ffmpeg:ubuntu",
				"-hide_banner", "-v", "warning", "-stats", "-n",
				"-i", "/input/${spec.input.name}",
				"-map", "0:a:0", "-sn", "-dn",
				"-c:a", "libfdk_aac", "-profile:a", "aac_he_v2", "-b:a", spec.bitrate,
			],
			List.concat(cover_args, ["/output/${spec.output.name}"]),
		)
	}

	ffmpeg! : List(Str) => Try({}, _)
	ffmpeg! = |args| Cmd.new("docker").args(args.map(OsStr.from_str)).inherit_stdio().call!()

	path_str! : Path => Try(Str, _)
	path_str! = |path| path.absolute!()?.to_str().map_err(|_| NonUtf8Path(path))

	## Encodes the first audio track of `input` into `output`, keeping the cover
	## if `cover` is set. Covers ffmpeg can't copy fall back to audio only.
	encode! : { input : Path, output : Path, bitrate : Str, cover : Bool } => Try({}, _)
	encode! = |spec| {
		if !Cmd.check_available!("docker") {
			return Err(DockerMissing)
		}
		if spec.output.exists!()? {
			return Err(OutputExists(spec.output))
		}
		base = {
			user: user!()?,
			input: split_path(path_str!(spec.input)?),
			output: split_path(path_str!(spec.output)?),
			bitrate: spec.bitrate,
			cover: spec.cover,
		}
		match ffmpeg!(docker_args(base)) {
			Ok({}) => {}
			Err(BadExitStatus(_)) if spec.cover => {
				Stderr.line!("Could not keep the cover, retrying audio only.")?
				match spec.output.delete!() {
					Ok({}) | Err(PathErr(NotFound, _)) => {}
					Err(err) => return Err(err)
				}
				ffmpeg!(docker_args({ ..base, cover: False }))?
			}
			Err(err) => return Err(err)
		}
		if spec.output.size_in_bytes!()? == 0 {
			return Err(EmptyOutput(spec.output))
		}
		Ok({})
	}

	describe_error : _ -> Try(Str, [Unknown])
	describe_error = |err|
		match err {
			DockerMissing => Ok("docker is required but was not found in PATH.")
			OutputExists(output) => Ok("'${output.display()}' already exists.")
			EmptyOutput(output) => Ok("ffmpeg finished but '${output.display()}' is empty.")
			_ => Err(Unknown)
		}
}

expect Aac.check_bitrate("48k") == Ok("48k")
expect Aac.check_bitrate("48").is_err()
expect Aac.check_bitrate("k").is_err()
expect Aac.split_path("/a/b.mka") == { dir: "/a", name: "b.mka" }
expect Aac.split_path("/b.mka") == { dir: "/", name: "b.mka" }
