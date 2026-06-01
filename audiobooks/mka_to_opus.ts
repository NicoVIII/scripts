import { parseArgs } from "@std/cli/parse-args";
import * as path from "@std/path";
import { Result } from "typescript-result";

type Path = string;

// TODO: Branded type and make a value object for existing files?

type Args = {
  input_file: Path;
  bitrate: string;
};

class ArgumentsInvalidError extends Error {
  readonly type = "arguments-invalid-error";
}

function parse_arguments(args: string[]) {
  const parsed_args = parseArgs(Deno.args, {
    string: ["input_file", "bitrate"],
  });

  const inputFile = parsed_args.input_file ?? parsed_args._[0];
  const bitrate = parsed_args.bitrate ?? parsed_args._[1];

  // Check if the required arguments are provided
  if (!inputFile || !bitrate) {
    return Result.error(new ArgumentsInvalidError());
  }

  return Result.ok(
    {
      input_file: inputFile.toString(),
      bitrate: bitrate.toString(),
    } satisfies Args,
  );
}

type FileNames = {
  input_file: Path;
  cover_file: Path;
  output_file: Path;
};

function prepare_file_names(input_file: Path): FileNames {
  const base_path = path.dirname(input_file);

  return {
    input_file,
    cover_file: path.join(
      base_path,
      `${path.basename(input_file, path.extname(input_file))}.jpg`,
    ),
    output_file: path.join(
      base_path,
      `${path.basename(input_file, path.extname(input_file))}.opus`,
    ),
  };
}

const args = parse_arguments(Deno.args).getOrElse(() => {
  console.error("Usage: <input_file> <bitrate>");
  Deno.exit(1);
});
