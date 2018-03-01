# Should be sourced.

# bhlls.sh
# Bash Helper Library for Large Scripts
# ―――――――――――――――――――――――――――――――――――――
# It provides
#   - initial checks for
#      + bash version – to avoid running on prehistoric cygwin shells;
#      + the main script – that it’s not being sourced;
#      + all required binaries – which you may add – are accessible;
#   - various helpful variables preset such as
#      + colours;
#      + MYDIR and MYNAME;
#      + CMDLINE and TMPDIR;
#      + TERM_COLS and TERM_ROWS;
#   - automated logging: log files are put into the directory named after the
#     main script, and if it’s impossible to make, it uses a tmpdir in /tmp;
#   - smart message functions, that look well in the code even if
#     the message is split across lines. info, warn, err and others.
#     infow (=info+wait) takes a message and a command. The message is
#     printed right away, and after the command completes, function
#     prints its result: either [ OK ] or [ Fail ].
#         $ infow  'Running echo…'  '/bin/bash -c "echo Hi"'
#         Running echo… [ OK ]
#     Message functions honour indentation level between themselves.
#     It’s easy to bump in and out messages with milinc, mildec and mildrop.
#     Nodoby likes to read a bedsheet of text, where it’s unclear,
#     where something starts and where does it end.
#   - selection menus that use native shell means and work without
#     typing numbers or letters. What can be easier and more fool-proof
#     than using arrows? No ncurses, no more “type 33 to select a server”.
# Author: deterenkelt
# © Lifestream LLC 2016–2017
# © deterenkelt 2017–2018
# https://github.com/deterenkelt/bhlls

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but without any warranty; without even the implied warranty
# of merchantability or fitness for a particular purpose.
# See the GNU General Public License for more details.


# Requires GNU bash 4.3 or higher.

# BHLLS doesn’t set any of set and shopt permanently, in order to
# avoid clashing with scripts’ own set and shopt calls.

 # Unset after sourcing bhlls.sh to show full xtrace output
#  including BHLLS own functions.
#
BHLLS_HIDE_FROM_XTRACE=t

 # Colours for messages.
#  If you don’t use single-letter variables, better use them for colours.
#
__d='\e[39m'    # default fg
__r='\e[31m'    # red
__g='\e[32m'    # green
__y='\e[33m'    # yellow
__s='\e[0m'     # stop
__b='\e[1m'     # bright/bold. Sorry, no blue…
__rb='\e[21m'   # reset bold/bright
__u='\e[4m'     # underlined
info_colour=$__g
warn_colour=$__y
err_colour=$__r

 # We require bash >= 4.3 for nameref.
#  It’s better to use nameref than eval, where possible.
#
[ ${BASH_VERSINFO[0]:-0} -eq 4 ] &&
[ ${BASH_VERSINFO[1]:-0} -le 2 ] ||
[ ${BASH_VERSINFO[0]:-0} -le 3 ] && {
	# We use
	echo -e "$__r*$__s Bash v4.3 or higher required." >&2
	# so it would work for both sourced and executed script
	return 3 2>/dev/null ||	exit 3
}


 # Scripts usually shouldn’t be sourced,
#  unless they’re alternating the current environment.
#  Define NO_CHECK_FOR_SOURCED_SCRIPT to skip this.
#
[ -v NO_CHECK_FOR_SOURCED_SCRIPT ] || {
	[ "${BASH_SOURCE[-1]}" != "$0" ] && {
		echo -e "$__r*$__s This script shouldn’t be sourced." >&2
		return 4
	}
}

# $0 == -bash if the script is sourced.
[ -f "$0" ] && {
	MYNAME=${0##*/}
	MYDIR=`realpath "$0"`
	MYDIR=${MYDIR%/*}
}
CMDLINE="$0 $*"
TERM_COLS=`tput cols`
TERM_LINES=`tput lines`
BHLLS_VERSION="20180301"
TMPDIR=`mktemp -d`

bhlls_on_exit() {
	[ "$(type -t on_exit)" = function ] && on_exit  # run user’s on_exit().
	rm -rf "$TMPDIR"
}
trap 'bhlls_on_exit' EXIT TERM INT QUIT KILL

bhlls_show_error() {
	local file=$1 line=$2 lineno=$3
	echo -e "$file: An error occured!\nLine $lineno: $line" >&2
	notify-send --hint int:transient:1 \
	            -t 3000 \
	            "$MYNAME" "Error: check the console." \
	    || :
	info "Log is written to
	      $LOG"
	return 0
}

 # During the debug, it sometimes needed to disable errexit (set -e)
#  temporarily. However disabling errexit (with set +e) doesn’t remove
#  the associated trap.
#
traponerr() {
	case "$1" in
		set)
			#  Note the single quotes – to prevent early expansion
			trap 'bhlls_show_error "$BASH_SOURCE" "$BASH_COMMAND" "$LINENO"' ERR
			;;
		unset)
			#  trap '' ERR will ignore the signal.
			#  trap - ERR will reset command to 'bhlls_show_error "$BASH_SOURCE…'
			trap '' ERR
			;;
	esac
	return 0
}
traponerr set


 # List of utilities the lack of which must trigger an error.
#  Feel free to extend this array in your script:
#  required_utils+=(awk bc iostat)
#
required_utils=(
	getopt
	grep
	sed
)

 # Call this function in your script after extending the array above.
#
check_required_utils() {
	local missing_utils
	for util in ${required_utils[@]}; do
		which $util &>/dev/null || { iwarn no util; missing_utils=t; }
	done
	[ -v missing_utils ] && return 1
	return 0
}

# BHLLS offers keyword-based messages, which enables
# to create localised programs.

 # List of informational messages
#
declare -A BHLLS_INFO_MESSAGES=()

 # List of warning messages
#
declare -A BHLLS_WARNING_MESSAGES=(
	[no such msg]='Internal: No such message: ‘$failed_message’.'
	[no util]='‘$util’ is required but wasn’t found on this system.'
)

 # List of error messages
#  Keys are used as parameters to err() and values are printed via msg().
#  Keys may contain spaces – e.g. ‘my key’. Passing them to err()
#  doesn’t require quoting and the number of spaces is not important.
#  You can add your messages just by adding elements to this array,
#  and perform localisation just by redefining it after sourcing this file!
#
declare -A BHLLS_ERROR_MESSAGES=(
	[just quit]='Quitting.'
	[old utillinux]='This script requires util-linux-2.20 or higher.'
	[missing deps]='Dependencies are not satisfied.'
)

 # BHLLS requires util-linux >= 2.20
#
read -d $"\n" major minor \
	< <(getopt -V | sed -rn 's/^[^0-9]+([0-9]+)\.?([0-9]+)?.*/\1\n\2/p') ||:
[[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]] && [ $major -ge 2 ] \
	&& ( [ $major -gt 2 ] || [ $major -eq 2 -a $minor -ge 20 ] ) \
	|| err old_utillinux
unset major minor

 # To turn off xtrace (set -x) output during the execution
#  of BHLLS own functions.
#
xtrace_off() {
	[[ -v BHLLS_HIDE_FROM_XTRACE && "$-" =~ ^.*x.*$ ]] && {
		set +x
		declare -g BHLLS_BRING_BACK_XTRACE=t
	}
	return 0
}
xtrace_on() {
	[ -v BHLLS_BRING_BACK_XTRACE ] && {
		unset BHLLS_BRING_BACK_XTRACE
		set -x
	}
	return 0
}


 # Message Indentation Level.
#  Each time you go deeper one level, call milinc – and the messages
#  will be indented one level more. mildec decreases one level.
#  See also: milset, mildrop.
#
MI_LEVEL=0  # Debug indentation level. Default is 0.
MI_SPACENUM=4  # Number of spaces to use per indentation level
MI_CHARS=''  # Accumulates spaces for one portion of indentation
for ((i=0; i<MI_SPACENUM; i++)); do MI_CHARS+=' '; done

mi_assemble() {
	local z
	MI=
	for ((z=0; z<MI_LEVEL; z++)); do MI+=$MI_CHARS; done
	# Without this, multiline messages that occur on MI_LEVEL=0,
	# when $MI is empty, won’t be indented properly. ‘* ’, remember?
	[ "$MI" ] || MI='  '
	return 0
}
mi_assemble

 # Increments the indentation level.
#    [$1] — number of times to increment $MI_LEVEL. The default is to increment by 1.
#
milinc() {
	xtrace_off
	local count=$1 z mi_as_result
	count=${count:-1}
	for ((z=0; z<count; z++)); do ((MI_LEVEL++, 1)); done
	mi_assemble; mi_as_result=$?
	xtrace_on
	return $mi_as_result
}

 # Decrements the indentation level.
#    [$1] — number of times to decrement $MI_LEVEL. The default is to decrement by 1.
#
mildec() {
	xtrace_off
	local count=$1 z mi_as_result
	count=${count:-1}
	if [ $MI_LEVEL -eq 0 ]; then
		warn "No need to decrease indentation, it’s on the minimum."
	else
		for ((z=0; z<count; z++)); do ((MI_LEVEL--, 1)); done
		mi_assemble; mi_as_result=$?
	fi
	xtrace_on
	return $mi_as_result
}

 # Sets the indentation level to a specified number.
#    $1 – desired indentation level, 0..9999.
#
milset () {
	xtrace_off
	local _mi_level=$1 mi_as_result
	[[ "$_mi_level" =~ ^[0-9]{1,4}$ ]] || {
		warn "Indentation level should be an integer between 0 and 9999."
		return 0
	}
	MI_LEVEL=$_mi_level
	mi_assemble; mi_as_result=$?
	xtrace_on
	return $mi_as_result
}

 # Removes any indentation.
#
mildrop() {
	xtrace_off
	MI_LEVEL=0
	mi_assemble; local mi_as_result=$?
	xtrace_on
	return $mi_as_result
}

 # Shows an info message.
#  Features asterisk, automatic indentation with mil*, keeps lines
#
#  $1 — a message or a key of an item in the corresponding array containing
#       the messages. Depends on whether $MSG_USE_ARRAYS is set (see above).
#
info() {
	xtrace_off
	msg "$@"; local msg_res=$?
	xtrace_on
	return $msg_res
}

 # Same as info, but omits the ending newline, like “echo -n” does.
#  This allows to print whatever with just simple “echo” later.
#
infon() {
	xtrace_off
	nonl=t msg "$@"; local msg_res=$?
	xtrace_on
	return $msg_res
}

 # Shows an info message and waits for the given command to finish,
#  to print its result, and if it’s not zero, print the output
#  of that command.
#
#  $1 – a message. Something like ‘Starting up servicename… ’
#  $2 – a command.
#  $3 – any string to force the output even if the result is [OK].
#       Handy for faulty programs that return 0 even on error.
#
infow() {
	xtrace_off
	local message=$1 command=$2 force_output="$3" outp result
	msg "$message"
	outp=$( bash -c "$command" 2>&1 )
	result=$?
	[ $result -eq 0 ] \
		&& printf "${__b}%s${__g}%s${__s}${__b}%s${__s}\n"  ' [ ' OK ' ]' \
		|| printf "${__b}%s${__r}%s${__s}${__b}%s${__s}\n"  ' [ ' Fail ' ]'
	[ $result -ne 0 -o "$force_output" ] && {
		milinc
		info "Here is the output of ‘$command’:"
		plainmsg "$outp"
		mildec
	}
	xtrace_on
	return 0
}

#  Like info, but the output goes to stderr. Dimmed yellow asterisk.
warn() {
	xtrace_off
	msg "$@"
	xtrace_on
}

#  Shows message and then calls exit. Red asterisk.
#  If MSG_USE_ARRAYS is not set, the default exit code is 5.
err() {
	xtrace_off
	msg "$@"
	xtrace_on
}

#  Same as err(), but prints the whole line in red.
errw() {
	xtrace_off
	msg "$@"
	xtrace_on
}

#  For internal BHLLS warnings and errors.
iwarn() {
	xtrace_off
	msg "$@"
	xtrace_on
}
ierr() {
	xtrace_off
	msg "$@"
	xtrace_on
}

 # For internal use in alias functions, such as infow(), where we cannot use
#  msg() as is, because FUNCNAME[1] will be set to the name of that alias
#  function. Hence, to avoid additions and get a plain msg(), we must call it
#  from another function, for which no additions are specified in msg().
#
plainmsg() {
	xtrace_off
	msg "$@"
	xtrace_on
}


 # Shows an info, a warning or an error message.
#  TAKES:
#    $1 — a text message or, if MSG_USE_ARRAYS is set, a key from
#         - INFO_MESSAGES, if called as info*();
#         - WARNING_MESSAGES,  if called as warn*();
#         - ERROR_MESSAGES, if called as err*().
#         That key may contain spaces, and the number of spaces between words
#         in the key is not important, i.e.
#           $ warn "no needed file found"
#           $ warn  no needed file found
#         and
#           $ warn  no   needed  file     found
#         will use the same item in the WARNING_MESSAGES array.
#  RETURNS:
#    If called as an err* function, then quits the script with exit/return code 5
#    or 5–∞, if ERROR_CODES is set.
#    Returns with zero otherwise.
#
msg() {
	local msgtype c cs=$__s nonl asterisk='  ' message redir code=5 internal \
	      key msg_key_exists
	case "${FUNCNAME[1]}" in
		*info*)  # all *info*
			msgtype=info
			local -n  msg_array=INFO_MESSAGES
			local -n  c=info_colour
			;;&
		info|infon)
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+INFO: }"
			;;
		infow)
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+RUNNING: }"
			nonl=t
			;;
		*warn*)
			msgtype=warn redir='>&2'
			local -n  msg_array=WARNING_MESSAGES
			local -n  c=warn_colour
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+WARNING: }"
		    ;;&
		*err*)
			msgtype=err redir='>&2'
			local -n  msg_array=ERROR_MESSAGES
			local -n  c=err_colour
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+ERROR: }"
			;;&
		errw)
			asterisk='  '
			unset cs  # print whole line in red, no asterisk.
			;;
		iwarn|ierr|iinfo)
			internal=t
			;;&
		iwarn)
			# For internal messages.
			local -n  msg_array=BHLLS_WARNING_MESSAGES
			;;
		ierr)
			# For internal messages.
			local -n  msg_array=BHLLS_ERROR_MESSAGES
			;;
	esac
	[ -v nonl ] && nonl='-n'
	[ -v QUIET ] && redir='>/dev/null'
	[ -v MSG_USE_ARRAYS -o -v internal ] && {
		# What was passed to us is not a message, but a key
		# of a corresponding array.
		#
		# We cannot do
		#     eval [ -v \"$prefix$msg_array[$message]\" ]
		# here, becasue it will only work when $message item does exist,
		# and if it doesn’t, bash will throw an error about wrong syntax.
		# Actually, without nameref it would be hell to do this cycle.
		for key in "${!msg_array[@]}"; do
			[ "$key" = "$*" ] && msg_key_exists=t
		done
		if [ -v msg_key_exists ]; then
			message="${msg_array[$@]}"
		else
			failed_message=$message iwarn no such msg
			# Quit, if the user has called err*() – he most probably
			# intended to quit here.
			[ "$msgtype" = err ] && ierr just quit || return $code
		fi
	}|| message="$*"
	# Removing blank space before message lines.
	# This allows strings to be split across lines and at the same time
	# be well-indented with tabs and/or spaces – indentation will be cut
	# from the output.
	message=`sed -r 's/^\s*//; s/\n\t/\n/g' <<<"$message"`
	# Both fold and fmt use smaller width,
	# if they deal with non-Latin characters.
	eval "echo -e $nonl \"$c$asterisk$cs$message$__s\" \
	          | tee -a $LOG \
	          | fold  -w $((TERM_COLS - MI_LEVEL*MI_SPACENUM -2)) -s \
	          | sed -r \"1s/^/${MI#  }/; 1!s/^/$MI/g\" $redir"

	[ "$msgtype" = err ] && {
		# If this is an error message, we must also quit
		# with a certain exit/return code.
		[ -v MSG_USE_ARRAYS -a ${#ERROR_CODES[@]} -ne 0 ] \
			&& code=${ERROR_CODES[$*]}
		# BHLLS can be used in both sourced and standalone scripts
		# code=5 by default.
		[ -v BHLLS_USE_RETURN ] && { return $code; :; } || exit $code
	}
	return 0
}

 # Dumps values of variables to stdout and to the log
#    $1..n – variable names
#
dumpvar() {
	local var
	for var in "$@"; do
		msg "`declare -p $var`"
	done
}

 # Shows a menu, where a selection is made with only arrows on keyboard.
#
#  TAKES
#      $1 – prompt
#      $2..n – options to choose from. The first one become the default.
#                If the default option is not the first one, it should be
#                given _with underscores_.
#              If the user must set values to options, vertical type of menu
#                allows to show values aside of the option names.
#                To pass a value for an option, add it after the option name
#                and separate from it with “---”.
#                If the option name has underscores marking it as default,
#                they surround only the option name, as usual.
#  SETS
#      CHOSEN – selected option.
#
carousel() { menu "$@"; }
menu() {
	xtrace_off
	local mode choice_is_confirmed bivariant prompt options=() optvals=() \
	      option rest arrow_up=$'\e[A' arrow_right=$'\e[C' \
	      arrow_down=$'\e[B' arrow_left=$'\e[D' clear_line=$'\r\e[K' \
	      left=t right=t
	# For an X terminal or TTY with jfbterm
	local cool_graphic=( '‘' '’' '…'   '–'   '│' '─' '∨' '∧' '◆' )
	# For a regular TTY
	local poor_graphic=( "'" "'" '...' '-'   '|' '-' 'v' '^' '+' )
	graphic=("${cool_graphic[@]}")
	local oq=${graphic[0]}  # opening quote
	local cq=${graphic[1]}  # closing quote
	local el=${graphic[2]}  # ellipsis
	local da=${graphic[3]}  # en dash
	local vb=${graphic[4]}  # vertical bar
	local hb=${graphic[5]}  # horizontal bar
	local ad=${graphic[6]}  # arrow down
	local au=${graphic[7]}  # arrow up
	local di=${graphic[8]}  # diamond
	chosen_idx=0
	[ "$OVERRIDE_DEFAULT" ] && chosen_idx="$OVERRIDE_DEFAULT"
	[ "${FUNCNAME[1]}" = carousel ] && mode=carousel
	prompt="$1" && shift
	while option="$1"; [ "$option" ]; do
		optvals+=("${option#*---}")
		option=${option%---*}
		[ "${option/_*_}" ] || {
			# Option specified _like this_ is to be selected by default.
			[ "$OVERRIDE_DEFAULT" ] || chosen_idx=${#options[@]}
			# Erasing underscores.
			option=${option#_} option=${option%_}
		}
		options+=("${option}")
		shift
	done
	[ ${#options[@]} -eq 2 ] && {
		mode=bivariant
		[ $chosen_idx -eq 0 ] && right= || left=
	}
	[ -v NON_INTERACTIVE ] && {
		CHOSEN=${options[chosen_idx]}
		return
	}
	until [ -v choice_is_confirmed ]; do
		clear
		case "$mode" in
			bivariant)
				echo -en "$prompt ${left:+$__g}${options[0]}${left:+$__s <} ${right:+> $__g}${options[1]}${right:+$__s} "
				;;
			carousel)
				[ $chosen_idx -eq 0 ] && left=
				[ $chosen_idx -eq $(( ${#options[@]} -1 )) ] && right=
				echo -en "$prompt ${left:+$__g}<|$s ${options[chosen_idx]} $__s${right:+$__g}|>$__s "
				;;
			*)
				echo -e "\n\n/${hb}${hb}${hb} $prompt ${hb}${hb}${hb}${hb}${hb}${hb}"
				for ((i=0; i<${#options[@]}; i++)); do
					[ $i -eq $chosen_idx ] && pre="$__g${di}$__s" || {
						[ $i -eq 0 ] && pre="$__g${au}$__s" || {
							[ $i -eq $(( ${#options[@]} -1 )) ] && pre="$__g${ad}$__s" || pre="${vb}"
						}
					}
					eval echo -e \"$pre ${options[i]}\"\$\{${optvals[i]}:+:\ \$${optvals[i]}\}
				done
				echo -en "${__g}Up$s/${__g}Dn$__s: select parameter, ${__g}Enter$__s: confirm. "
				;;
			esac
		read -sn1
		[ "$REPLY" = $'\e' ] && read -sn2 rest && REPLY+="$rest"
		if [ "$REPLY" ]; then
			case "$REPLY" in
				"$arrow_left"|"$arrow_down"|',')
					case "$mode" in
						bivariant) left=t right= chosen_idx=0;;
						carousel)
							[ $chosen_idx -eq 0 ] && left= || {
								((chosen_index--, 1))
								right=t
							}
							;;
						*)
							[ $chosen_idx -eq $(( ${#options[@]} -1)) ] \
								|| ((chosen_idx++, 1))
							;;
					esac
					;;
				"$arrow_right"|"$arrow_up"|'.')
					case "$mode" in
						bivariant) left= right=t chosen_idx=1;;
						carousel)
							if [ $chosen_idx -eq $(( ${#options[@]}-1)) ]; then
								right=
							else
								((chosen_index++, 1))
								left=t
							fi
							;;
						*)
							[ $chosen_idx -eq 0 ] || ((chosen_idx--, 1))
							;;
					esac
					;;
			esac
			[[ "$mode" =~ ^(bivariant|carousel)$ ]] && echo -en "$clear_line"
		else
			echo
			choice_is_confirmed=t
		fi
	done
	CHOSEN=${options[chosen_idx]}
	xtrace_on
	return 0
}


 # Logging
#  Set BHLLS_LOGGING_ON to turn on logging.
#  By default it is unset and logs go to /dev/null.
#
LOG=/dev/null
[ -v BHLLS_LOGGING_ON ] && {
	LOGDIR="$MYDIR/${MYNAME%.sh}_logs"
	[ -d "$LOGDIR" -a -w "$LOGDIR" ] || {
		mkdir "$LOGDIR" &>/dev/null || {
			LOGDIR="`mktemp -d`/logs"
			mkdir "$LOGDIR"
		}
	}
	LOG="$LOGDIR/${MYNAME}_`date +%Y-%m-%d_%H:%M:%S`.log"
	# Removing old logs, keeping maximum of $LOG_KEEP_COUNT of recent logs.
	cd "$LOGDIR"
	[[ "$-" =~ ^.*f.*$ ]] && {
		set +f
		bhlls_return_noglob=t
	}
	ls -r * | tail -n+$((${BHLLS_LOG_MAX_COUNT:=5}+1)) \
	        | xargs rm -v &>/dev/null || :
	[ -v bhlls_return_noglob ] && {
		set -f
		unset bhlls_return_noglob
	}
	cd - >/dev/null
	echo "Log started at `date`." >"$LOG"
	echo "Command line: $CMDLINE" >>"$LOG"
	exec |& tee -a "$LOG"
}

show_path_to_log() {
	info "Log is written to
	      $LOG"
}

return 0