# Review the nvm fallback in .zshrc

Status (2026-11-27): open. Review around 2027-11.

## Background

`zshrc/.zshrc` loads nvm once, near the end: `/usr/share/nvm/init-nvm.sh` (Arch package), with an
`elif` fallback to a git-cloned `~/.nvm/nvm.sh` for non-Arch machines. The old early `~/.nvm` block
was removed because on Arch it loaded the same file twice.

The fallback branch touches `~/.cache/zshrc-nvm-fallback-used` whenever it runs.

## Review (around 2027-11)

On each machine:

```
ls -l ~/.cache/zshrc-nvm-fallback-used
```

If no machine touched the marker in the last year, delete the `elif` branch from `.zshrc`.

From 2027-11-27 the shell prints a blue reminder at startup. Delete the reminder lines (the
`zmodload` and `EPOCHSECONDS` lines) together with the `elif` branch.
