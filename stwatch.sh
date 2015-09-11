#!/bin/bash
#
# Sync Watcher
#
#
# Require fswatch (brew install fswatch)
#
#
SOURCE=
QUIET=0

function log_warn() {
	if [ ${QUIET} -ne 0 ]; then return ; fi
	echo -n "WARN: "
	echo $@
}

function log_err() {
	# Always print errors
	echo -n "ERROR: "
	echo $@
}

function log_info() {
	if [ ${QUIET} -ne 0 ]; then return ; fi
	echo -n "INFO: "
	echo $@
}

function log() {
	if [ ${QUIET} -ne 0 ]; then return ; fi
	echo $@
}

function usage() {
	echo "Companion script for stsync.sh which monitors the source directory and automatically"
	echo "performs uploads and publishing"
	echo ""
	echo "  -d        = DISABLE preprocessor directives (see README.md)"
	echo "  -h        = This help"
	echo "  -p        = Publish changes (can be combined with -u)"
	echo "  -P <file> = Load a different profile other than ~/.stsync"
	echo "  -u        = Upload changes"
	echo ""
	exit 0
}

# Parse options
#
CMDLINE="-q "
PROFILE="~/.stsync"
PROFILECHG=0

echo ""
echo "SmartThings Watch (beta) - henric@smartthings.com"
echo "¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨"

while getopts upihP: opt
do
   	case "$opt" in
		p) CMDLINE="${CMDLINE}-p ";;
		u) CMDLINE="${CMDLINE}-u ";;
		i) CMDLINE="${CMDLINE}-i ";;
   		P) PROFILE=$OPTARG;PROFILECHG=1;CMDLINE="${CMDLINE}-P ${PROFILE} ";;
		h) usage;;
	esac
done

# Load user settings and allow override of the above values
#
eval pushd "$(dirname "${PROFILE}")" > /dev/null
PROFILE="$(pwd)/$(basename "${PROFILE}")"
popd > /dev/null
if [ -f "${PROFILE}" ]; then
	if [ ${PROFILECHG} -gt 0 ]; then
		log_info "Using ${PROFILE} instead of ~/.stsync"
	fi
	source "${PROFILE}"
else
	log_err "${PROFILE} does not exist"
	exit 1
fi

# Get the path of ourselves (need for symlinks)
#
eval pushd "$(dirname "$0")" > /dev/null
SCRIPTPATH="$(pwd)"
popd > /dev/null


if [ "${SOURCE}" == "" ]; then
	echo "ERROR: No source directory specified in ${PROFILE}"
	exit 255
fi

eval CLEAN_SOURCE="${SOURCE}"

if [ "$CMDLINE" == "" ] ; then
	echo "WARNING: You gave no arguments, so no changes will be uploaded or published"
	echo ""
fi

# Test compatibility
which fswatch >/dev/null ; HAS_FSWATCH=$(( 1 - $? ))
which inotifywait >/dev/null ; HAS_INOTIFY=$(( 1 - $? ))

if [ $HAS_INOTIFY -gt 0 -o $HAS_FSWATCH -gt 0 ] ; then
	echo "Starting watch of ${CLEAN_SOURCE}"
else
	echo "ERROR: You must have fswatch (OSX) or inotifywait (Linux/Cygwin) installed"
	exit 255
fi

# Monitor
MONITOR="fswatch -l 0.1 -e \"\.raw\""
if [ $HAS_INOTIFY -gt 0 ]; then
	MONITOR="inotifywait -q --format %w%f -me close_write -r"
fi
eval ${MONITOR} "${CLEAN_SOURCE}" | xargs -n 1 bash stsync.sh ${CMDLINE} -f
