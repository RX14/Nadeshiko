#! /usr/bin/env bash

#  nadeshiko-mpv.sh
#  Wrapper for Nadeshiko to provide IPC with mpv.
#  deterenkelt © 2018
#
#  For licence see nadeshiko.sh

set -feEuT
shopt -s extglob
. "$(dirname "$(realpath "$0")")/lib/bahelite/bahelite.sh"
prepare_cachedir 'nadeshiko'
start_log
set_libdir 'nadeshiko'
. "$LIBDIR/mpv_ipc.sh"
. "$LIBDIR/gather_file_info.sh"
. "$LIBDIR/xml_and_python_functions.sh"
set_modulesdir 'nadeshiko'
set +f
for module in "$MODULESDIR"/nadeshiko-mpv_*.sh ; do
	. "$module" || err "Couldn’t source module $module."
done
set -f
set_exampleconfdir 'nadeshiko'
prepare_confdir 'nadeshiko'

declare -r version="2.3.1"
declare -r rcfile_minver='2.3'
RCFILE_BOOLEAN_VARS=(
	show_preview
	show_encoded_file
	predictor
)
#  Defining it here, so that the definition in RC would be shorter
#  and didn’t confuse users with “declare -gA …”.
declare -A mpv_sockets
declare -A nadeshiko_presets
declare -r datadir="$CACHEDIR/nadeshiko-mpv_data"
#  Old, this file is deprecated.
declare -r postponed_commands="$CACHEDIR/postponed_commands"
#  New, this directory is to be used instead.
declare -r postponed_commands_dir="$CACHEDIR/postponed_commands_dir"

single_process_check
pgrep -u $USER -af "bash.*nadeshiko-do-postponed.sh" \
	&& err 'Cannot run at the same time with Nadeshiko-do-postponed.'


on_error() {
	local func \
	      pyfile="$TMPDIR/nadeshiko-mpv_dialogues_gtk.py" \
	      gladefile="$TMPDIR/nadeshiko-mpv_dialogues_gtk.glade"
	#  Wipe the data directory, so that after a stop caused by an error
	#  we wouldn’t read the old data, but tried to create new ones.
	#  The data per se probably won’t break the script, but those data
	#  could be just stale.
	touch "$datadir/wipe_me"

	for func in ${FUNCNAME[@]}; do
		#  If we couldn’t prepare option list, because we hit an error
		#  with Nadeshiko in dryrun mode…
		if [ "$func" = choose_preset ]; then
			LOGDIR="$TMPDIR" \
			set_last_log_path 'nadeshiko'
			[ -v LAST_LOG_PATH ] && [ -r "$LAST_LOG_PATH" ] && {
				cp "$LAST_LOG_PATH" "$LOGDIR"
				info "Nadeshiko dryrun log:
				      $LOGDIR/${LAST_LOG_PATH##*/}"
				which xclip &>/dev/null && {
					# trapondebug unset
					echo -n "$LOGDIR/${LAST_LOG_PATH##*/}" | xclip
					# trapondebug set
					info 'Copied path to clipboard.'
				}
			}

		#  If we hit an error while parsing .glade or .py files
		#  or while running the .py file…
		elif [ "$func" = show_dialogue_choose_preset ]; then
			[ -r "$pyfile" ] && cp "$pyfile" "$LOGDIR"
			[ -r "$gladefile" ] && cp "$gladefile" "$LOGDIR"

		fi
	done

	#  Cropping module’s own on_error().
	[ "$(type -t on_croptool_error)" = 'function' ] && on_croptool_error

	return 0
}


[ -d "$datadir" ] || mkdir "$datadir"
cd "$datadir"
if [ -e wipe_me ]; then
	set +f
	rm -rf ./*
	set -f
else
	# Delete files older than one hour.
	find -type f -mmin +60  -delete
fi



show_help() {
	cat <<-EOF
	Usage:
	./nadeshiko-mpv.sh [postpone]

	    postpone – Store the command for Nadeshiko for later, instead of
	               running it right away.

	Nadeshiko-mpv in the wiki: https://git.io/fx8D6

	Post bugs here: https://github.com/deterenkelt/Nadeshiko/issues
	EOF
}


show_version() {
	cat <<-EOF
	nadeshiko-mpv.sh $version
	© deterenkelt 2018.
	Licence GPLv3+: GNU GPL ver. 3  <http://gnu.org/licenses/gpl.html>
	This is free software: you are free to change and redistribute it.
	There is no warranty, to the extent permitted by law.
	EOF
}


post_read_rcfile() {
	local preset_name  preset_exists
	(( ${#nadeshiko_presets[*]} == 0 )) \
		&& nadeshiko_presets=( [default]='nadeshiko.rc.sh' )
	(( ${#nadeshiko_presets[*]} > 1 )) && {
		for preset_name in "${!nadeshiko_presets[@]}"; do
			[ "$gui_default_preset" = "$preset_name" ] && preset_exists=t
		done
		[ -v preset_exists ] \
			|| err "GUI default preset with name “$gui_default_preset” doesn’t exist."
	}
	return 0
}


write_var_to_datafile() {
	local varname="$1" varval="$2"
	info "Setting $varname and appending it to ${data_file##*/}."
	declare -g $varname="$varval"
	sed -ri "/^$varname=/d" "$data_file"
	printf "$varname=%q\n" "$varval" >> "$data_file"
	return 0
}


del_var_from_datafile() {
	local varname="$1"
	unset $varname
	info "Deleting $varname from ${data_file##*/}."
	sed -ri "/^$varname=/d" "$data_file"
	return 0
}


populate_data_file() {
	declare -g  ffmpeg_ext_subs  ffmpeg_subs_tr_id  ffmpeg_audio_tr_id
	local i tr_type tr_is_selected tr_id ff_index \
	      tr_is_external external_filename
	#  NB path must come after working directory!
	#  path must be a valid file, but path *may be* relative
	#  to $working_directory, thus the latter becomes a part of the path’s
	#  “good value” test.
	#
	#  Should be done earlier, see below.
	# write_var_to_datafile mpv_socket "$mpv_socket"
	get_props working-directory \
	          screenshot-directory \
	          path \
	          mute \
	          sub-visibility \
	          track-list \
	          track-list/count \
	          volume \
	    || exit $?
	write_var_to_datafile working_directory "$working_directory"
	write_var_to_datafile screenshot_directory "$screenshot_directory"
	if [ -e "$path" ]; then
		write_var_to_datafile path "$path"
	elif [ -e "$working_directory/$path" ]; then
		write_var_to_datafile path "$working_directory/$path"
	fi
	write_var_to_datafile mute $mute
	write_var_to_datafile sub_visibility $sub_visibility

	#  Subtitle and audio tracks are either an index of an internal stream
	#  or a path to an external file.
	for ((i=0; i<track_list_count; i++)); do
		IFS=$'\n' read -d '' tr_type \
		                     tr_is_selected \
		                     tr_id  ff_index \
		                     tr_is_external  external_filename \
			< <( echo "$track_list" \
			     | jq -r ".[$i].type, \
			              .[$i].selected,  \
			              .[$i].id,  .[$i].\"ff-index\", \
			              .[$i].external,  .[$i].\"external-filename\""; \
			     echo -en '\0'
			   )
		info "Track $i
		      Type: $tr_type
		      Selected: $tr_is_selected
		      ID: $tr_id
		      FFmpeg index: $ff_index
		      External: $tr_is_external
		      External filename: $external_filename"
		[ "$tr_is_selected" = true ] && {
			#  ffmpeg_subs_tr_id  and  ffmpeg_audio_tr_id  are to become
			#  “subs” and “audio” parameters for Nadeshiko, thus, they must be
			#  set only subtitles are enabled and audio is on.
			if [ "$tr_type" = sub  -a  -v sub_visibility_true ]; then
				case "$tr_is_external" in
					true)
						if [ -f "$external_filename" ]; then
							ffmpeg_ext_subs="$external_filename"
						elif [ -f "$working_directory/$external_filename" ]; then
							ffmpeg_ext_subs="$working_directory/$external_filename"
						else
							ffmpeg_ext_subs="$FUNCNAME: mpv’s “$external_filename” is not a valid path."
						fi
						write_var_to_datafile ffmpeg_ext_subs "$ffmpeg_ext_subs"
						;;
					false)
						# man mpv says:
						# “Note that ff-index can be potentially wrong if a
						#    demuxer other than libavformat (--demuxer=lavf)
						#    is used. For mkv files, the index will usually
						#    match even if the default (builtin) demuxer is
						#    used, but there is no hard guarantee.”
						# Note the difference between tr_id and ff_index:
						#   - ‘ff_index’ is the number of a *stream* by order,
						#     this includes all video, audio, subtitle streams
						#     and also fonts. ffmpeg -map would use syntax
						#     0:<stream_id> to refer to the stream.
						#   - ‘tr_id’ is the number of this stream among
						#     the other streams of *this same type*.
						#     ffmpeg -map uses syntax 0:s:<subtitle_stream_id>
						#     for these – that’s exactly what we need.
						#     It’s necessary to decrement it by one, as mpv
						#     counts them from 1 and ffmpeg – from 0.
						ffmpeg_subs_tr_id=$((  tr_id - 1  ))
						write_var_to_datafile ffmpeg_subs_tr_id "$ffmpeg_subs_tr_id"
						;;
				esac
				#  ffmpeg_subtitles now contains either a track id,
				#  an absolute path or an error message (Nadeshiko handles all).
			elif [ "$tr_type" = audio   -a  ! -v mute_true ]; then
				case "$tr_is_external" in
					true)
						err 'External audio tracks aren’t supported yet.
						     Please post an issue on the project page to speed up the work!'
						;;
					false)
						#  See the note at the similar place above.
						ffmpeg_audio_tr_id=$((  tr_id - 1  ))
						write_var_to_datafile ffmpeg_audio_tr_id "$ffmpeg_audio_tr_id"
						;;
				esac
			fi
		}
	done

	cat "$data_file"
	return 0
}


 # This function verifies, that all the necessary variables
#  are set at the current stage. For that it has a list of
#  variable names for each caller function.
#
check_needed_vars() {
	declare -A vars_needed=(
		[arrange_times]='time1 time2'
		[play_preview]='time1 time2 mute sub_visibility'
		[choose_preset]=''
		[encode]='time1 time2 mute sub_visibility max_size screenshot_directory working_directory'
		[play_encoded_file]='screenshot_directory working_directory'
	)
	for var in ${vars_needed[${FUNCNAME[1]}]}; do
		[ -v $var ] \
			|| err "Variable “$var” is not set."
	done
	return 0
}


put_time() {
	local mute_text subvis_text
	get_prop time-pos || exit $?
	time_pos=${time_pos%???}
	if [ ! -v time1 -o -v time2 ]; then
		write_var_to_datafile time1 "$time_pos"
		get_props sub-visibility mute || exit $?
		[ -v sub_visibility_true ] \
			&& subvis_text='Subs: ON' \
			|| subvis_text='Subs: OFF'
		[ -v mute_true ] \
			&& mute_text='Sound: OFF' \
			|| mute_text='Sound: ON'
		send_command show-text "Time1 set\n$subvis_text\n$mute_text" "3000" \
			|| exit $?
		unset time2
		del_var_from_datafile time2

	elif [ -v time1 -a ! -v time2 ]; then
		write_var_to_datafile time2 "$time_pos"
		populate_data_file
		[ -v sub_visibility_true ] \
			&& subvis_text='Subs: ON' \
			|| subvis_text='Subs: OFF'
		[ -v mute_true ] \
			&& mute_text='Sound: OFF' \
			|| mute_text='Sound: ON'
		send_command show-text "Time2 set\n$subvis_text\n$mute_text" "3000" \
			|| exit $?
	fi
	return 0
}


arrange_times() {
	check_needed_vars
	local time_buf
	[ "$time1" = "$time2" ] && err "Time1 and Time2 are the same."
	[ "${time1%.*}" -gt "${time2%.*}" ] && {
		time_buf="$time1"
		write_var_to_datafile time1 "$time2"
		write_var_to_datafile time2 "$time_buf"
	}
	return 0
}


pause_and_leave_fullscreen() {
	local  rewind_to_time_pos
	#  Calculating time-pos to rewind to later.
	#  Doing it beforehand to avoid lags on socket connection.
	get_props 'time-pos' 'fullscreen'
	rewind_to_time_pos=${time_pos%.*}
	let "rewind_to_time_pos-=2 ,1"
	(( rewind_to_time_pos < 0 )) && rewind_to_time_pos=0
	set_prop 'pause' 'yes'

	if  (
			[    "${FUNCNAME[1]}" = play_preview ] \
			|| [ "${FUNCNAME[1]}" = choose_crop_settings ] \
			|| [ "${FUNCNAME[1]}" = play_encoded_file  -a  ! -v postpone ]
		) \
		&& [ -v fullscreen_true ]
	then
		#  If the player was in fullscreen, return it back to windowed mode,
		#  or the preview will be playing somewhere in the background.
		#
		#  When in fullscreen mode, sleep for 1.7 seconds, so that
		#  before we turn off fullscreen to show the encoded file,
		#  the user would notice, that the encoding is done, and would
		#  expect to see another file.
		#
		#  Sleeping in paused state while “Encoding is done” is shown.
		[ "$(type -t sleep)" = file ] \
			&& sleep 1.700 \
			|| sleep 2
		set_prop 'fullscreen' 'no'
		#  Rewind the file two seconds back, so that continuing wouldn’t
		#    be from an abrupt moment for the user.
		#  This option is a little unsettling, so it is disabled by default.
		[ -v rewind_back_on_leaving_fullscreen ] \
			&& set_prop 'time-pos' "$rewind_to_time_pos"
	fi
	#  When the encoding is postponed,
	#  pause only for the time notification is shown, and then unpause.
	[ "${FUNCNAME[1]}" = play_encoded_file  -a  -v postpone ] && {
		#  Sleeping in paused state while “Command to encode saved for later.”
		#  is shown. The notification is shown for exectly two seconds, and
		#  due to a small lag it will probably take a bit longer, so sleeping
		#  for two full seconds here.
		sleep 2
		set_prop 'pause' 'no'
		#  We didn’t go off of fullscreen, so no need to rewind.
	}
	return 0
}


choose_crop_settings() {
	declare -g predictor  crop
	local  pick  has_croptool_installer  crop_width  crop_height  \
	       crop_x  crop_y  resp_crop  resp_predictor

	#  Module function.
	[ "$(type -t run_crop_tool)" = 'function' ] || return 0
	pause_and_leave_fullscreen
	#  Module function.
	[ "$(type -t run_croptool_installer)" = 'function' ] \
		&& has_installer=yes \
		|| has_installer=no
	[ -v predictor ] \
		&& predictor=on \
		|| predictor=off

	until [ -v cropsettings_accepted ]; do
		is_crop_tool_available \
			&& pick='on' \
			|| pick='off'

		show_dialogue_crop_and_predictor pick="$pick" \
		                                 has_installer="$has_installer" \
		                                 predictor="$predictor" \
		                                 ${crop_width:-} \
		                                 ${crop_height:-} \
		                                 ${crop_x:-} \
		                                 ${crop_y:-}

		IFS=$'\n' read -r -d ''  resp_crop \
		                         resp_predictor \
			< <(echo -e "$dialog_output\0")

		declare -p resp_crop  resp_predictor
		case "${resp_crop#crop=}" in
			nocrop)
				info 'Disabling crop.'
				unset crop
				cropsettings_accepted=t
				;;
			+([0-9]):+([0-9]):+([0-9]):+([0-9]))
				info 'Setting crop size and position.'
				orig_width=$(get_ffmpeg_attribute "$path" v width)
				orig_height=$(get_ffmpeg_attribute "$path" v height)
				[[ "$resp_crop" =~ ^crop=([0-9]+):([0-9]+):([0-9]+):([0-9]+)$ ]]
				crop_width=${BASH_REMATCH[1]}
				crop_height=${BASH_REMATCH[2]}
				crop_x=${BASH_REMATCH[3]}
				crop_y=${BASH_REMATCH[4]}
				declare -p orig_width  orig_height  crop_width  crop_height  \
				           crop_x  crop_y
				(( crop_width <= orig_width )) \
					|| err "Crop width is larger than the video itself: W > origW."
				(( crop_height <= orig_height )) \
					|| err "Crop height is bigger than the video itself: H > origH."
				(( crop_x <= ( orig_width - crop_width ) )) \
					|| err "Crop Xtopleft puts crop area out of frame bounds: X + W > origW."
				(( crop_y <= ( orig_height - crop_height ) )) \
					|| err "Crop Ytopleft puts crop area out of frame bounds: Y + H > origH."
				cropsettings_accepted=t
				;;
			pick)
				unset crop_width  crop_height  crop_x  crop_y  crop
				prepare_crop_tool \
					|| err 'Cropping module failed at preparing crop tool.'
				run_crop_tool \
					|| err 'Cropping module failed at running crop tool.'
				if [ -v croptool_resp_cancelled ]; then
					warn-ns 'Cropping cancelled.'
				elif [ -v croptool_resp_failed ]; then
					warn-ns 'Crop tool failed.'
				else
					crop_width=$croptool_resp_width
					crop_height=$croptool_resp_height
					crop_x=$croptool_resp_x
					crop_y=$croptool_resp_y
					crop="$crop_width:$crop_height:$crop_x:$crop_y"
				fi
				;;
			install_croptool)
				run_croptool_installer \
					|| err 'Crop tool installer has exited with an error.'
				;;
			*)
				err "Dialog returned wrong value for crop: “$resp_crop”."
				;;
		esac

		case "${resp_predictor#predictor=}" in
			on)
				predictor=on
				;;
			off)
				predictor=off
				;;
			*)
				err "Dialog returned wrong value for predictor: “$resp_predictor”."
				;;
		esac

	done

	[ "$predictor" != on ] && unset predictor
	return 0
}


play_preview() {
	[ -v show_preview ] || return 0
	local  temp_sock="$(mktemp -u)"  sub_file  sid  aid  vfcrop
	check_needed_vars  'sub-file'
	pause_and_leave_fullscreen
	#  --ff-sid and --ff-aid, that take track numbers in FFmpeg order,
	#  i.e. starting from zero within their type, do not work with
	#  certain files.
	[ "$sub_visibility" = yes ] && {
		[ -v ffmpeg_ext_subs ] \
			&& sub_file=(--sub-file "$ffmpeg_ext_subs")  # sic!
		[ -v ffmpeg_subs_tr_id ] && sid="--sid=$(( ffmpeg_subs_tr_id +1 ))"
	}
	[ -v mute ] || aid="--aid=$(( ffmpeg_audio_tr_id +1 ))"
	[ -v crop ] && vfcrop="--vf=crop=$crop"

	$mpv --x11-name mpv-nadeshiko-preview \
	     --title "Preview – $MY_DESKTOP_NAME" \
	     --input-ipc-server="$temp_sock" \
	     --start="$time1" \
	     --ab-loop-a="$time1" --ab-loop-b="$time2" \
	     --mute=$mute \
	     --volume=$volume \
	     --sub-visibility=$sub_visibility \
	         "${sub_file[@]}" \
	         ${sid:-} \
	     ${aid:-} \
	     ${vfcrop:-} \
	     --osd-msg1="Preview" \
	     "$path"
	rm "$temp_sock"
	return 0
}


choose_preset() {
	declare -g  mpv_pid  nadeshiko_presets  scene_complexity
	local  i  param_list  preset_idx  gui_default_preset_idx  \
	       ordered_preset_list  temp  \
	       resp_nadeshiko_preset  preset  preset_exists  \
	       resp_max_size  \
	       resp_fname_pfx  \
	       resp_postpone
	check_needed_vars

	 # Composes a list of options for a preset_option_array_N.
	#  In a subshell reads Nadeshiko configs and executes Nadeshiko in dry run
	#  mode several times to get information about how the video clip
	#  would (or would not) fit at the possible maximum file size presets.
	#   $1  – nadeshiko config in CONFDIR to use.
	#  [$2] – scene_complexity to assume (for the second run and further).
	prepare_preset_options() {
		local nadeshiko_preset="$1"  nadeshiko_preset_name="$2"  size  \
		      scene_complexity  option_list=()  last_line_in_last_log  \
		      native_profile  preset_fitmark  preset_fitdesc  i  \
		      running_preset_mpv_msg
		[ "${3:-}" ] && scene_complexity="$3"
		declare -A codec_names_as_formats
		declare -a known_sub_codecs
		declare -a can_be_used_together
		declare -A bitres_profile_360p \
		           bitres_profile_480p \
		           bitres_profile_576p \
		           bitres_profile_720p \
		           bitres_profile_1080p \
		           bitres_profile_1440p \
		           bitres_profile_2160p
		declare -A ffmpeg_subtitle_fallback_style

		info "Preset: $nadeshiko_preset"  >&2
		milinc
		. "$EXAMPLECONFDIR/example.nadeshiko.rc.sh" \
			|| err "Cannot read example.nadeshiko.rc.sh"
		. "$CONFDIR/$nadeshiko_preset" \
			|| err "$nadeshiko_preset doesn’t exist or is not readable."

		prepare_preset_info() {
			local preset_info=''
			#  Line 1
			preset_info+="$ffmpeg_vcodec ($ffmpeg_pix_fmt) "
			preset_info+="+ $ffmpeg_acodec → $container;"
			preset_info+='  '
			[ "$subs" = yes ] \
				&& preset_info+="+Subs" \
				|| preset_info+="−Subs" 
			preset_info+=' '
			[ "$audio" = yes ] \
				&& preset_info+="+Audio" \
				|| preset_info+="−Audio"
			preset_info+='\n'
			#  Line 2
			preset_info+='Container own space: '
			preset_info+="<span weight=\"bold\">${container_own_size_pct%\%}%</span>"
			preset_info+='\n'
			#  Line 3
			preset_info+='Minimal bitrate perc.: '
			[ "${scene_complexity:-}" = dynamic ] \
				&& preset_info+="<span fgalpha=\"50%\" weight=\"bold\">${minimal_bitrate_pct%\%}%</span>" \
				|| preset_info+="<span weight=\"bold\">${minimal_bitrate_pct%\%}%</span>"
			[ -v scene_complexity ] \
				&& preset_info+="  (source is $scene_complexity)"
			echo "$preset_info"
			return 0
		}

		 # Reads config values for max_size_normal etc, converts [kMG]
		#    suffixes to kB, MB or KiB, MiB, determines, which option
		#    is set to default
		#  $1 – size code, tiny, normal etc.
		prepare_size_radiobox_label() {
			local size="$1"
			declare -n size_val="max_size_$size"
			[ "$size" = unlimited ] && size_val='Unlimited'
			if [ "$kilo" = '1000' ]; then
				size_val=${size_val/k/ kB}
				size_val=${size_val/M/ MB}
				size_val=${size_val/G/ GB}
			elif [ "$kilo" = '1024' ]; then
				size_val=${size_val/k/ KiB}
				size_val=${size_val/M/ MiB}
				size_val=${size_val/G/ GiB}
			fi
			#  GTK builder is bugged, so the 6th option wouldn’t
			#    actually work. We need to set active radiobutton
			#    at runtime, and thus need to have some key to distinguish
			#    the radiobutton, that should be activated.
			#  It also lets the user to see which size is the config’s
			#    default, even when the user clicks on another radiobutton.
			[ "$max_size_default" = "$size" ] && size_val+=" – default"
			echo "$size_val"
			return 0
		}

		 # Checks whether a size code is one of those, that predictor
		#    should run for, as it’s specified in the RC file. Returns 0, if
		#    size should be analysed, 1 otherwise.
		#  $1 – size code, e.g. tiny, normal, small, unlimited, default
		if_predictor_runs_for_this_size() {
			local size="$1"  run_predictor
			for s in "${run_predictor_only_for_sizes[@]}"; do
				if	[ "$s" = "$size" ] \
					|| [ "$s" = 'default'  -a  "$max_size_default" = "$size" ]
				then
					run_predictor=t
					break
				fi
			done
			[ -v run_predictor ]
			return $?
		}

		 # Preset options for the dialogue window
		#
		#  1. Preset file name (config file name), that the dialogue
		#     should return in stdout later.
		option_list=( "$nadeshiko_preset" )

		#  2. Preset display name, that the dialogue uses
		#     for tab title
		option_list+=( "$nadeshiko_preset_name" )

		#  3. Brief description of the configuration for the popup
		option_list+=( "$( prepare_preset_info  2>&1)" )

		if [ -v predictor ]; then
			#  4. Source video description.
			#     Without predictor it’s unknown, but if predictor is enabled,
			#     then it will be set on the first dry run.
			option_list+=( ' ' )
		else
			option_list+=( 'Unknown' )
		fi

		for size in unlimited normal small tiny; do
			[ ! -v predictor ] && {
				option_list+=(
					"$size"
					"$( prepare_size_radiobox_label "$size"  2>&1 )"
					"$( [ "$max_size_default" = "$size" ] \
							&& echo on  \
							|| echo off  )"
					'-'
					'Predictor disabled'
				)
				continue
			}

			#  This saves 1/4 of predictor time w/o determining scenecomp.
			[ "$size" = unlimited ] && {
				option_list+=(
					"$size"
					"$( prepare_size_radiobox_label "$size"  2>&1 )"
					"$( [ "$max_size_default" = "$size" ] \
							&& echo on  \
							|| echo off  )"
					'='
					"$( [ -v native_profile ] \
					        && echo "$native_profile" \
					        || echo '<Native>p'  )"
				)
				continue
			}

			if_predictor_runs_for_this_size "$size" || {
				option_list+=(
					"$size"
					"$( prepare_size_radiobox_label "$size"  2>&1 )"
					"$( [ "$max_size_default" = "$size" ] \
							&& echo on  \
							|| echo off  )"
					'#'
					' '  #  User has intentionally skipped this step, they
					     #    want to clearly see only what they need, hence
					     #    the only sizes they use for predictor will stand
					     #    out better, if there will be less clutter around.
					     #  There will be a tooltip for the “…” mark to leave
					     #    a note about skipping for those who may have
					     #    questions.
				)
				continue
			}

			info "Size: $size"  >&2
			milinc
			running_preset_mpv_msg='Running Nadeshiko predictor'
			running_preset_mpv_msg+="\nPreset: “$nadeshiko_preset_name”"
			[ "$size" = "$max_size_default" ] \
				&& running_preset_mpv_msg+="\nSize: “default”" \
				|| running_preset_mpv_msg+="\nSize: “$size”"
			if [ -v scene_complexity ]; then
				send_command show-text "$running_preset_mpv_msg" '10000' || exit $?
			else
				running_preset_mpv_msg+="\n\nDetermining scene complexity…"
				send_command show-text "$running_preset_mpv_msg" '15000' || exit $?
			fi
			#  Expecting exit codes either 0 or 5  (fits or doesn’t fit)
			errexit_off
			LOGDIR="$TMPDIR"  \
			NO_DESKTOP_NOTIFICATIONS=t  \
			"$MYDIR/nadeshiko.sh" "$nadeshiko_preset"  \
			                      "$time1" "$time2" "$size" "$path" \
			                      ${crop:+crop=$crop} \
			                      dryrun  \
			                      ${scene_complexity:+force_scene_complexity=$scene_complexity} \
			                      &>/dev/null
			errexit_on
			info 'Getting the path to the last log.'  >&2
			LOGDIR="$TMPDIR" \
			read_last_log 'nadeshiko'
			last_line_in_last_log=$(sed -rn '$ p' <<<"$LAST_LOG" 2>&1)
			grep -qE '(Encoding with|Cannot fit)' <<<"$last_line_in_last_log" \
				|| err 'Error while parsing Nadeshiko log.'

			[ -v scene_complexity ] || {    #  Once.
				info 'Reading scene complexity from the log.'  >&2
				scene_complexity=$(
					sed -rn 's/\s*\*\s*Scene complexity:\s(static|dynamic).*/\1/p' \
						<<<"$LAST_LOG"
				)
				if [[ "$scene_complexity" =~ ^(static|dynamic)$ ]]; then
					info "Determined scene complexity as $scene_complexity."  >&2
					#  Updating preset info now that we know scene complexity.
					option_list[2]="$( prepare_preset_info  2>&1)"
					[ "${option_list[3]}" = ' ' ] && {
						#  4. Updating source video description.
						option_list[3]="$scene_complexity"
					}
				else
					warn-ns "Couldn’t determine scene complexity." >&2
					scene_complexity='dynamic'
				fi
				echo "$scene_complexity" >"$TMPDIR/scene_complexity"
			}

			unset bitrate_corrections
			grep -qF 'Bitrate corrections to be applied' <<<"$LAST_LOG" \
				&& bitrate_corrections=t

			container=$(
				sed -rn 's/\s*\*\s*.*\+.*→\s*(.+)\s*.*/\1/p'  <<<"$LAST_LOG"
			)
			[ "$container" ] || warn-ns 'Couldn’t determine container.'
			info "Container to be used: $container"  >&2

			native_profile=$(
				sed -rn 's/\* Starting bitres profile: ([0-9]{3,4}p)\./\1/p' \
					<<<"$LAST_LOG"
			)
			[[ "$native_profile" =~ ^[0-9]{3,4}p$ ]] \
				|| warn-ns 'Couldn’t determine native bitres profile.' >&2
			info "Native bitres profile for the video: $native_profile"  >&2
			for ((i=0; i<${#option_list[@]}; i++)); do
				[ "${option_list[i]}" = '<Native>p' ] && {
					info "Updating value “Native” in the option_list[$i] to $native_profile." >&2
					[ -v bitrate_corrections ] \
						&& option_list[i]="$native_profile*" \
						|| option_list[i]="$native_profile"
				}
			done

			if [[ "$last_line_in_last_log" =~ Encoding\ with.*\ ([0-9]+p|Native|Cropped).* ]]; then
				encoding_res_code="${BASH_REMATCH[1]}"
				if [[ "$encoding_res_code" =~ ^(Native|Cropped)$ ]]; then
					preset_fitmark='='
					preset_fitdesc="$native_profile"
				else
					preset_fitmark='v'
					preset_fitdesc="$encoding_res_code"
				fi
				[ -v bitrate_corrections ] && preset_fitdesc+='*'

			elif [[ "$last_line_in_last_log" =~ Cannot\ fit ]]; then
				preset_fitmark='x'
				preset_fitdesc="Won’t fit"

			else
				preset_fitmark='?'
				preset_fitdesc="Unknown"
				warn-ns 'Unexpected value in Nadeshiko config.'

			fi

			#  Options 5–9 will be repeating for each row.
			#
			#  5. String to return in stdout, if this radiobox is chosen.
			option_list+=( "$size" )

			#  6. Radiobox label.
			option_list+=( "$(prepare_size_radiobox_label "$size" 2>&1)" )

			#  7. Whether radiobox should be set active.
			option_list+=( "$(
				[ "$max_size_default" = "$size" ] && echo on || echo off
			)" )

			#  8. Code character representing how the clip would fit:
			#     “=” – fits at native resolution
			#     “v” – fits with downscale
			#     “x” – wouldn’t fit.
			option_list+=("$preset_fitmark")

			#  9. String accompanying the code character above, either
			#     a profile resolution, e.g. “1080p” or “Won’t fit”.
			option_list+=("$preset_fitdesc")

			mildec
		done

		mildec
		#  echo’ing the list to stdout to be read into an array,
		#    which name would then be send as an argument to the function
		#    running dialogue window.
		#  W! The last element should *never* be empty, or the readarray -t
		#    command will not see the empty line! It will discard the \n,
		#    and there will be a lost element and a shift in the order.
		IFS=$'\n' ; echo "${option_list[*]}"
		return 0
	}

	preset_idx=0
	for nadeshiko_preset_name in "${!nadeshiko_presets[@]}"; do
		#  To put the default preset first later.
		[ "$nadeshiko_preset_name" = "$gui_default_preset" ] \
			&& gui_default_preset_idx=$preset_idx
		nadeshiko_preset="${nadeshiko_presets[$nadeshiko_preset_name]}"
		declare -g -a  preset_option_array_$preset_idx
		declare -n current_preset_option_array="preset_option_array_$preset_idx"
		[ ! -v scene_complexity  -a  -r "$TMPDIR/scene_complexity" ] \
			&& scene_complexity=$(<"$TMPDIR/scene_complexity")
		#  Subshell call is necessary here.
		#  It is to sandbox the sourcing of Nadeshiko configs.
		errexit_off
		param_list=$(
			prepare_preset_options "$nadeshiko_preset"  \
			                       "$nadeshiko_preset_name"   \
			                       ${scene_complexity:-}
		) || exit $?

		echo
		info "Options for preset $nadeshiko_preset:"
		declare -p param_list
		readarray -d $'\n'  -t  current_preset_option_array  <<<"$param_list"
		let ++preset_idx
	done

	#  Placing the default preset first to be opened in GUI by default.
	ordered_preset_list=( ${!preset_option_array_*} )
	[ "${ordered_preset_list[0]}" != preset_option_array_$gui_default_preset_idx ] && {
		temp="${ordered_preset_list[0]}"
		ordered_preset_list[0]="preset_option_array_$gui_default_preset_idx"
		ordered_preset_list[gui_default_preset_idx]="$temp"
	}

	 # Must be here, because mpv_pid is used in functions, that send messages
	#  to mpv window, when it may be closed. To avoid that, we must know
	#  its PID and check if it’s still running, so if there would be
	#  no window, we wouldn’t send anything.
	#
	mpv_pid=$(lsof -t -c mpv -a -f -- "$mpv_socket")
	[[ "$mpv_pid" =~ ^[0-9]+$ ]] || err "Couldn’t determine mpv PID."

	echo
	info "Dispatching options to dialogue window:"
	declare -p ordered_preset_list
	declare -p ${!preset_option_array_*}
	send_command show-text 'Building GUI' '1000' || exit $?
	show_dialogue_choose_preset "${ordered_preset_list[@]}"

	IFS=$'\n' read -r -d ''  resp_nadeshiko_preset  \
	                         resp_max_size  \
	                         resp_fname_pfx  \
	                         resp_postpone  \
		< <(echo -e "$dialog_output\0")
	#  Verifying data
	for preset in ${nadeshiko_presets[@]}; do
		[ "$resp_nadeshiko_preset" = "$preset" ] && preset_exists=t
	done
	if [ -v preset_exists ]; then
		write_var_to_datafile nadeshiko_preset "$resp_nadeshiko_preset"
	else
		err 'Dialog didn’t return a valid Nadeshiko preset.'
	fi

	if [[ "$resp_max_size" =~ ^(tiny|small|normal|unlimited)$ ]]; then
		write_var_to_datafile max_size "$resp_max_size"
	else
		err 'Dialog didn’t return a valid maximum size code.'
	fi

	! [[ "$resp_fname_pfx" =~ ^[[:space:]]*$ ]]  \
		&& write_var_to_datafile  fname_pfx  "$resp_fname_pfx"

	if [ "$resp_postpone" = postpone ]; then
		write_var_to_datafile  postpone  "$resp_postpone"
	elif [ "$resp_postpone" = run_now ]; then
		#  keeping postpone unset, as writing it to datafile will set it
		#  as a global variable.
		:
	else
		err 'Dialog returned an unknown value for postpone.'
	fi

	return 0
}


encode() {
	check_needed_vars
	local  audio  subs  nadeshiko_retval  command  postponed_job_file  str  \
	       first_line_in_postponed_command=t

	[ -v ffmpeg_audio_tr_id ]  \
		&& audio=audio:$ffmpeg_audio_tr_id  \
		|| audio=noaudio

	 # Never rely on “sub_visibility” property, as it is on by default:
	#  even when there’s no subtitles at all.
	if [ -v ffmpeg_ext_subs ];  then
		subs="subs=$ffmpeg_ext_subs"
	elif [ -v ffmpeg_subs_tr_id ];  then
		subs="subs:$ffmpeg_subs_tr_id"
	else
		subs='nosubs'
	fi

	if [ -e "/proc/${mpv_pid:-not exists}" ]; then
		send_command show-text 'Encoding' '2000' || exit $?
	else
		: warn-ns "Not sending anything to mpv: it was closed."
	fi


	 # “postpone” passed to nadeshiko-mpv.sh forks the process in a paused
	#    state in the background. When nadeshiko.sh (not …-mpv.sh!) is called
	#    with a single parameter “unpause”, it unfreezes the processes
	#    one by one and then quits.
	#  This allows to free the watching from humming/heating and probably,
	#    even glitchy playback, if you attempt to continue watching after
	#    firing up the encode, especially, if it’s the 2nd, the 3rd or the 15th.
	#
	nadeshiko_command=(
		"$MYDIR/nadeshiko.sh"  "$time1" "$time2" "$path"
		                       "$audio" "$subs" "$max_size"
		                       ${crop:+crop=$crop}
		                       "${screenshot_directory:-$working_directory}"
		                       ${fname_pfx:+"fname_pfx=$fname_pfx"}
		                       ${scene_complexity:+force_scene_complexity=$scene_complexity}
		                       "$nadeshiko_preset"
	)
	if [ -v postpone ]; then
		[ -d "$postponed_commands_dir" ] || mkdir "$postponed_commands_dir"
		postponed_job_file="$postponed_commands_dir"
		postponed_job_file+="/$(mktemp -u "${path##*/}.XXXXXXXX").sh"
		cat <<-EOF >"$postponed_job_file"
		#! /usr/bin/env bash

		#  Nadeshiko-mpv postponed job file
		#  ${postponed_job_file##*/}
		#  This file is to be run with nadeshiko-do-postponed.sh


		EOF
		chmod +x "$postponed_job_file"
		for str in "${nadeshiko_command[@]}"; do
			if [ -v first_line_in_postponed_command ]; then
				printf '%q  \\\n\t\\\n' "$str" >>"$postponed_job_file"
				unset first_line_in_postponed_command
			else
				printf '\t%q  \\\n' "$str" >>"$postponed_job_file"
			fi
		done
		echo >>"$postponed_commands"
		rm "$data_file"
		if [ -e "/proc/${mpv_pid:-not exists}" ]; then
			send_command  show-text \
			              "Command to encode saved for later."  \
			              '2000' \
				|| exit $?
		fi
		exit 0
	else
		errexit_off
		set -x
		"${nadeshiko_command[@]}"
		nadeshiko_retval=$?
		set +x
		errexit_on
		rm "$data_file"
		if [ -e "/proc/${mpv_pid:-not exists}" ]; then
			if [ $nadeshiko_retval -eq 0 ]; then
				send_command show-text 'Encoding done.'  '2000' || exit $?
			else
				send_command show-text 'Failed to encode.'  '3000' || exit $?
				#  Don’t display a desktop notification with an error here –
				#  nadeshiko.sh does this.
				# err 'Encoding failed.'
			fi
		else
			: warn-ns "Not sending anything to mpv: it was closed."
		fi
	fi
	return $nadeshiko_retval
}


play_encoded_file() {
	[ -v show_encoded_file ] || return 0

	local  last_file  temp_sock="$(mktemp -u)"
	check_needed_vars
	read_last_log 'nadeshiko' || {
		warn "Cannot get last log."
		return 1
	}
	info "last_log: $LAST_LOG_PATH"
	last_file=$(sed -rn '/Encoded successfully/ {n; s/^..//p}' <<<"$LAST_LOG")
	info "last_file: $last_file"

	[ -e "/proc/${mpv_pid:-not exists}" ] && pause_and_leave_fullscreen

	 # Setting --screenshot-directory, because otherwise screenshots
	#  taken from that video would fall into $datadir, and it’s not
	#  obvious to seek for them there.
	$mpv --x11-name mpv-nadeshiko-preview \
	     --title "Encoded file – $MY_DESKTOP_NAME" \
	     --input-ipc-server="$temp_sock" \
	     --loop-file=inf \
	     --mute=no \
	     --volume=$volume \
	     --sub-visibility=yes \
	     --osd-msg1="Encoded file" \
	     --screenshot-directory="${screenshot_directory:-$working_directory}" \
	     "${screenshot_directory:-$working_directory}/$last_file"
	rm -f "$temp_sock"
	return 0
}



read_rcfile  "$rcfile_minver"
post_read_rcfile

REQUIRED_UTILS+=(
	python3     # Dialogue windows.
	xmlstarlet  # To alter XML in the GUI file.
	find        # To find and delete possible leftover data files.
	lsof        # To check, that there is an mpv process listening to socket.
	jq          # To parse JSON from mpv.
	pgrep
	wc
	socat
)
check_required_utils

[[ "${1:-}" =~ ^(-h|--help)$ ]] && show_help && exit 0
[[ "${1:-}" =~ ^(-v|--version)$ ]] && show_version && exit 0
#  Can be passed to set both Time1 and Time2,
#  acts only when the time to encode comes.
[ "${1:-}" ] && [ "${1:-}" = postpone ] && postpone=t
[ "$*" -a ! -v postpone ] && {
	show_help
	err 'The only parameter may be “postpone”!'
}

 # Test, that all the entries from our properties array
#  can be retrieved.
#
# retrieve_properties

get_props mpv-version filename
data_file=$(grep -rlF "filename=$(printf '%q' "$filename")" |& head -n1)
if [ -e "$data_file" ]; then
	# Read properties.
	. "$data_file"
else
	 # Check connection and get us filename to serve as an ID for the playing
	#    file, as for getting path we’d need working-directory. Not taking
	#    path for ID to not do the job twice.
	#
	data_file=$(mktemp --tmpdir='.'  mpvfile.XXXX)
	# printf "filename=%q\n" "$filename" > "$data_file"
	write_var_to_datafile filename "$filename"
	write_var_to_datafile mpv_socket "$mpv_socket"
fi

#  If this is the first run, set time1 and quit.
#  On the second run (time2 is set) do the rest.
put_time && [ -v time2 ] && {
	#  Check, if Time1 and Time2 are the same and order them properly.
	arrange_times
	choose_crop_settings
	play_preview
	choose_preset
	#  Call Nadeshiko.
	encode || exit $?
	#  Show the encoded file.
	play_encoded_file
}


exit 0