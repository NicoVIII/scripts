import pf.Duration

Chapters :: {}.{
	pad_left : U64, U64 -> Str
	pad_left = |n, width| {
		digits = n.to_str()
		len = Str.to_utf8(digits).len()
		if len >= width digits else "${Str.repeat("0", width - len)}${digits}"
	}

	format_timestamp : Duration -> Str
	format_timestamp = |duration| {
		ms = duration.to_millis()
		"${pad_left(ms // 3_600_000, 2)}:${pad_left((ms // 60_000) % 60, 2)}:${pad_left((ms // 1000) % 60, 2)}.${pad_left(ms % 1000, 3)}"
	}

	space : U8
	space = 32

	## Bytes at the same distance from the start (`FromStart`) or end
	## (`FromEnd`) that all names share.
	shared_len : List(List(U8)), [FromStart, FromEnd] -> U64
	shared_len = |names, side| {
		first = names.first() ?? []
		byte_at = |name, offset|
			match side {
				FromStart => name.get(offset)
				FromEnd => if offset < name.len() name.get(name.len() - 1 - offset) else Err(OutOfBounds)
			}
		var $len = 0
		var $matching = True
		for _ in first {
			at = $len
			if $matching and names.all(|name| byte_at(name, at) == byte_at(first, at)) {
				$len = $len + 1
			} else {
				$matching = False
			}
		}
		$len
	}

	## Cuts the shared bytes back to whole words: a prefix ends with a space,
	## a suffix starts with one. That also keeps multi-byte characters whole.
	word_len : List(U8), U64, [FromStart, FromEnd] -> U64
	word_len = |first, len, side|
		match side {
			FromStart => first.take_first(len).find_last_index(|byte| byte == space).map_ok(|index| index + 1) ?? 0
			FromEnd => first.drop_first(first.len() - len).find_first_index(|byte| byte == space).map_ok(|index| len - index) ?? 0
		}

	## A single shared word like "Teil" in "Teil 1: Der Anfang" is part of
	## the name, not repetition.
	at_least_two_words : List(U8) -> Bool
	at_least_two_words = |bytes| {
		words = Str.split_on(Str.from_utf8_lossy(bytes), " ").keep_if(|word| Str.to_utf8(word).any(|byte| (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte >= 128))
		words.len() >= 2
	}

	## A name made only of digits and punctuation, like "1" or "1.1", says
	## nothing without the text that was cut off.
	has_letter : Str -> Bool
	has_letter = |name| Str.to_utf8(name).any(|byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte >= 128)

	unwrap_brackets : List(Str) -> List(Str)
	unwrap_brackets = |names|
		if names.all(|name| Str.starts_with(name, "(") and Str.ends_with(name, ")")) {
			names.map(|name| Str.trim(Str.drop_suffix(Str.drop_prefix(name, "("), ")")))
		} else {
			names
		}

	## Drops `prefix` and `suffix` bytes, or fails if that leaves a name
	## without letters.
	strip : List(List(U8)), U64, U64 -> Try(List(Str), [Meaningless])
	strip = |names, prefix, suffix| {
		if names.any(|name| prefix + suffix >= name.len()) {
			return Err(Meaningless)
		}
		stripped = unwrap_brackets(names.map(|name| Str.trim(Str.from_utf8_lossy(name.sublist({ start: prefix, len: name.len() - prefix - suffix })))))
		if stripped.all(has_letter) Ok(stripped) else Err(Meaningless)
	}

	## Drops what all chapter names repeat, like the episode title in
	## "215 - und die verlorene Zeit  (Teil 01)", and brackets around what's
	## left. Only whole words are dropped, at least two of them. Where dropping the prefix would leave only numbers, as with
	## "Kapitel 1", the prefix stays.
	clean : List(Str) -> List(Str)
	clean = |names| {
		if names.len() < 2 {
			return names
		}
		bytes = names.map(Str.to_utf8)
		first = bytes.first() ?? []
		prefix_len = word_len(first, shared_len(bytes, FromStart), FromStart)
		suffix_len = word_len(first, shared_len(bytes, FromEnd), FromEnd)
		prefix = if (at_least_two_words(first.take_first(prefix_len))) prefix_len else 0
		suffix = if (at_least_two_words(first.drop_first(first.len() - suffix_len))) suffix_len else 0
		strip(bytes, prefix, suffix) ?? (strip(bytes, 0, suffix) ?? names)
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

expect Chapters.pad_left(1234, 3) == "1234"

expect Chapters.clean(["215 - und die verlorene Zeit  (Titelsong)", "215 - und die verlorene Zeit  (Teil 01)"]) == ["Titelsong", "Teil 01"]
expect Chapters.clean(["Kapitel 1.1 - Throne of Glass 1: Die Erwählte", "Kapitel 1.2 & Kapitel 2.1 - Throne of Glass 1: Die Erwählte"]) == ["Kapitel 1.1", "Kapitel 1.2 & Kapitel 2.1"]
expect Chapters.clean(["Kapitel 1", "Kapitel 2"]) == ["Kapitel 1", "Kapitel 2"]
expect Chapters.clean(["Spuk auf Bloodywood Castle 1", "Spuk auf Bloodywood Castle 2"]) == ["Spuk auf Bloodywood Castle 1", "Spuk auf Bloodywood Castle 2"]
expect Chapters.clean(["Intro", "Prolog: Schatten der Angst"]) == ["Intro", "Prolog: Schatten der Angst"]
expect Chapters.clean(["Teil 1: Der Anfang", "Teil 2: Das Ende"]) == ["Teil 1: Der Anfang", "Teil 2: Das Ende"]
expect Chapters.clean(["Die drei ??? Größte Fälle: Eins", "Die drei ??? Größte Fälle: Zwei"]) == ["Eins", "Zwei"]
expect Chapters.clean(["Ein Junge überlebt 1", "Ein Junge überlebt 2", "Ansage"]) == ["Ein Junge überlebt 1", "Ein Junge überlebt 2", "Ansage"]
expect Chapters.clean(["Same", "Same"]) == ["Same", "Same"]
expect Chapters.clean(["Only one"]) == ["Only one"]
