use call_coding_clis::{
    build_prompt_spec, load_config, parse_args, print_help, print_usage, resolve_command, Runner,
};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();

    if args.is_empty() {
        print_usage();
        return ExitCode::from(1);
    }

    if args.len() == 1 && (args[0] == "--help" || args[0] == "-h") {
        print_help();
        return ExitCode::from(0);
    }

    let spec = if args.len() == 1 {
        match build_prompt_spec(&args[0]) {
            Ok(spec) => spec,
            Err(message) => {
                eprintln!("{message}");
                return ExitCode::from(1);
            }
        }
    } else {
        let parsed = parse_args(&args);
        if parsed.prompt.trim().is_empty() {
            eprintln!("prompt must not be empty");
            return ExitCode::from(1);
        }
        let config = load_config(None);
        match resolve_command(&parsed, Some(&config)) {
            Ok((argv, env_overrides)) => {
                let mut spec = call_coding_clis::CommandSpec::new(argv);
                for (k, v) in env_overrides {
                    spec = spec.with_env(k, v);
                }
                spec
            }
            Err(msg) => {
                eprintln!("{msg}");
                return ExitCode::from(1);
            }
        }
    };

    let mut spec = spec;
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
