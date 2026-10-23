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
