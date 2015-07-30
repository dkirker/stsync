#!/bin/bash
#
# needs json for perl:
# brew install cpanm
# cpan install JSON
#
# To set the password, please create a file in your home directory
# called ".stsync" with the username and password fields set.
#
# DO NOT PLACE YOUR CREDENTIALS IN THIS FILE!
#

# Copy these into your ~/.stsync and edit
USERNAME=""
PASSWORD=""
SOURCE=""

USERAGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/43.0.2357.134 Safari/537.36"
HEADERS=/tmp/headers.txt
COOKIES=/tmp/cookies.txt

LOGIN_URL="https://graph.api.smartthings.com/j_spring_security_check"
LOGIN_FAIL="https://graph.api.smartthings.com/login/authfail?"
LOGIN_NEEDED="https://graph.api.smartthings.com/login/auth"

SMARTAPPS_URL="https://graph.api.smartthings.com/ide/apps"
DEVICETYPES_URL="https://graph.api.smartthings.com/ide/devices"
SMARTAPPS_LINK="/ide/app/editor/[^\"]+"
DEVICETYPES_LINK="/ide/device/editor/[^\"]+"

SMARTAPPS_TRANSLATE="https://graph.api.smartthings.com/ide/app/getResourceList?id="
SMARTAPPS_EXTRACT_IDFILE="(id\":\"[^\"]+)\",\"text\":\"[^\"]+"
SMARTAPPS_EXTRACT_ID="(id\":\"[^\"]+)"
SMARTAPPS_EXTRACT_FILE="(text\":\"[^\"]+)"
SMARTAPPS_DOWNLOAD="https://graph.api.smartthings.com/ide/app/getCodeForResource"

SMARTAPPS_COMPILE="https://graph.api.smartthings.com/ide/app/compile"
SMARTAPPS_PUBLISH="https://graph.api.smartthings.com/ide/app/publishAjax"

LOGGING_URL="https://graph.api.smartthings.com/ide/logs"

TOOL_JSONDEC="tools/json_decode.pl"
TOOL_JSONENC="tools/json_encode.pl"
TOOL_URLENC="tools/url_encode.pl"
TOOL_EXTRACT="tools/extract_device.pl"
TOOL_LOGGING="tools/livelogging.pl"

function checkAuthError() {
	if grep "${LOGIN_NEEDED}" "${HEADERS}" >/dev/null ; then
		echo "ERROR: Server refusing access, login has probably expired. Try again."
		rm /tmp/login_ok
		exit 255
	fi
}

function usage() {
	echo ""
	echo "SmartThings WebIDE Sync (beta) - henric@smartthings.com"
	echo "======================================================="
	echo "Simplifying the use of an external editor with the SmartThings development"
	echo "environment."
	echo ""
	echo "  -s        = Start a new repository (essentially downloading your ST apps and device types)"
	echo "  -S        = Same as -s but WILL overwrite any existing files. Use with care, you'll lose any changes you've made"
	echo "  -u        = Upload changes"
	echo "  -p        = Publish changes (can be combined with -u)"
	echo "  -f <file> = Make -u & -p apply to <file> ONLY"
	echo "  -h        = This help"
	echo "  -q        = Quiet (less output)"
	echo "  -l        = Always login"
	echo "  -L        = Live Logging (experimental)"
	echo ""
	exit 0
}

function download_repo() {
	TYPE=$1
	for FILE in ${2}; do
		FILE=${FILE##/ide/${TYPE}/editor/} # Strip off the editor stuff

		# Download the mapping between ID and actual script and save it
		# so we have that info readily available later.
		if [ "${TYPE}" == "app" ]; then
			curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" "https://graph.api.smartthings.com/ide/${TYPE}/getResourceList?id=${FILE}" -o "${RAW_SOURCE}/${TYPE}/${FILE}_translate.json"
			checkAuthError
			TMP="$( egrep -o "${SMARTAPPS_EXTRACT_IDFILE}" ${RAW_SOURCE}/${TYPE}/${FILE}_translate.json)"
			SA_ID="$(echo ${TMP} | egrep -o "${SMARTAPPS_EXTRACT_ID}")"
			SA_ID="${SA_ID:5}"
			SA_FILE="$(echo ${TMP} | egrep -o "${SMARTAPPS_EXTRACT_FILE}")"
			SA_FILE=${SA_FILE:7}

			echo -n "   ${SA_FILE} - "

			if [ -f "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}" -a ${FORCE} -eq 0 ]; then
				echo "File exists, skipping (use FORCE to ignore)"
			else
				# Download the actual script now
				curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d "id=${FILE}&resourceId=${SA_ID}&resourceType=script" "https://graph.api.smartthings.com/ide/${TYPE}/getCodeForResource" -o "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp"
				if grep "${LOGIN_NEEDED}" "${HEADERS}" >/dev/null ; then
					echo "ERROR: Failed to download source"
					rm /tmp/login_ok
					exit 255
				fi
				cat "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" | "${TOOL_JSONDEC}" > "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}"

				# Finally, sha1 it, so we can detect diffs.
				SHA=$(shasum "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}")
				SHA="${SHA:0:40}"
				echo "${SA_ID} ${SA_FILE} ${SHA}" > "${RAW_SOURCE}/${TYPE}/${FILE}.map"
				echo "OK"
			fi
		else
			curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" "https://graph.api.smartthings.com/ide/device/editor/${FILE}" -o "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html"
			checkAuthError
			SA_FILE="$(egrep -o '<title>([^<]+)' "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html")"
			SA_FILE="${SA_FILE##\<title\>}"
			SA_FILE="${SA_FILE// /-}.groovy"
			SA_FILE="${SA_FILE//\(/-}"
			SA_FILE="${SA_FILE//\)/-}"
			SA_FILE="$(echo "${SA_FILE}" | tr '[:upper:]' '[:lower:]')"
			SA_ID="$(egrep -o '("[^"]+" id="id")' "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html")"
			SA_ID="${SA_ID##\"}"
			SA_ID="${SA_ID%%\" id=\"id\"}"
			echo -n "   ${SA_FILE} - "
			if [ -f "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}" -a ${FORCE} -eq 0 ]; then
				echo "File exists, skipping (use FORCE to ignore)"
			else
				cat "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html" | ${TOOL_EXTRACT}  > "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}"

				# Finally, sha1 it, so we can detect diffs.
				SHA=$(shasum "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}")
				SHA="${SHA:0:40}"
				echo "${SA_ID} ${SA_FILE} ${SHA}" > "${RAW_SOURCE}/${TYPE}/${FILE}.map"
				echo "OK"
			fi
		fi

	done
}

function checkDiff() {
	for FILE in "${RAW_SOURCE}/$1/"*.map; do
		ID="$(basename "${FILE}")"
		ID="${ID%%.map}"
		INFO=( $(cat "${FILE}") ) # 0 = Resource ID, 1 = File, 2 = sha checksum (diff)
		SHA=( $(shasum "${CLEAN_SOURCE}/$1/${INFO[1]}") )

		if [ "${SELECTED}" == "" -o "${SELECTED}" == "${INFO[1]}" ]; then
			ERROR=0
			I=$((${I} + 1))
			DIFF=""
			if [ "${INFO[3]}" == "UNPUBLISHED" ]; then
				DIFF="${DIFF}U"
				U=$((${U} + 1))
			else
				DIFF="${DIFF}-"
			fi

			if [ "${SHA[0]}" != "${INFO[2]}" ]; then
				DIFF="${DIFF}C"
				C=$((${C} + 1))
			else
				DIFF="${DIFF}-"
			fi

			if [ "${DIFF}" == "--" -a $QUIET -eq 0 ]; then
				if [ $TIMESTAMP -gt 0 ]; then
					echo "Sync started $(date):"
					TIMESTAMP=0
				fi
				echo "  ${DIFF} $1/${INFO[1]}"
			fi

			if [ $UPLOAD -gt 0 -a "${DIFF:1:1}" == "C" ]; then
				echo -n "     Uploading... "
				# Build the data to post (it's massive, so temp file!)
				echo -n > /tmp/postdata "id=${ID}&location=&resource=${INFO[0]}&resourceType=script&code="
				cat "${CLEAN_SOURCE}/$1/${INFO[1]}" | ${TOOL_URLENC} >> /tmp/postdata
				curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d @/tmp/postdata "https://graph.api.smartthings.com/ide/$1/compile" > /tmp/post_result
				if grep "${LOGIN_NEEDED}" "${HEADERS}" >/dev/null ; then
					echo "ERROR: Failed to push changes, login timed out. Try again"
					rm /tmp/login_ok
					exit 255
				fi
				if grep '{"errors":\["' /tmp/post_result 2>/dev/null 1>/dev/null ; then
					echo "ERROR: Upload failed due to compilation errors..."
					cat /tmp/post_result | ${TOOL_JSONDEC} errors
					echo ""
					ERROR=1
				else
					SHA=$(shasum "${CLEAN_SOURCE}/$1/${INFO[1]}")
					SHA="${SHA:0:40}"
					echo "${INFO[0]} ${INFO[1]} ${SHA} UNPUBLISHED" > "${FILE}"
					C=$((${C} - 1))
					U=$((${C} - 1))
					DIFF="U-"
					echo "OK"
				fi
			fi
			if [ $PUBLISH -gt 0 -a "${DIFF:0:1}" == "U" ]; then
				if [ $ERROR -gt 0 ]; then
					echo "     NOT publishing since you had an error"
				else
					echo -n "     Publishing... "
					curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d "id=${ID}&scope=me" "https://graph.api.smartthings.com/ide/$1/publishAjax" > /tmp/post_result
					if grep "${LOGIN_NEEDED}" "${HEADERS}" >/dev/null ; then
						echo "ERROR: Failed to push changes, login timed out. Try again"
						rm /tmp/login_ok
						exit 255
					fi
					echo "${INFO[0]} ${INFO[1]} ${SHA}" > "${FILE}"
					echo "OK"
					U=$((${U} - 1))
				fi
			fi
		fi
	done

}

# Defaults, do not change
#
FORCE=0
MODE=diff
PUBLISH=0
UPLOAD=0
SELECTED=
QUIET=0
TIMESTAMP=0

# Parse options
#
while getopts tsSdhpulqLf: opt
do
   	case "$opt" in
   		t) TIMESTAMP=1;;
	   	s) MODE=sync;;
		S) MODE=sync ; FORCE=1;;
		p) PUBLISH=1;;
		u) UPLOAD=1;;
		f) SELECTED="$(basename "$OPTARG")";;
		q) QUIET=1;;
		l) rm /tmp/login_ok 2>/dev/null 1>/dev/null ;;
		L) MODE=logging;;
		h) usage;;
	esac
done

if [ $QUIET -eq 0 ]; then
	echo ""
	echo "SmartThings WebIDE Sync (beta)"
	echo "=============================="
	echo ""
fi

# Load user settings
#
if [ -f ~/.stsync ]; then
	source ~/.stsync
fi

eval CLEAN_SOURCE="${SOURCE}"
RAW_SOURCE="${CLEAN_SOURCE}/raw/"

# Sanity testing
#
if [ "${USERNAME}" == "" -o "${PASSWORD}" == "" ]; then
	echo "ERROR: No username and/or password. Please create a personal settings file in ~/.stsync"
	exit 255
fi
if [ "${SOURCE}" == "" ]; then
	echo "ERROR: No source directory specified in ~/.stsync"
	exit 255
fi

if [ "${SELECTED: -7}" != ".groovy" -a "${SELECTED}" != "" ]; then
	if [ $QUIET -eq 0 ]; then
		echo "ERROR: You cannot select a non-groovy file"
		exit 255
	else
		# Special case, hide errors from caller
		exit 0
	fi
fi

# Get the path of ourselves (need for symlinks)
#
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd`
popd > /dev/null

# If we haven't logged in, do so now
#
if [ ! -f /tmp/login_ok ]; then
	curl -A "${USERAGENT}" -D "${HEADERS}" -c "${COOKIES}" -X POST -d "j_username=${USERNAME}&j_password=${PASSWORD}" ${LOGIN_URL}
	if grep "${LOGIN_FAIL}" "${HEADERS}" ; then
		echo "ERROR: Login failed, check username/password"
		exit 255
	fi
	if [ $QUIET -eq 0 ]; then
		echo "Login successful and cached"
	fi
	touch /tmp/login_ok
fi

if [ "${MODE}" == "sync" ]; then
	echo "Downloading repository to ${CLEAN_SOURCE}:"
	mkdir -p "${CLEAN_SOURCE}/app"
	mkdir -p "${CLEAN_SOURCE}/device"
	mkdir -p "${RAW_SOURCE}/app"
	mkdir -p "${RAW_SOURCE}/device"
	curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" ${SMARTAPPS_URL} -o "${RAW_SOURCE}/app/smartapps.lst"
	checkAuthError
	curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" ${DEVICETYPES_URL} -o "${RAW_SOURCE}/device/devicetypes.lst"
	checkAuthError

	# Get the APP ids
	IDS="$(egrep -o "${SMARTAPPS_LINK}" "${RAW_SOURCE}/app/smartapps.lst")"
	download_repo "app" "${IDS}"
	IDS="$(egrep -o "${DEVICETYPES_LINK}" "${RAW_SOURCE}/device/devicetypes.lst")"
	download_repo "device" "${IDS}"
	if [ ! -f "${CLEAN_SOURCE}/.gitignore" ]; then
		# Create a gitignore in-case the user will use git
		echo >"${CLEAN_SOURCE}/.gitignore" "raw/"
	fi
fi

if [ "${MODE}" == "diff" ]; then
	if [ ! -d "${RAW_SOURCE}" -o ! -d "${CLEAN_SOURCE}" ]; then
		echo "ERROR: You haven't initialized a repository or the path is wrong"
		exit 255
	fi

	if [ $QUIET -eq 0 ]; then
		if [ "${SELECTED}" != "" ]; then
			echo "Checking ${CLEAN_SOURCE} for any changes to ${SELECTED}:"
		else
			echo "Checking ${CLEAN_SOURCE} for any changes:"
		fi
		echo ""
	fi
	I=0
	C=0
	U=0

	checkDiff app
	checkDiff device
	if [ $QUIET -eq 0 ]; then
		echo ""
		echo "Checked ${I} files, ${U} unpublished, ${C} changed locally"
	fi
fi

if [ "${MODE}" == "logging" ]; then
	curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" ${LOGGING_URL} -o "/tmp/get_data"
	checkAuthError
	WEBSOCKET="$(egrep -o "websocket: \'[^\']+" /tmp/get_data)"
	WEBSOCKET="${WEBSOCKET##websocket: \'}"
	CLIENT="$(egrep -o "client: \'[^\']+" /tmp/get_data)"
	CLIENT="${CLIENT##client: \'}"

	${TOOL_LOGGING} "${WEBSOCKET}client/${CLIENT}" "${CLIENT}"
fi