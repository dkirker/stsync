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
SERVER="graph.api.smartthings.com"

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

function webide_login() {
	if [ ! -f /tmp/login_ok ]; then
		curl -s -A "${USERAGENT}" -D "${HEADERS}" -c "${COOKIES}" -X POST -d "j_username=${USERNAME}&j_password=${PASSWORD}" ${LOGIN_URL}
		if grep "${LOGIN_FAIL}" "${HEADERS}" ; then
			log_err "Login failed, check username/password"
			exit 255
		fi
		if [ $QUIET -eq 0 ]; then
			log_info "Login successful and cached"
		fi
		touch /tmp/login_ok
	fi
}

function webide_needLogin() {
	if grep "${LOGIN_NEEDED}" "${HEADERS}" >/dev/null ; then
		log_warn "Server refusing access, login has probably expired."
		rm /tmp/login_ok
		return 0
	fi
	return 1
}

function checkAuthError() {
	if webide_checkLogin; then
		exit 255
	fi
}

function needQuotes() {
	case "$@" in
	     *\ * )
	           return 0
	          ;;
	     *\&* )
	           return 0
	          ;;
	       *)
	           return 1
	           ;;
	esac
}

# Executes the provided arguments as a command
# and checks if it was successful or not, will
# automatically retry after a login.
#
function webide_execWithLogin() {
	CMDLINE=
	for X in "$@"; do
		if needQuotes $X; then
			CMDLINE="${CMDLINE} \"${X}\""
		else
			CMDLINE="${CMDLINE} ${X}"
		fi
	done
	eval $CMDLINE
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		log_err "$CMDLINE failed with error code $RESULT"
		exit 255
	fi
	if webide_needLogin; then
		# Login and try again
		webide_login
		log_info "Retrying..."
		eval $CMDLINE
		RESULT=$?
		if [ $RESULT -ne 0 ]; then
			log_err "$CMDLINE failed with error code $RESULT"
			exit 255
		fi
		if webide_needLogin; then
			log_err "Unable to login"
			exit 255
		fi
	fi
}

# Useful functions
function rawurlencode() {
	local string="${1}"
	local strlen=${#string}
	local encoded=""

	for (( pos=0 ; pos<strlen ; pos++ )); do
		c=${string:$pos:1}
		case "$c" in
		[-_.~a-zA-Z0-9] ) o="${c}" ;;
		* )               printf -v o '%%%02x' "'$c"
	esac
	encoded+="${o}"
	done
	echo "${encoded}"
}

function usage() {
	echo ""
	echo "SmartThings WebIDE Sync (beta) - henric@smartthings.com"
	echo "¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨"
	echo "Simplifying the use of an external editor with the SmartThings development"
	echo "environment."
	echo ""
	echo "  -d        = DISABLE preprocessor directives (see README.md)"
	echo "  -f <file> = Make -u & -p apply to <file> ONLY"
	echo "  -F        = Force action, regardless of change"
	echo "  -h        = This help"
	echo "  -l        = Always login"
	echo "  -L        = Live Logging (experimental)"
	echo "  -o        = Allow overwrite of include files (normally only new files are created)"
	echo "  -P <file> = Load a different profile other than ~/.stsync"
	echo "  -p        = Publish changes (can be combined with -u)"
	echo "  -q        = Quiet (less output)"
	echo "  -s        = Start a new repository (essentially downloading your ST apps and device types)"
	echo "  -S        = Same as -s but WILL overwrite any existing files. Use with care, you'll lose any local changes you've made"
	echo "  -u        = Upload changes"
	#echo "  -j        = Journaling mode (see README.md)"
	#echo "  -a <file> = Add file to repository"
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
			COUNTER=0
			CONTENT=""

			webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -o "${RAW_SOURCE}/${TYPE}/${FILE}_translate.json" "https://${SERVER}/ide/${TYPE}/getResourceList?id=${FILE}"
			ITEMS=($( cat ${RAW_SOURCE}/${TYPE}/${FILE}_translate.json | ${TOOL_PATHS}))
			SA_ID=
			SA_FILE=
			SA_TYPE=
			SA_CONTENT=
			SA_HOME=
			# First, locate the groovy file and obtain the path we need
			for X in "${ITEMS[@]}"; do
				if [ "${X##*\.}" == "groovy" ]; then
					SA_HOME="${X%.groovy}.src"
				fi
			done
			if [ "" == "${SA_HOME}" ]; then
				log_warn "$FILE has no groovy code, skipped!"
			else
				for X in "${ITEMS[@]}"; do
					if [ "" == "${SA_ID}" ]; then
						SA_ID="${X}"
					elif [ "" == "${SA_CONTENT}" ]; then
						SA_CONTENT="${X}"
					elif [ "" == "${SA_TYPE}" ]; then
						SA_TYPE="${X}"
					elif [ "" == "${SA_FILE}" ]; then
						SA_PLAIN_FILE="${X}"
						SA_FILE="${SA_HOME}/${X}"
						printf "   %-60.60s - " "${SA_FILE}"

						# Make sure the directory structure is there
						mkdir -p "$(dirname "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}")"

						if [ -f "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}" -a ${FORCE} -eq 0 ]; then
							echo "Skipped"
						else
							# Download the actual script now... unless it's an image (wtf)
							if [ "${SA_CONTENT%/*}" == "image" ]; then
								webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d "id=${FILE}&fileName=$(basename "${SA_FILE}")&filePath=$(dirname "${SA_PLAIN_FILE}")" -o /tmp/getresult "${SMARTAPP_CDN}"
								URL="$(cat /tmp/getresult | ${TOOL_JSONDEC} imageUrl)"
								webide_execWithLogin curl -s -o "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" "${URL}"
								touch "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" # This is needed since files may be zero length
								cp "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}"
							else
								webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d "id=${FILE}&resourceId=${SA_ID}&resourceType=${SA_TYPE}" -o "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" "https://${SERVER}/ide/${TYPE}/getCodeForResource"
								touch "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" # This is needed since files may be zero length
								cat "${RAW_SOURCE}/${TYPE}/${SA_ID}.tmp" | "${TOOL_PREPROCESS}" "${CLEAN_SOURCE}/$TYPE/${SA_HOME}" ${INCLUDE_OVERWRITE} > "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}"
							fi
							# Finally, sha1 it, so we can detect diffs.
							SHA=$(shasum "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}")
							SHA="${SHA:0:40}"
							echo "${FILE} ${SA_ID} ${SA_FILE} ${SA_CONTENT} ${SA_TYPE} ${SHA}" > "${RAW_SOURCE}/${TYPE}/${SHA}.map"
							echo "OK (${SA_CONTENT})"
						fi
						SA_TYPE=
						SA_CONTENT=
						SA_ID=
						SA_FILE=
					fi
				done
			fi
		else
			webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -o "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html" "https://${SERVER}/ide/device/editor/${FILE}"

			SA_FILE="$(egrep -o '<title>([^<]+)' "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html")"
			SA_FILE="${SA_FILE##\<title\>}"
			SA_FILE="${SA_FILE// /-}.groovy"
			SA_FILE="${SA_FILE//\(/-}"
			SA_FILE="${SA_FILE//\)/-}"
			SA_FILE="$(echo "${SA_FILE}" | tr '[:upper:]' '[:lower:]')"
			SA_ID="$(egrep -o '("[^"]+" id="id")' "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html")"
			SA_ID="${SA_ID##\"}"
			SA_ID="${SA_ID%%\" id=\"id\"}"
			printf "   %-60.60s - " "${SA_FILE}"
			if [ -f "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}" -a ${FORCE} -eq 0 ]; then
				echo "Skipped"
			else
				cat "${RAW_SOURCE}/${TYPE}/${FILE}_translate.html" | ${TOOL_EXTRACT}  | "${TOOL_PREPROCESS}" "${CLEAN_SOURCE}/$TYPE" ${INCLUDE_OVERWRITE} > "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}"

				# Finally, sha1 it, so we can detect diffs.
				SHA=$(shasum "${CLEAN_SOURCE}/${TYPE}/${SA_FILE}")
				SHA="${SHA:0:40}"
				echo "${FILE} ${SA_ID} ${SA_FILE} X X ${SHA}" > "${RAW_SOURCE}/${TYPE}/${FILE}.map"
				echo "OK (text/plain)"
			fi
		fi
	done
}

function checkDiff() {
	for FILE in "${RAW_SOURCE}/$1/"*.map; do
		ID="$(basename "${FILE}")"
		ID="${ID%%.map}"
		INFO=( $(cat "${FILE}") ) # 0 = Project ID, 1 = Resource ID, 2 = File, 3 = Content, 4 = Type, 5 = sha checksum (diff), 6 = UNPUBLISHED
		SHA=( $(shasum "${CLEAN_SOURCE}/$1/${INFO[2]}") )

		if [ "${SELECTED}" == "" -o "${SELECTED}" == "$1/${INFO[2]}" ]; then
			ERROR=0
			I=$((${I} + 1))
			DIFF=""
			if [ "${INFO[6]}" == "UNPUBLISHED" ]; then
				DIFF="${DIFF}U"
				U=$((${U} + 1))
			else
				DIFF="${DIFF}-"
			fi

			if [ "${SHA[0]}" != "${INFO[5]}" ]; then
				DIFF="${DIFF}C"
				C=$((${C} + 1))
			else
				DIFF="${DIFF}-"
			fi

			if [ $FORCE_ACTION -gt 0 ]; then
				DIFF="UC"
			fi

			if [ "${DIFF}" != "--" -o $QUIET -eq 0 ]; then
				if [ $TIMESTAMP -gt 0 ]; then
					echo "Sync started $(date):"
					TIMESTAMP=0
				fi

				if [ $FORCE_ACTION -gt 0 ]; then
					echo "  UC $1/${INFO[2]} (forced)"
				else
					echo "  ${DIFF} $1/${INFO[2]}"
				fi
			fi

			if [ $UPLOAD -gt 0 -a "${DIFF:1:1}" == "C" ]; then
				# Build the data to post (it's massive, so temp file!)
				echo -n > /tmp/postdata "id=${INFO[0]}&location=&resource=${INFO[1]}&resourceType=${INFO[4]}&code="
				if [ $INCLUDES -gt 0 ]; then
					echo -n "     Preprocessing & Uploading... "
					cat "${CLEAN_SOURCE}/$1/${INFO[2]}" | ${TOOL_PREPROCESS} "${CLEAN_SOURCE}/$1/$(dirname "${INFO[2]}")/" | ${TOOL_URLENC} >> /tmp/postdata
				else
					echo -n "     Uploading... "
					cat "${CLEAN_SOURCE}/$1/${INFO[2]}" | ${TOOL_URLENC} >> /tmp/postdata
				fi
				webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d @/tmp/postdata -o /tmp/post_result "https://${SERVER}/ide/$1/compile"

				if grep '{"errors":\["' /tmp/post_result 2>/dev/null 1>/dev/null ; then
					echo -e "ERROR!\n"
					echo -n "$(basename "${INFO[2]}"):"
					# Do not change the following 3 lines, they have to be this way to get \n into the feed.
					cat /tmp/post_result | ${TOOL_JSONDEC} errors | sed -E 's/script[0-9]+\.{0,1}//g' | sed -nE 's/(.*) @ line ([0-9]+)$/\2: \1/p' | sed -E 's/: /:\
    /g'
					echo ""
					echo '>>>Did not upload or publish the file<<<'
					echo ""
					ERROR=1
				else
					SHA=$(shasum "${CLEAN_SOURCE}/$1/${INFO[2]}")
					SHA="${SHA:0:40}"
					echo "${INFO[0]} ${INFO[1]} ${INFO[2]} ${INFO[3]} ${INFO[4]} ${SHA} UNPUBLISHED" > "${FILE}"
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
					webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -X POST -d "id=${INFO[0]}&scope=me" -o /tmp/post_result "https://${SERVER}/ide/$1/publishAjax"
					echo "${INFO[0]} ${INFO[1]} ${INFO[2]} ${INFO[3]} ${INFO[4]} ${SHA}" > "${FILE}"
					echo "OK"
					U=$((${U} - 1))
				fi
			fi

			if [ "${SELECTED}" != "" ]; then
				return
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
INCLUDES=1
INCLUDE_OVERWRITE=0
FORCE_ACTION=0
PROFILE="~/.stsync"
PROFILECHG=0

# Parse options
#
while getopts FtsSdhpulqLof:P: opt
do
   	case "$opt" in
		d) INCLUDES=0;;
		f) SELECTED=$OPTARG;;
		F) FORCE_ACTION=1;;
		h) usage;;
		l) rm /tmp/login_ok 2>/dev/null 1>/dev/null ;;
		L) MODE=logging;;
		o) INCLUDE_OVERWRITE=0;;
   		P) PROFILE=$OPTARG;PROFILECHG=1;;
		p) PUBLISH=1;;
		q) QUIET=1;;
	   	s) MODE=sync;;
		S) MODE=sync ; FORCE=1;;
   		t) TIMESTAMP=1;;
		u) UPLOAD=1;;
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

USERAGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/43.0.2357.134 Safari/537.36"
HEADERS=/tmp/headers.txt
COOKIES=/tmp/cookies.txt

LOGIN_URL="https://${SERVER}/j_spring_security_check"
LOGIN_FAIL="https://${SERVER}/login/authfail?"
LOGIN_NEEDED="https://${SERVER}/login/auth"

SMARTAPPS_URL="https://${SERVER}/ide/apps"
DEVICETYPES_URL="https://${SERVER}/ide/devices"
SMARTAPPS_LINK="/ide/app/editor/[^\"]+"
DEVICETYPES_LINK="/ide/device/editor/[^\"]+"

SMARTAPPS_TRANSLATE="https://${SERVER}/ide/app/getResourceList?id="
SMARTAPPS_EXTRACT_IDFILE="(id\":\"[^\"]+)\",\"text\":\"[^\"]+"
SMARTAPPS_EXTRACT_ID="(id\":\"[^\"]+)"
SMARTAPPS_EXTRACT_FILE="(text\":\"[^\"]+)"
SMARTAPPS_DOWNLOAD="https://${SERVER}/ide/app/getCodeForResource"

SMARTAPPS_COMPILE="https://${SERVER}/ide/app/compile"
SMARTAPPS_PUBLISH="https://${SERVER}/ide/app/publishAjax"

SMARTAPP_CDN="https://${SERVER}/ide/app/cdnImageURL"

LOGGING_URL="https://${SERVER}/ide/logs"

TOOL_JSONDEC="${SCRIPTPATH}/tools/json_decode.pl"
TOOL_JSONENC="${SCRIPTPATH}/tools/json_encode.pl"
TOOL_URLENC="${SCRIPTPATH}/tools/url_encode.pl"
TOOL_EXTRACT="${SCRIPTPATH}/tools/extract_device.pl"
TOOL_LOGGING="${SCRIPTPATH}/tools/livelogging.pl"
TOOL_PREPROCESS="${SCRIPTPATH}/tools/preprocessor.pl"
TOOL_PATHS="${SCRIPTPATH}/tools/json_paths.pl"



log ""
log "SmartThings WebIDE Sync (beta)"
log "¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨"
log ""

if [ "${SERVER}" != "graph.api.smartthings.com" ]; then
	log_info "Note! Using ${SERVER} instead of regular end-point"
	log ""
fi

eval CLEAN_SOURCE="${SOURCE}"
RAW_SOURCE="${CLEAN_SOURCE}/.raw/"

# Sanity testing
#
if [ "${USERNAME}" == "" -o "${PASSWORD}" == "" ]; then
	log_err "No username and/or password. Please create a personal settings file in ~/.stsync"
	exit 255
fi

# Due to the fact that we're sending passwords and usernames in URLs and whatnot
# we need to make sure it's compatible.
USERNAME="$( rawurlencode "${USERNAME}" )"
PASSWORD="$( rawurlencode "${PASSWORD}" )"

if [ "${SOURCE}" == "" ]; then
	log_err "No source directory specified in ~/.stsync"
	exit 255
fi

# Clean up the filename if -f is used
if [ "${SELECTED}" != "" ]; then
	SELECTED="${SELECTED#${CLEAN_SOURCE}}"
fi

# Get the path of ourselves (need for symlinks)
#
pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd`
popd > /dev/null

# If we haven't logged in, do so now
#
webide_login

if [ "${MODE}" == "sync" ]; then
	log "Downloading repository to ${CLEAN_SOURCE}:"
	mkdir -p "${CLEAN_SOURCE}/app"
	mkdir -p "${CLEAN_SOURCE}/device"
	mkdir -p "${RAW_SOURCE}/app"
	mkdir -p "${RAW_SOURCE}/device"
	log "(this initial download will sometimes take up to a minute or two)"
	webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -o "${RAW_SOURCE}/app/smartapps.lst" "${SMARTAPPS_URL}"
	webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -o "${RAW_SOURCE}/device/devicetypes.lst" "${DEVICETYPES_URL}"
	log ""
	# Get the APP ids
	IDS="$(egrep -o "${SMARTAPPS_LINK}" "${RAW_SOURCE}/app/smartapps.lst")"
	log "Downloading SmartApps:"
	download_repo "app" "${IDS}"
	IDS="$(egrep -o "${DEVICETYPES_LINK}" "${RAW_SOURCE}/device/devicetypes.lst")"
	log ""
	log "Downloading Device Types:"
	download_repo "device" "${IDS}"
	if [ ! -f "${CLEAN_SOURCE}/.gitignore" ]; then
		# Create a gitignore in-case the user will use git
		echo >"${CLEAN_SOURCE}/.gitignore" ".raw/"
	fi
	log ""
	log "Finished! Your projects can be found at ${CLEAN_SOURCE}"
	log ""
fi

if [ "${MODE}" == "diff" ]; then
	if [ ! -d "${RAW_SOURCE}" -o ! -d "${CLEAN_SOURCE}" ]; then
		log_err "You haven't initialized a repository or the path is wrong"
		exit 255
	fi

	if [ $QUIET -eq 0 ]; then
		if [ "${SELECTED}" != "" ]; then
			log "Checking ${CLEAN_SOURCE} for any changes to ${SELECTED}:"
		else
			log "Checking ${CLEAN_SOURCE} for any changes:"
		fi
		log ""
	fi
	I=0
	C=0
	U=0

	checkDiff app
	checkDiff device
	if [ $QUIET -eq 0 ]; then
		if [ $U -lt 0 ]; then U=0 ; fi
		if [ $C -lt 0 ]; then C=0 ; fi

		log ""
		log "Checked ${I} files, ${U} unpublished, ${C} changed locally"
	fi
fi

if [ "${MODE}" == "logging" ]; then
	webide_execWithLogin curl -s -A "${USERAGENT}" -D "${HEADERS}" -b "${COOKIES}" -o "/tmp/get_data" ${LOGGING_URL}
	WEBSOCKET="$(egrep -o "websocket: \'[^\']+" /tmp/get_data)"
	WEBSOCKET="${WEBSOCKET##websocket: \'}"
	CLIENT="$(egrep -o "client: \'[^\']+" /tmp/get_data)"
	CLIENT="${CLIENT##client: \'}"

	${TOOL_LOGGING} "${WEBSOCKET}client/${CLIENT}" "${CLIENT}"
fi
