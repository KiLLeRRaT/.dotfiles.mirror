# SSH agent forwarding + YubiKey when working remotely

Status (2026-10-20): **Part 1 done and tested on arch-agouws.** Parts 2 and 3 are open TODOs.

## Problem

On `arch-agouws`, auth works through the YubiKey:

- `pam_u2f` (FIDO PIN + touch) is a `sufficient` line in `/etc/pam.d/sudo`, `system-local-login`,
  `lightdm` and `polkit-1` (see `install/install-arch.sh`, "Configure Yubikey").
- 1Password unlocks through polkit, which also goes through `pam_u2f`.
- ssh and git use the 1Password SSH agent (`~/.1password/agent.sock`).
- Git commit signing uses 1Password's `op-ssh-sign`.

The account password is a very long string that can't be typed by hand, so **password fallback is
never usable**. Every auth path needs a YubiKey- or agent-based route.

When working on arch-agouws over SSH from `arch-macbookpro13`, ssh, git and signing went to the
1Password app on arch-agouws. It showed a GUI/polkit prompt on the arch-agouws screen, which you
can't see from the MacBook, so commands just hung. In detail:

- The old `~/.ssh/config` skipped 1Password only when `$SSH_TTY` was set. That variable is empty
  inside tmux panes on arch-agouws.
- `gpg.ssh.program` always called `/opt/1Password/op-ssh-sign`. `pull.rebase = true` re-signs
  rebased commits, so even `git pull` could trigger a signing prompt.
- The MacBook didn't forward its agent.

Forwarding the YubiKey itself (usbip) was rejected: it needs root and kernel modules, and the key
disappears from the MacBook while it's attached.

## Part 1: agent forwarding (DONE)

How it works: plug the YubiKey into the MacBook. The MacBook's 1Password agent is forwarded to
arch-agouws, so 1Password prompts and YubiKey PIN/touch all happen on the MacBook.

### Key facts about arch-agouws

- Reach it from the MacBook as `agouws.gouws.org` (192.168.111.250). `arch-agouws.gouws.org` doesn't
  resolve. `arch-agouws.local` resolves via mDNS, but its host key isn't in `known_hosts`.
- `~/.ssh` is a **stow-folded symlink** to `~/.dotfiles/ssh/.ssh`. New files there go straight into
  the repo; no stow run is needed.
- `.gitignore` ignores `ssh/.ssh/*` except for whitelisted files. **Any new file in `ssh/.ssh/` needs
  a `!ssh/.ssh/<name>` exception.**
- `~/.gitscripts` is a stow symlink to `~/.dotfiles/gitconfig/.gitscripts`.
- OpenSSH 10.x on this host puts forwarded agent sockets in `~/.ssh/agent/s.*.sshd.<pid>.*`, not
  `/tmp/ssh-*`. sshd deletes the socket when that session ends.
- sshd has `X11Forwarding yes`, so `~/.ssh/rc` must do the xauth setup itself.
- With `ForwardAgent yes` and no `SSH_AUTH_SOCK`, the MacBook's ssh forwards the agent set in
  `IdentityAgent` (1Password). This was verified: `ssh-add -l` on arch-agouws listed the MacBook's
  1Password keys.

### Changes (in `~/.dotfiles` on arch-agouws)

| Repo file | Change |
|---|---|
| `.gitignore` | Added `!ssh/.ssh/rc` after `!ssh/.ssh/*.pub`. |
| `ssh/.ssh/rc` (new) | Runs at every SSH login. Does the xauth setup, and if an agent was forwarded, points `~/.ssh/agent-forwarded.sock` at it (`ln -sfn`). |
| `ssh/.ssh/config` | Removed the `$SSH_TTY` Match. Added `Host agouws.gouws.org arch-agouws.gouws.org arch-agouws.local` with `ForwardAgent yes`. At the end of the file: `Match host * exec "test -S ~/.ssh/agent-forwarded.sock"` uses that link as `IdentityAgent`, and the negated Match uses `~/.1password/agent.sock`. |
| `gitconfig/.gitscripts/git-ssh-sign` (new, 0755) | If `~/.ssh/agent-forwarded.sock` is a live socket, runs `SSH_AUTH_SOCK=<link> exec ssh-keygen "$@"`. Otherwise runs `exec /opt/1Password/op-ssh-sign "$@"`. |
| `gitconfig/.gitconfig` | `[gpg "ssh"] program = ~/.gitscripts/git-ssh-sign`. git expands the `~`; checked with `git config --type=path`. |

`test -S` is false for a symlink whose target is gone. After you log out, everything falls back to
the local 1Password automatically.

The exact diffs, the full file contents and the original files are on arch-agouws in
`~/tmp/ssh-yubikey/`: `CHANGES.md`, `originals/` and `revert.sh`. Don't run `revert.sh` unless you
want to undo the change. The backups can be deleted once Part 1 is committed and has worked for a
while.

### Verified

- Plain SSH login no longer prints `ln: failed to create symbolic link`. The first `rc` version ran
  `ln` without checking whether an agent was forwarded.
- With no forwarded agent, `ssh -G github.com` shows IdentityAgent `~/.1password/agent.sock`.
- With `ssh -A`, the link points at the forwarded socket, IdentityAgent is the link, and `ssh-add -l`
  lists the MacBook's 1Password keys.
- After logout, the link no longer points at a live socket and ssh falls back to 1Password.
- `git log --show-signature -1` gives a good signature through the wrapper.
- User test: with 1Password locked on the MacBook,
  `ssh -A agouws.gouws.org ssh -T git@github.com` showed the 1Password unlock and YubiKey
  PIN/touch on the **MacBook** and authenticated.

### Gotchas found while testing

- `ssh -A host true` runs `true` remotely and exits. Anything you type next runs **locally**.
- If 1Password is already unlocked and has approved the key, no prompt appears. Lock it first
  (Ctrl+Shift+L) to see the full flow.
- An SSH session opened **without** forwarding has no `SSH_AUTH_SOCK`. ssh started from it falls
  back to the arch-agouws 1Password and shows the invisible prompt again.
- **The newest forwarded login takes over the link.** When diagnosing from another machine, use
  `ssh -a` (no forwarding) so you don't repoint it. Part 2 fixes the general case.

### Remaining steps for Part 1

1. In an `ssh -A` session on arch-agouws, test `git pull` and a signed commit in a throwaway repo
   (`git log --show-signature -1`).
2. Albert commits the 5 files on arch-agouws, then pulls on the MacBook. After that, plain
   `ssh agouws.gouws.org` forwards without `-A`. Agents must not stage or commit.
3. Delete `~/tmp/ssh-yubikey/` on arch-agouws when no longer needed.

## Part 2 (TODO): self-healing forwarded-agent link

**Problem.** `rc` repoints the link at every forwarded login, so the newest session always wins.
If that session closes while an older forwarded session is still open, the link points at nothing.
Commands in the older session then fall back to the arch-agouws 1Password, and the invisible prompt
comes back.

**Proposed design.**

1. Add a helper `ssh/.ssh/agent-forwarded` (0755, POSIX sh) and add a `!ssh/.ssh/agent-forwarded`
   line to `.gitignore`. It should:
   - exit 0 if `~/.ssh/agent-forwarded.sock` is already a live socket;
   - otherwise find the newest socket in `~/.ssh/agent/` (`ls -t`, no loops needed), repoint the
     link at it with `ln -sfn`, and exit 0;
   - otherwise exit 1;
   - print nothing, because `Match exec` and git both call it.
2. In `ssh/.ssh/config`, change the first block to `Match host * exec "~/.ssh/agent-forwarded"`.
   The fallback block can become `Match all` with `IdentityAgent ~/.1password/agent.sock`. ssh uses
   the first `IdentityAgent` value it gets, so the helper then runs only once. Check this with
   `ssh -G`.
3. In `git-ssh-sign`, replace the `test -S` with a call to `~/.ssh/agent-forwarded`.
4. Keep `rc` as it is, so a new login still takes over the link straight away.

**Check:** open two forwarded sessions A and B (B newer). Close B. In A, `ssh -T git@github.com`
should prompt on the MacBook, and `ls -la ~/.ssh/agent-forwarded.sock` should point at A's socket.

## Part 3 (TODO): sudo over SSH with the YubiKey (`pam_ssh_agent_auth`)

**Problem.** Over SSH there's no YubiKey on arch-agouws. `pam_u2f` fails and sudo falls back to the
password, which can't be used.

**Design.** `pam_ssh_agent_auth` lets sudo authenticate by asking the forwarded agent to sign a
challenge. 1Password on the MacBook then prompts for PIN and touch.

**Albert runs every `/etc` and package step himself. Agents only prepare the exact commands and
file contents.** Keep a root shell open while testing PAM changes.

1. Install `pam_ssh_agent_auth` from the AUR (check the package name and that it's maintained).
2. Create `/etc/security/sudo_authorized_keys` (root:root, 0644) containing **only** the public key
   of the 1Password SSH key to use. Decide which of the 17 1Password keys that is; probably
   `~/.ssh/id_ed25519.pub`.
3. In `/etc/pam.d/sudo`, add this line **directly below** the existing `pam_u2f` line:
   `auth sufficient pam_ssh_agent_auth.so file=/etc/security/sudo_authorized_keys`
   - At the desk, `pam_u2f` succeeds first, so nothing changes there.
   - Check how quickly `pam_u2f` (with `cue`) gives up when no key is plugged in.
4. Add a sudoers drop-in through `visudo -f /etc/sudoers.d/ssh-agent-auth`:
   `Defaults env_keep += "SSH_AUTH_SOCK"`.
5. Add a dotfiles change (zsh, `zshrc/.zshrc` or a plugin in `zshrc/.config/zsh/plugins/`): a `sudo`
   function that, when `~/.ssh/agent-forwarded.sock` is live, runs sudo with
   `SSH_AUTH_SOCK=~/.ssh/agent-forwarded.sock`, so old tmux panes use the right agent. After Part 2,
   call the helper instead. Check that `pam_ssh_agent_auth` accepts a symlinked socket path
   (it checks socket ownership); if not, resolve the link with `readlink -f` first.
6. Change only `/etc/pam.d/sudo`. Leave the other PAM files (`polkit-1`, `lightdm`,
   `system-local-login`) alone.

**Risks.**

- If 1Password on the MacBook is set to remember approvals, later sudo calls in that session won't
  prompt. Set this key to ask every time.
- Anything running as `albert` on arch-agouws during a forwarded session can ask for a sudo
  signature. Each request still needs approval in 1Password on the MacBook.
- polkit (`pkexec`, `systemctl` without sudo) still prompts on the arch-agouws screen over SSH. Use
  `sudo` remotely; extending agent auth to polkit is out of scope.
- If the agent check fails you get a `Password:` prompt you can't use. Ctrl-C gets you out.

**Check:** over `ssh -A`, with 1Password locked on the MacBook, `sudo -k; sudo true` should prompt
on the MacBook and succeed. At the desk, `sudo -k; sudo true` should still use `pam_u2f` as before.

## Rules for agents working on this

- Make changes in `~/.dotfiles` on the machine where they take effect. Albert commits; never stage
  or commit.
- Before changing anything, back up originals with `cp -p` to `~/tmp/<topic>/originals/` and write
  `CHANGES.md` (exact diffs, checks, test steps) plus a `revert.sh` that isn't run.
- Nothing that triggers a signature or 1Password approval without Albert present.
- Diagnose over SSH with `ssh -a`. From an agent sandbox on the MacBook, ssh to arch-agouws needs the
  sandbox disabled (DNS is blocked).
