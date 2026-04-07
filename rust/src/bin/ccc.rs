use call_coding_clis::{build_prompt_spec, Runner};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() != 1 {
        eprintln!("usage: ccc \"<Prompt>\"");
        return ExitCode::from(1);
    }

    let spec = match build_prompt_spec(&args[0]) {
        Ok(spec) => spec,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::from(1);
        }
    };

    let result = Runner::new().run(spec);
    if !result.stdout.is_empty() {
        print!("{}", result.stdout);
    }
    if !result.stderr.is_empty() {
        eprint!("{}", result.stderr);
    }

    ExitCode::from(result.exit_code as u8)
}
