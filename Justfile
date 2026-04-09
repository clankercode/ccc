install-py:
	install -D -m 755 python/call_coding_clis/cli.py "$HOME/.local/bin/ccc-py"

install-rs: install-rust

install-rust:
	cargo install --path rust --force
