import pf.Env
import pf.Path

WorkDir :: {}.{

	## Runs `callback!` with a fresh hidden directory in the current directory
	## and deletes it afterward. Not /tmp, which is often a RAM-backed tmpfs too
	## small for a merged book.
	in_cwd! : (Path => Try(a, err)) => Try(a, _)
	in_cwd! = |callback!| {
		work_dir = Env.create_temp_dir_in!(Env.cwd!()?, ".audiobook-")?
		result = callback!(work_dir)
		work_dir.delete_all!()?
		result
	}
}
