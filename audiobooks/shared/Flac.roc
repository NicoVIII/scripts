import pf.Cmd
import pf.Duration
import pf.OsStr
import pf.Path
import Extension

Flac :: {}.{

	## metaflac and the ffmpeg concat list need text paths, so non-UTF-8 paths
	## are rejected up front instead of being mangled.
	path_str : Path -> Try(Str, [NonUtf8Path(Path)])
	path_str = |path|
		match path.to_str() {
			Ok(str) => Ok(str)
			Err(InvalidStr(_)) => Err(NonUtf8Path(path))
		}

	is_flac : Path -> Bool
	is_flac = |path| Extension.matches(path, "flac")

	## `sort -V` puts "2.flac" before "10.flac", like merge_flac.sh did.
	version_sort! : List(Str) => Try(List(Str), _)
	version_sort! = |names| {
		input = Str.to_utf8(Str.join_with(names.map(|name| "${name}\u(0)"), ""))
		output = Cmd.new("sort").args(["-V", "-z"]).stdin(Bytes(input)).run!()?.require_success()?
		sorted = output.stdout_utf8()?
		Ok(sorted.split_on("\u(0)").drop_if(Str.is_empty))
	}

	## The FLAC files directly in `folder`, in chapter order.
	files! : Path => Try(List(Str), _)
	files! = |folder| {
		flacs = folder.list!()?.keep_if(is_flac).map_try(path_str)?
		if flacs.is_empty() {
			Err(NoFlacFiles(folder))
		} else {
			version_sort!(flacs)
		}
	}

	tag_value : List(Str), Str -> Try(Str, [NotFound])
	tag_value = |lines, tag|
		lines
			.keep_oks(|line| Str.drop_prefix_caseless_ascii(line, "${tag}="))
			.first()
			.map_err(|_| NotFound)

	## Split into whole seconds and remainder so long high-rate files can't
	## overflow U64 nanoseconds.
	samples_to_duration : U64, U64 -> Duration
	samples_to_duration = |samples, sample_rate|
		Duration.nanos((samples // sample_rate) * 1_000_000_000 + (samples % sample_rate) * 1_000_000_000 // sample_rate)

	## Sample counts give exact durations, unlike ffmpeg's rounded ones.
	info! : Str => Try({ path : Str, duration : Duration, sample_rate : U64, title : Try(Str, [NotFound]), album : Try(Str, [NotFound]), album_artist : Try(Str, [NotFound]) }, _)
	info! = |path| {
		output = Cmd.new("metaflac")
			.args(["--show-total-samples", "--show-sample-rate", "--show-tag=TITLE", "--show-tag=ALBUM", "--show-tag=ALBUMARTIST"])
			.arg(OsStr.from_str(path))
			.capture!()?
		match output.trim_end().split_on("\n") {
			[samples_str, rate_str, .. as tags] => {
				samples = U64.from_str(samples_str)?
				sample_rate = U64.from_str(rate_str)?
				Ok({
					path,
					duration: samples_to_duration(samples, sample_rate),
					sample_rate,
					title: tag_value(tags, "TITLE"),
					album: tag_value(tags, "ALBUM"),
					album_artist: tag_value(tags, "ALBUMARTIST"),
				})
			}
			_ => Err(UnexpectedMetaflacOutput(path, output))
		}
	}

	## The concat demuxer assumes all files share one stream layout.
	check_sample_rates : List({ sample_rate : U64, .. }) -> Try({}, [MixedSampleRates(List(U64))])
	check_sample_rates = |infos| {
		rates = infos.map(|info| info.sample_rate)
		match rates {
			[first, ..] if rates.all(|rate| rate == first) => Ok({})
			_ => Err(MixedSampleRates(rates))
		}
	}
}

expect Flac.check_sample_rates([{ sample_rate: 44100 }, { sample_rate: 48000 }]) == Err(MixedSampleRates([44100, 48000]))
