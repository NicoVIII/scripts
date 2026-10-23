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
}
