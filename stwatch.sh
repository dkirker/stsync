#!/bin/bash
#
# Sync Watcher
#
#
# Require fswatch (brew install fswatch)
#
#
SOURCE=

function usage() {
	echo ""
	echo "SmartThanks Watch (beta) - henric@smartthings.com"
	echo "================================================="
	echo "Companion script for stsync.sh which monitors the source directory and automatically"
	echo "performs uploads and publishing"
	echo ""
	echo "  -u        = Upload changes"
	echo "  -p        = Publish changes (can be combined with -u)"
	echo "  -d        = DISABLE preprocessor directives (see README.md)"
	echo "  -h        = This help"
	echo ""
	exit 0
}

# Parse options
#
CMDLINE=
while getopts upih opt
do
   	case "$opt" in
		p) CMDLINE="${CMDLINE}-p ";;
		u) CMDLINE="${CMDLINE}-u ";;
		i) CMDLINE="${CMDLINE}-i ";;
		h) usage;;
	esac
done

echo ""
echo "SmartThings Watch (beta)"
echo "========================"
echo ""

# Load user settings
#
if [ -f ~/.stsync ]; then
	source ~/.stsync
fi

if [ "${SOURCE}" == "" ]; then
	echo "ERROR: No source directory specified in ~/.stsync"
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
MONITOR="fswatch -l 0.1"
if [ $HAS_INOTIFY -gt 0 ]; then
	MONITOR="inotifywait -q --format %w%f -me close_write -r"
fi
${MONITOR} "${CLEAN_SOURCE}" | xargs -n 1 bash stsync.sh ${CMDLINE} -f
