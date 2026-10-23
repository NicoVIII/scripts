import pf.Cmd
import pf.Path

Ffmpeg :: {}.{
	concat_list : List(Str) -> Str
	concat_list = |files|
		Str.join_with(files.map(|file| "file '${Str.replace_each(file, "'", "'\\''")}'\n"), "")

	## Concatenates `files` (absolute paths, since the concat demuxer resolves
	## relative ones against the list file) into `output`, dropping embedded
	## pictures. The list file is written to `work_dir`.
	concat! : List(Str), Path, Path => Try({}, _)
	concat! = |files, work_dir, output| {
		list_file = work_dir.join("concat.txt")
		list_file.write_utf8!(concat_list(files))?
		Cmd.new("ffmpeg")
			.args(["-v", "warning", "-stats", "-f", "concat", "-safe", "0"])
			.arg("-i")
			.arg(list_file.to_os_str())
			.arg("-vn")
			.arg(output.to_os_str())
			.inherit_stdio()
			.call!()
	}
}

expect Ffmpeg.concat_list(["/a/it's.flac"]) == "file '/a/it'\\''s.flac'\n"
