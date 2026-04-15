build: build-py build-rs

build-py:
	python3 -m compileall -q python/call_coding_clis

build-rs:
	cargo build --manifest-path rust/Cargo.toml --bin ccc

install-py:
	install -D -m 755 python/call_coding_clis/cli.py "$HOME/.local/bin/ccc-py"

install-rs: install-rust

install-rust:
	cargo install --path rust --force
