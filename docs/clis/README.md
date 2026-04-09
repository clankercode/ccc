# CLI Notes

These files record the current state of each supported coding CLI from the perspective of `ccc`.

They intentionally mix:

- verified local help output
- upstream official docs when available
- `ccc`-specific notes about what is safe to normalize

Current files:

- [opencode.md](/home/xertrov/src/call-coding-clis/docs/clis/opencode.md)
- [claude.md](/home/xertrov/src/call-coding-clis/docs/clis/claude.md)
- [codex.md](/home/xertrov/src/call-coding-clis/docs/clis/codex.md)
- [kimi.md](/home/xertrov/src/call-coding-clis/docs/clis/kimi.md)
- [crush.md](/home/xertrov/src/call-coding-clis/docs/clis/crush.md)
- [roocode.md](/home/xertrov/src/call-coding-clis/docs/clis/roocode.md)

If a CLI changes upstream, the fastest refresh path is:

```sh
<cli> --version
<cli> --help
```

Then update the corresponding file here before changing `ccc` runner assembly.
