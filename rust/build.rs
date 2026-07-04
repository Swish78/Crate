use std::env;
use std::path::PathBuf;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "macos" {
        return;
    }

    // Tell Cargo to link libxpc (system-provided, no search path needed).
    println!("cargo::rustc-link-lib=framework=System");

    // Generate a C header via cbindgen.
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let header = PathBuf::from(&crate_dir).join("container_client.h");

    let config = cbindgen::Config::from_file("cbindgen.toml")
        .unwrap_or_default();

    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_config(config)
        .generate()
        .expect("cbindgen failed")
        .write_to_file(header);
}
