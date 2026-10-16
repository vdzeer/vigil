#!/bin/zsh
# One-time admin step for "Keep Running with Lid Closed".
#
# Keeping a Mac awake with its lid shut is a system setting only an administrator may change.
# This lets one account flip exactly that setting, on and off, without a password. Nothing
# else is allowed.
#
#   sudo allow-lid-closed.sh            allow it for the account that ran sudo
#   sudo allow-lid-closed.sh --remove   take it back and restore normal sleep
#
# Vigil runs it for you through the macOS password dialog the first time you switch the mode
# on; that route does not go through sudo, so the account is passed with --user.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run it with sudo: sudo $0"
  exit 1
fi

OWNER="${SUDO_USER:-}"
REMOVE=0
while (( $# )); do
  case "$1" in
    --remove) REMOVE=1 ;;
    --user) shift; OWNER="${1:-}" ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

RULE="/etc/sudoers.d/vigil"

if (( REMOVE )); then
  /bin/rm -f "$RULE"
  /usr/bin/pmset -a disablesleep 0
  echo "Removed. The Mac sleeps again when its lid is closed."
  exit 0
fi

# A user name is letters, digits, dot, dash and underscore; anything else could change the
# meaning of the rule below.
if [[ -z "$OWNER" || "$OWNER" == "root" || ! "$OWNER" =~ '^[A-Za-z0-9._-]+$' ]] || ! /usr/bin/id -u "$OWNER" >/dev/null 2>&1; then
  echo "Whose account is this for? Run with sudo from your own account, or pass --user NAME."
  exit 1
fi

# The draft is written next to the rule, in a folder only root can write to, so no other
# process can swap it between the check and the move. sudo skips file names with a dot, so the
# draft is never read as a rule. The move replaces the rule in one step.
TMP=$(/usr/bin/mktemp /etc/sudoers.d/.vigil.XXXXXX)
trap '/bin/rm -f "$TMP"' EXIT
print -r -- "$OWNER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
/usr/sbin/chown root:wheel "$TMP"
/bin/chmod 0440 "$TMP"
# A broken sudoers file locks sudo out, so it is checked before it is put in place.
/usr/sbin/visudo -cf "$TMP" >/dev/null
/bin/mv -f "$TMP" "$RULE"
echo "Done. Switch it on from the Vigil menu."
