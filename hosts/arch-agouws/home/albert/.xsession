#!/bin/sh
# Display layout first: instant, and shouldn't wait behind the ~1s YubiKey
# challenge below.
~/.dotfiles/hosts/arch-agouws/arandr.sh

# Unlock the GNOME login keyring before i3 starts.
#
# /etc/lightdm/Xsession sources this after the xinitrc.d scripts (which import
# DISPLAY/XAUTHORITY) and immediately before `exec i3`. i3 launches the
# browsers and keyring-unlock simultaneously, so running the unlock from i3
# always races them. Doing it here means the --login daemon is up and unlocked
# before any client exists.
~/.local/bin/keyring-unlock
