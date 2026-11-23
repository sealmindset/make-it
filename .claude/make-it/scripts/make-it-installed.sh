#!/bin/sh
# make-it-installed.sh -- print the make-it version installed for one user account, for a device-management
# inventory item. Prints one of three lines, and exits 0 in every case:
#   make-it <version>                        the VERSION file is a regular file whose first line looks like a version
#   make-it installed (version unreadable)   something named VERSION is there, but it is a symlink, a folder,
#                                            unreadable, or its first line is not a version
#   make-it not installed                    nothing named VERSION is there
#
# Usage:  make-it-installed.sh [HOME_FOLDER]     (default: $HOME)
#
# It reads one file, <HOME_FOLDER>/.claude/make-it/VERSION, which make-it's installer writes on every install and
# update, and at most its first 256 bytes. It never follows that file if it is a symlink (a person could point it
# at a file only root can read); a symlinked make-it folder, as dev-link.sh makes, is fine. It changes nothing and
# contacts nothing. A device-management script usually runs as root, whose $HOME is not the person's: pass each
# person's home folder.
LC_ALL=C; export LC_ALL
f="${1:-$HOME}/.claude/make-it/VERSION"
if [ ! -e "$f" ] && [ ! -L "$f" ]; then
  echo "make-it not installed"
  exit 0
fi
v=""
if [ -f "$f" ] && [ ! -L "$f" ]; then
  v="$(dd if="$f" bs=256 count=1 2>/dev/null | head -n 1 | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
fi
if [ "${#v}" -le 64 ] && printf '%s\n' "$v" | grep -Eq '^[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.]+)?$'; then
  echo "make-it $v"
else
  echo "make-it installed (version unreadable)"
fi
exit 0
