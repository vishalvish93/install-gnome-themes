#
# Messaging
#

BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

message ()
{
	COLOR=${2:-$CYAN}
	echo -e "${COLOR}$@$RESET"
	if [ "$LOG" != '/dev/stdout' ]; then
		echo "$1" >> "$LOG"
	fi
}

comma-separated ()
{
	local R
	for A in "$@"; do
		if [ -z "$R" ]; then
			R=$1
		else
			R="$R, $A"
		fi
	done
	echo $R
}

sed-escape ()
{
	echo $1 | sed 's/[\/&]/\\&/g'
}

#
# Platform
#

os-name ()
{
	local OS=$(lsb_release --id --short)
	if [ -z "$OS" ]; then
		OS=$(cat /etc/*-release | grep '^NAME=' | cut --delimiter='=' --fields=2 | sed -e 's/^"//' -e 's/"$//')
	fi
	if [ -z "$OS" ]; then
		OS=$(head -1 /etc/issue | cut --delimiter=' ' --fields=1)
	fi
	echo "$OS"
}

gnome-version ()
{
	gnome-shell --version 2> /dev/null | cut --delimiter=' ' --fields=3 | cut --delimiter='.' --fields=1,2
}

gtk-version ()
{
	local VERSION=$(dpkg-version libgtk-3-0)
	if [ -z "$VERSION" ]; then
		VERSION=$(dpkg-version libgtk2.0-0)
	fi
	if [ -z "$VERSION" ]; then
		VERSION=$(rpm-version gtk3)
	fi
	if [ -z "$VERSION" ]; then
		VERSION=$(rpm-version gtk2)
	fi
	echo "$VERSION"
}

dpkg-version ()
{
	local PKG=$1
	dpkg -s "$PKG" 2> /dev/null | grep '^Version' | cut --delimiter=' ' --fields=2- | cut --delimiter='.' --fields=1,2
}

rpm-version ()
{
	local PKG=$1
	rpm --query --queryformat %{VERSION} "$PKG" 2> /dev/null | cut --delimiter='.' --fields=1,2
}

#
# Git Repositories
#

repository-timestamp ()
{
	git log --max-count=1 --date=short --pretty=format:%cr
}

repository-id ()
{
	git log --max-count=1 --pretty=format:%H
}

#
# Key-value
#

get-value () # [key] [db]
{
	local KEY=$1
	local DB=$2
	if [ -f "$DB" ]; then
		sed --quiet "s/^$KEY \(.*\)/\1/p" "$DB"
	fi
}

set-value () # [key] [value] [db]
{
	local KEY=$1
	local VALUE=$2
	local DB=$3
	if grep --quiet --no-messages "^$KEY " "$DB"; then
		sed --in-place "s/^\($KEY \)\(.*\)/\1$(sed-escape "$VALUE")/" "$DB" &>> "$LOG"
	else
		echo "$KEY $VALUE" >> "$DB"
	fi
}

#
# Themes
#

prepare () # [account] [repo] [branch] [themes...]
{
	local ACCOUNT=$1
	local REPO=$2
	local BRANCH=$3

	local URL="https://github.com/$ACCOUNT/$REPO"
	local KEY="$ACCOUNT|$REPO|$BRANCH"
	local LAST_ID=$(get-value "$KEY" "$CACHE_FILE")
	local NAMES=$(comma-separated "${@:4}")

	message "$NAMES:"

	message "  Fetching repository: $URL..."

	# Shallow git clone
	cleanup "$@"
	mkdir --parents "$WORK" &>> "$LOG"
	cd "$WORK"
	git clone "$URL" --branch "$BRANCH" --depth 1 "$REPO" &>> "$LOG"
	cd "$WORK/$REPO"

	CURRENT_ID=$(repository-id)
	if [ "$CURRENT_ID" == "$LAST_ID" ]; then
		message "  Last updated $(repository-timestamp)."
		message "  Already installed."
		cleanup "$@"
		return 1
	else
		message "  Last updated $(repository-timestamp)." "$BLUE"
		message "  Installing..." "$BLUE"
		if [ "$REPO" == Adapta ]; then
			message "  WARNING: Installation takes an especially long time due to rendering of all assets, please be patient!" "$BLUE"
		fi
		cd "$THEMES"
		rm --recursive --force "${@:4}" &>> "$LOG"
		cd "$WORK/$REPO"
		return 0
	fi
}

cleanup () # [account] [repo] [branch]
{
	local ACCOUNT=$1
	local REPO=$2
	local BRANCH=$3

	local KEY="$ACCOUNT|$REPO|$BRANCH"

	rm --recursive --force "$WORK/$REPO" &>> "$LOG"
	set-value "$KEY" "$CURRENT_ID" "$CACHE_FILE"
}

theme-cp () # [account] [repo] [branch] [themes...]
{
	local REPO=$2
	if ! prepare "$@"; then
		return
	fi
	cp --recursive "${@:4}" "$THEMES/" &>> "$LOG"
	cleanup "$@"
}

theme-mv () # [account] [repo] [branch] [theme]
{
	local REPO=$2
	local THEME=$4
	if ! prepare "$@"; then
		return
	fi
	mv "$WORK/$REPO" "$THEMES/$THEME" &>> "$LOG"
	cleanup "$@"
}

theme-tarball () # [account] [repo] [branch] [file] [dir] [themes...]
{
	local REPO=$2
	local FILE=$4
	local DIR=$5
	if ! prepare "$1" "$2" "$3" "${@:6}"; then
		return
	fi
	cd "$WORK/$REPO" &>> "$LOG"
	tar xvf "$FILE" "$DIR" &>> "$LOG"
	cd "$DIR" &>> "$LOG"
	mv * "$THEMES/" &>> "$LOG" 
	cleanup "$@"
}

theme-execute () # [account] [repo] [branch] [file] [themes...]
{
	local REPO=$2
	local FILE=$4
	if ! prepare "$1" "$2" "$3" "${@:5}"; then
		return
	fi
	cd "$WORK/$REPO" &>> "$LOG"
	chmod +x "$FILE" &>> "$LOG"
	"./$FILE" &>> "$LOG"
	cleanup "$@"
}

theme-script () # [account] [repo] [branch] [script] [themes...]
{
	local REPO=$2
	local SCRIPT=$4
	if ! prepare "$1" "$2" "$3" "${@:5}"; then
		return
	fi
	cd "$WORK/$REPO" &>> "$LOG"
	eval $SCRIPT &>> "$LOG"
	cleanup "$@"
}

theme-make () # [account] [repo] [branch] [theme]
{
	local REPO=$2
	local THEME=$4
	if ! prepare "$@"; then
		return
	fi
	make install INSTALL_DIR="$THEMES/$THEME" &>> "$LOG"
	cleanup "$@"
}

theme-make-destdir () # [account] [repo] [branch] [theme]
{
	local REPO=$2
	local THEME=$4
	if ! prepare "$@"; then
		return
	fi
	mkdir --parents "$WORK/$REPO/usr/share/themes" &>> "$LOG"
	make &>> "$LOG"
	make install DESTDIR="$WORK/$REPO" &>> "$LOG"
	cp --recursive "$WORK/$REPO/usr/share/themes/"* "$THEMES/" &>> "$LOG"
	cleanup "$@"
}

theme-autogen-prefix () # [account] [repo] [branch] [themes...]
{
	local REPO=$2
	if ! prepare "$@"; then
		return
	fi
	./autogen.sh --enable-parallel --prefix=$(pwd) $AUTOGEN_ARGS &>> "$LOG"
	make &>> "$LOG"
	# Adapta/Pop need to run "make install" separately
	make install &>> "$LOG"
	cp --recursive "$WORK/$REPO/share/themes/"* "$THEMES/" &>> "$LOG"
	cleanup "$@"
}

theme-autogen-destdir () # [account] [repo] [branch] [themes...]
{
	local REPO=$2
	if ! prepare "$@"; then
		return
	fi
	./autogen.sh --enable-parallel $AUTOGEN_ARGS &>> "$LOG"
	make install DESTDIR=$(pwd) &>> "$LOG"
	cp --recursive "$WORK/$REPO/usr/share/themes/"* "$THEMES/" &>> "$LOG"
	cleanup "$@"
}
