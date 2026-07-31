# Clipboard helpers: xc (copy) and xcp (paste).
#
# xc prefers xclip when it is available and $DISPLAY is set; otherwise it falls back to OSC 52
# escape sequences, which work over SSH and inside containers where there is no X server.
# Passing --osc52 as the first argument forces the OSC 52 path even when xclip is usable.
#
# xcp is xclip only. OSC 52 paste would be a clipboard *read* query, which terminals disable by
# default (alacritty defaults to osc52 = "OnlyCopy") because it lets anything that can write to the
# tty exfiltrate the clipboard. We deliberately do not enable it, so there is no OSC 52 paste path.

# Copy to clipboard.
xc() {
	local use_osc52=0
	if [[ $1 == --osc52 ]]; then
		shift
		use_osc52=1
		print -u2 "Using OSC52 escape sequence to copy to clipboard"
	fi

	if [[ $use_osc52 -eq 1 ]] || ! command -v xclip &> /dev/null || [[ -z $DISPLAY ]]; then
		local input encoded
		input=$(cat "$@")
		encoded=$(printf '%s' "$input" | base64 | tr -d '\n')
		# OSC 52 writes are fire-and-forget: there is no acknowledgement, so an oversized payload
		# is dropped or clipped without any error. The real cap is terminal-dependent; 74994 is
		# xterm's documented default, not a universal value, so this is a warning and nothing more.
		if (( ${#encoded} > 74994 )); then
			print -u2 "xc: base64 payload is ${#encoded} bytes, which may exceed the terminal's" \
				"OSC 52 limit and be silently truncated (the limit is terminal-dependent;" \
				"74994 is xterm's documented default). Attempting the copy anyway."
		fi
		# Must go to the tty: if stdout is redirected to a file or a pipe the escape sequence lands
		# there instead and the terminal never sees it, so the copy silently does nothing.
		# Emitted plain on purpose: tmux understands OSC 52 natively via `set-clipboard on` and
		# forwards it, whereas a DCS passthrough wrap is dropped unless allow-passthrough is on.
		printf '\033]52;c;%s\a' "$encoded" > /dev/tty
	else
		xclip -selection clipboard "$@"
	fi
}

# Paste from clipboard. xclip only -- see the header comment for why OSC 52 is not used here.
xcp() {
	# No --osc52 flag here, unlike xc -- see the header comment.

	if command -v xclip &> /dev/null && [[ -n $DISPLAY ]]; then
		xclip -selection clipboard -o "$@"
	else
		print -u2 "xcp: paste requires xclip and an X display (DISPLAY must be set)." \
			"OSC 52 paste is intentionally unsupported."
		return 1
	fi
}
