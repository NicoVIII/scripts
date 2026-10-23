import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr

## AAC HE v2 with libfdk_aac. Distribution ffmpeg builds lack it for licensing
## reasons, so ffmpeg runs in Docker.
Aac :: {}.{

	## 5.1 is the newest jrottenberg/ffmpeg whose fdk-aac still has HE-AAC; from
	## 6.0 on it's built without SBR, so only AAC-LC encodes. Older images (the
	## :ubuntu tag is ffmpeg 3.1) can't write covers into m4a. Pinned by digest
	## because a re-pushed tag would silently change the library's encoding.
	image : Str
	image = "jrottenberg/ffmpeg:5.1-ubuntu@sha256:478e5de92d31a88fcd643dc2d3dbb0c48f08d87c0df9cc455e1a1f9c2498704c"

	## Written into every m4a, so encode_audio_on_nas can find working copies
	## from an older encoding. Bump it with any change that alters the output;
	## the next run then re-encodes all older working copies. Version 1 is the
	## first that keeps the cover; untagged m4as predate it.
	version : U64
	version = 1

	## ffmpeg's `encoding_tool` is the iTunes ©too atom, which players leave
	## alone. A key of our own would need `-movflags use_metadata_tags`, which
	## moves every tag out of the iTunes atoms and drops the cover.
	encoding_tag : Str -> Str
	encoding_tag = |bitrate| "audiobooks-aac ${version.to_str()} ${bitrate}"

	parse_encoding_tag : Str -> Try({ version : U64, bitrate : Str }, [Untagged])
	parse_encoding_tag = |tag|
		match Str.split_on(Str.trim(tag), " ") {
			["audiobooks-aac", tag_version, bitrate] =>
				match U64.from_str(tag_version) {
					Ok(number) => Ok({ version: number, bitrate })
					Err(_) => Err(Untagged)
				}
			_ => Err(Untagged)
		}

	## The version and bitrate an m4a was encoded with.
	read_encoding! : Path => Try({ version : U64, bitrate : Str }, _)
	read_encoding! = |m4a| {
		tag = Cmd.new("ffprobe")
			.args(["-v", "error", "-show_entries", "format_tags=encoder", "-of", "default=noprint_wrappers=1:nokey=1"])
			.arg(m4a.to_os_str())
			.capture!()?
		parse_encoding_tag(tag)
	}

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
				image,
				"-hide_banner", "-v", "warning", "-stats", "-n",
				"-i", "/input/${spec.input.name}",
				"-map", "0:a:0", "-sn", "-dn",
				"-c:a", "libfdk_aac", "-profile:a", "aac_he_v2", "-b:a", spec.bitrate,
				"-metadata", "encoding_tool=${encoding_tag(spec.bitrate)}",
			],
			List.concat(cover_args, ["/output/${spec.output.name}"]),
		)
	}

	ffmpeg! : List(Str) => Try({}, _)
	ffmpeg! = |args| Cmd.new("docker").args(args.map(OsStr.from_str)).inherit_stdio().call!()

	remove_if_exists! : Path => Try({}, _)
	remove_if_exists! = |path|
		match path.delete!() {
			Ok({}) | Err(PathErr(NotFound, _)) => Ok({})
			Err(err) => Err(err)
		}

	## ffmpeg leaves a broken partial file behind when it fails.
	ffmpeg_to! : List(Str), Path => Try({}, _)
	ffmpeg_to! = |args, output|
		match ffmpeg!(args) {
			Ok({}) => Ok({})
			Err(err) => {
				remove_if_exists!(output)?
				Err(err)
			}
		}

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
		match ffmpeg_to!(docker_args(base), spec.output) {
			Ok({}) => {}
			Err(BadExitStatus(_)) if spec.cover => {
				Stderr.line!("Could not keep the cover, retrying audio only.")?
				ffmpeg_to!(docker_args({ ..base, cover: False }), spec.output)?
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

expect Aac.parse_encoding_tag(Aac.encoding_tag("48k")) == Ok({ version: Aac.version, bitrate: "48k" })
expect Aac.parse_encoding_tag("Lavf59.27.100\n") == Err(Untagged)
expect Aac.check_bitrate("48k") == Ok("48k")
expect Aac.check_bitrate("48").is_err()
expect Aac.check_bitrate("k").is_err()
expect Aac.split_path("/a/b.mka") == { dir: "/a", name: "b.mka" }
expect Aac.split_path("/b.mka") == { dir: "/", name: "b.mka" }
