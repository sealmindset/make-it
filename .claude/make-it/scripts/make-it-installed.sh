#!/bin/sh
# make-it-installed.sh -- print the make-it version installed for one user account, for a device-management
# inventory item. Prints "make-it <version>" or "make-it not installed", and exits 0 either way.
#
# Usage:  make-it-installed.sh [HOME_FOLDER]     (default: $HOME)
#
# It reads one file, <HOME_FOLDER>/.claude/make-it/VERSION, which make-it's installer writes on every install and
# update. It changes nothing and contacts nothing. Only letters, digits, ".", "+" and "-" from the file are printed,
# at most 64 of them: the file is the user's to edit, so its content is never trusted.
# A device-management script usually runs as root, whose $HOME is not the person's: pass each person's home folder.
f="${1:-$HOME}/.claude/make-it/VERSION"
v=""
if [ -f "$f" ]; then
  v="$(head -n 1 "$f" 2>/dev/null | tr -cd '0-9A-Za-z.+-' | cut -c1-64)"
fi
if [ -n "$v" ]; then
  echo "make-it $v"
else
  echo "make-it not installed"
fi
exit 0
