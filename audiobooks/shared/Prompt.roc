import pf.Cmd
import pf.OsStr
import pf.Stdin
import pf.Stdout
import pf.Stderr

Prompt :: {}.{

	## Asks once; an empty answer takes `default`.
	ask! : Str, Str => Try(Str, _)
	ask! = |question, default| {
		hint = if (Str.is_empty(default)) "" else " [${default}]"
		Stdout.write!("${question}${hint}: ")?
		answer = Stdin.line!()?.trim()
		Ok(if (Str.is_empty(answer)) default else answer)
	}

	## Asks until `validate!` accepts the answer; its `Err` message is shown
	## before asking again.
	ask_valid! : Str, Str, (Str => Try(a, Str)) => Try(a, _)
	ask_valid! = |question, default, validate!| {
		answer = ask!(question, default)?
		match validate!(answer) {
			Ok(value) => Ok(value)
			Err(message) => {
				Stderr.line!(message)?
				ask_valid!(question, default, validate!)
			}
		}
	}

	## `ask_valid!` for a pure `parse`.
	ask_parsed! : Str, Str, (Str -> Try(a, Str)) => Try(a, _)
	ask_parsed! = |question, default, parse| ask_valid!(question, default, |answer| parse(answer))

	non_empty : Str -> Try(Str, Str)
	non_empty = |answer| if (Str.is_empty(answer)) Err("This can't be empty.") else Ok(answer)

	parse_yes_no : Str -> Try(Bool, Str)
	parse_yes_no = |answer|
		if Str.caseless_ascii_equals(answer, "y") {
			Ok(True)
		} else if Str.caseless_ascii_equals(answer, "n") {
			Ok(False)
		} else {
			Err("Answer y or n.")
		}

	## One line per option, numbered from 1, with the details lined up.
	menu : List({ label : Str, detail : Str, value : a }) -> Str
	menu = |options| {
		width = options.map(|option| Str.count_utf8_bytes(option.label)).max() ?? 0
		lines = options.map_with_index(
			|option, index| {
				padding = Str.repeat(" ", width - Str.count_utf8_bytes(option.label))
				"  ${(index + 1).to_str()}) ${option.label}${padding}   ${option.detail}"
			},
		)
		Str.join_with(lines, "\n")
	}

	## A number picks that option; anything else goes to `parse_other`.
	pick : List({ label : Str, detail : Str, value : a }), Str, (Str -> Try(a, Str)) -> Try(a, Str)
	pick = |options, answer, parse_other|
		match U64.from_str(answer) {
			Ok(number) if number >= 1 =>
				options.get(number - 1).map_ok(|option| option.value).map_err(|_| "Choose a number from 1 to ${options.len().to_str()}.")
			_ => parse_other(answer)
		}

	## Shows `options` as a numbered menu and asks until the answer is one of
	## their numbers or something `parse_other` accepts; `other` describes
	## that, e.g. "enter a bitrate like 56k".
	choose! : Str, List({ label : Str, detail : Str, value : a }), Str, (Str -> Try(a, Str)) => Try(a, _)
	choose! = |question, options, other, parse_other| {
		Stdout.line!("${question}:\n${menu(options)}")?
		ask_parsed!("Choose 1-${options.len().to_str()}, or ${other}", "", |answer| pick(options, answer, parse_other))
	}

	## stty acts on its stdin, which must be the terminal.
	stty! : Str => Try({}, _)
	stty! = |setting| Cmd.new("stty").arg(OsStr.from_str(setting)).stdin(Inherit).call!()

	## Asks without echoing the answer, e.g. for a password. The answer is
	## taken as typed, without trimming.
	ask_secret! : Str => Try(Str, _)
	ask_secret! = |question| {
		Stdout.write!("${question}: ")?
		stty!("-echo")?
		answer = Stdin.line!()
		stty!("echo")?
		# The Enter that ended the answer wasn't echoed either.
		Stdout.line!("")?
		answer
	}
}

expect Prompt.menu([{ label: "audiobook", detail: "48k", value: 1 }, { label: "audio drama", detail: "64k", value: 2 }]) == "  1) audiobook     48k\n  2) audio drama   64k"
expect Prompt.pick([{ label: "a", detail: "", value: "x" }], "1", |_| Err("no")) == Ok("x")
expect Prompt.pick([{ label: "a", detail: "", value: "x" }], "2", |_| Err("no")) == Err("Choose a number from 1 to 1.")
expect Prompt.pick([{ label: "a", detail: "", value: "x" }], "0", |_| Err("no")) == Err("no")
expect Prompt.pick([{ label: "a", detail: "", value: "x" }], "56k", |answer| Ok(answer)) == Ok("56k")
