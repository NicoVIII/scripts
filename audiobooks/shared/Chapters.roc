import pf.Duration

Chapters :: {}.{
	pad_left : U64, U64 -> Str
	pad_left = |n, width| {
		digits = n.to_str()
		missing = width - Str.to_utf8(digits).len()
		"${Str.repeat("0", missing)}${digits}"
	}

	format_timestamp : Duration -> Str
	format_timestamp = |duration| {
		ms = duration.to_millis()
		"${pad_left(ms // 3_600_000, 2)}:${pad_left((ms // 60_000) % 60, 2)}:${pad_left((ms // 1000) % 60, 2)}.${pad_left(ms % 1000, 3)}"
	}

	## OGM chapter text, which mkvmerge reads directly. Each part starts where
	## the previous ones end; summing exact durations before rounding keeps the
	## marks from drifting over long books.
	to_ogm : List({ title : Str, duration : Duration }) -> Str
	to_ogm = |parts| {
		var $start = Duration.zero
		var $lines = []
		for part in parts {
			number = ($lines.len() // 2 + 1).to_str()
			$lines = $lines.append("CHAPTER${number}=${format_timestamp($start)}")
			$lines = $lines.append("CHAPTER${number}NAME=${part.title}")
			$start = $start.plus(part.duration)
		}
		"${Str.join_with($lines, "\n")}\n"
	}
}

expect Chapters.format_timestamp(Duration.millis(3_723_004)) == "01:02:03.004"

expect {
	ogm = Chapters.to_ogm([{ title: "One", duration: Duration.millis(61_500) }, { title: "Two", duration: Duration.seconds(1) }])
	ogm == "CHAPTER1=00:00:00.000\nCHAPTER1NAME=One\nCHAPTER2=00:01:01.500\nCHAPTER2NAME=Two\n"
}

# Per-part rounding would put chapter 4 at 00:00:00.999.
expect {
	thirds = List.repeat({ title: "", duration: Duration.nanos(333_333_334) }, 4)
	Str.contains(Chapters.to_ogm(thirds), "CHAPTER4=00:00:01.000")
}
