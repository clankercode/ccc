use call_coding_clis::{build_prompt_spec, Runner};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() != 1 {
        eprintln!("usage: ccc \"<Prompt>\"");
        return ExitCode::from(1);
    }

    let mut spec = match build_prompt_spec(&args[0]) {
        Ok(spec) => spec,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::from(1);
        }
    };

    if let Ok(real_opencode) = env::var("CCC_REAL_OPENCODE") {
        if !real_opencode.is_empty() {
            spec.argv[0] = real_opencode;
        }
    }

    let result = Runner::new().run(spec);
    if !result.stdout.is_empty() {
        print!("{}", result.stdout);
    }
    if !result.stderr.is_empty() {
        eprint!("{}", result.stderr);
    }

    std::process::exit(result.exit_code)
}
