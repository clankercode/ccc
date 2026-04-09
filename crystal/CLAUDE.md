# Crystal Build Notes

## CC Path Issue

The `cc` command in this environment is a Claude Code wrapper located at `~/.local/bin/cc`, not the real C compiler. This causes Crystal builds to fail with errors like:

```
error: unknown option '-o'
Error: execution of command failed with exit status 1: cc "${@}" -o /path/to/ccc ...
```

## Solution

When building Crystal projects, use the real GCC compiler via absolute path:

```bash
# Set CRYSTAL_CC to use the real compiler
export CRYSTAL_CC=/usr/bin/gcc

# Or use CC directly
crystal build src/call_coding_clis/ccc.cr -o ccc --link-flags="-fuse-ld=/usr/bin/ld"
```

## Alternative

Temporarily override PATH to exclude the wrapper:

```bash
PATH=/usr/bin:$PATH crystal build src/call_coding_clis/ccc.cr -o ccc
```
