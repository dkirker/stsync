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
	echo "  -h        = This help"
	echo ""
	exit 0
}

# Parse options
#
CMDLINE=
while getopts uph opt
do
   	case "$opt" in
		p) CMDLINE="${CMDLINE}-p ";;
		u) CMDLINE="${CMDLINE}-u ";;
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

if which fswatch >/dev/null ; then 
	echo "Starting watch of ${CLEAN_SOURCE}"
else
	echo "ERROR: You must have fswatch installed"
	exit 255
fi

# Get all pending
bash stsync.sh -ql
# Monitor
fswatch -i '.+\.groovy' "${CLEAN_SOURCE}" | xargs -n 1 bash stsync.sh ${CMDLINE} -qlt -f