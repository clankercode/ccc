use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let version_path = manifest_dir.join("..").join("VERSION");
    println!("cargo:rerun-if-changed={}", version_path.display());
    if let Ok(version) = fs::read_to_string(&version_path) {
        let version = version.trim();
        if !version.is_empty() {
            println!("cargo:rustc-env=CCC_VERSION={version}");
        }
    }
}
