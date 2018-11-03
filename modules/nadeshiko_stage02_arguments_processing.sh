#  Should be sourced.

#  stage02_arguments_processing.sh
#  Nadeshiko module that contains functions for parsing, verifying,
#  and processing arguments. It also has a function that would
#  display the initial set of parameters.
#  deterenkelt © 2018
#
#  For licence see nadeshiko.sh


 # Assigns start time, stop time, source video file
#  and other stuff from command line parameters.
#  $@ – see show_help()
#
parse_args() {
	declare -g  subs  subs_explicitly_requested  subs_external_file  \
	            subs_track_id  \
	            audio  audio_explicitly_requested  audio_track_id  \
	            kilo  scale  crop  video  where_to_place_new_file  \
	            new_filename_user_prefix  max_size  vbitrate  abitrate \
	            scene_complexity  dryrun
	local args=("$@") arg pid
	for arg in "${args[@]}"; do
		if [[ "$arg" = @(-h|--help) ]]; then
			show_help

		elif [[ "$arg" = @(-v|--version) ]]; then
			show_version

		elif is_valid_timestamp "$arg"; then
			if [ ! -v time1  -a  ! -v time2 ]; then
				new_time_array "$arg" 'time1'  || err 'Couldn’t set Time1'
			elif [ -v time1  -a  ! -v time2 ]; then
				new_time_array "$arg" 'time2'  || err 'Couldn’t set Time2.'
			else
				err 'Cannot work with more than 2 timestamps.'
			fi

		elif [[ "$arg" =~ ^(no|)subs?((=|:)(.+)|)$ ]]; then
			#         external file ---^ ^---internal subtitle(!) track ID
			case "${BASH_REMATCH[1]}" in
				no)
					unset subs
					;;
				'')
					subs=t
					#  Remember, that subtitles were explicitly requested.
					#  This is needed to treat differently two cases:
					#  - “subs” are turned on by default. If a video would
					#    have no subs, Nadeshiko should be quiet and encode
					#    without subtitles.
					#  - “subs((=|:)(.+)|)” were set explicitly. In this case
					#    the lack of subtitles to render is an error.
					subs_explicitly_requested=t
					[ "${BASH_REMATCH[3]}" = '=' ] && {
						subs_external_file="${BASH_REMATCH[4]}"
						[ -r "$subs_external_file" ] \
							|| err "No such external subs file:
							        $subs_external_file"
					}
					[ "${BASH_REMATCH[3]}" = ':' ] && {
						subs_track_id="${BASH_REMATCH[4]}"
						[[ "$subs_track_id" =~ ^[0-9]+$ ]] \
							|| err "Subtitle track ID must be a number,
							        but it is set to “$subs_track_id”."
					}
					;;
			esac

		elif [[ "$arg" =~ ^(no|)audio(:(.+)|)$ ]]; then
			case "${BASH_REMATCH[1]}" in
				no) unset audio ;;
				'')
					audio=t
					#  Remembering it for the same reason as with “subs”.
					audio_explicitly_requested=t
					[ "${BASH_REMATCH[2]}" ] && {
						audio_track_id="${BASH_REMATCH[3]}"
						[[ "$audio_track_id" =~ ^[0-9]+$ ]] \
							|| err "Audio track ID must be a number,
							        but it is set to “$audio_track_id”."
					}
					;;
			esac

		elif [[ "$arg" =~ ^(si|kilo=1000|k=1000)$ ]]; then
			kilo=1000

		elif [[ "$arg" =~ ^($(IFS='|'; echo "${known_res_list[*]}"))p$ ]]; then
			scale="${BASH_REMATCH[1]}"

		elif [[ "$arg" =~ ^(tiny|small|normal|default|unlimited)$ ]]; then
			declare -gn max_size="max_size_$arg"

		elif [[ "$arg" =~ ^(vb|ab)([0-9]+[kMG])$ ]]; then
			[ "${BASH_REMATCH[1]}" = vb ] && vbitrate="${BASH_REMATCH[2]}"
			[ "${BASH_REMATCH[1]}" = ab ] && abitrate="${BASH_REMATCH[2]}"

		elif [[ "$arg" =~ ^crop=([0-9]+):([0-9]+):([0-9]+):([0-9]+)$ ]]; then
			crop_w=${BASH_REMATCH[1]}
			crop_h=${BASH_REMATCH[2]}
			crop_x=${BASH_REMATCH[3]}
			crop_y=${BASH_REMATCH[4]}
			crop="crop=trunc($crop_w/2)*2:"
			crop+="trunc($crop_h/2)*2:"
			crop+="trunc($crop_x/2)*2:"
			crop+="trunc($crop_y/2)*2"

		elif [ -f "$arg" ]; then
			[[ "$(file --mime-type -L -b "$arg")" =~ ^video/ ]] \
				&& video="$arg" \
				|| err "This is not a video file: ${arg##*/}"

		elif [ -d "$arg" ]; then
			if [ -w "$arg" ]; then
				where_to_place_new_file="$arg"
			else
				err "Cannot place files to directory “$arg”: not writeable."
			fi

		elif [[ "$arg" =~ ^fname_pfx=(.+)$ ]]; then
			#  User prefix for the name of the encoded file.
			#  - user might want to add a user prefix to the filename,
			#    e.g. to note who does what on the video.
			#  - test suite uses it to keep the encoded files in order.
			new_filename_user_prefix="${BASH_REMATCH[1]}"

		#  Internal use.
		#  Nadeshiko-mpv uses this with dryrun.
		elif [[ "$arg" =~ ^force_scene_complexity=(static|dynamic)$ ]]; then
			scene_complexity=${BASH_REMATCH[1]}
			scene_complexity_forced=t

		elif [ "$arg" = dryrun ]; then
			dryrun=t

		else
			err "“$arg”: parameter unrecognised."
		fi
	done

	[ -v video ] || err "Source video is not specified."
	return 0
}


 # Check, that all needed utils are in place and ffmpeg supports
#  user’s encoders.
#
check_util_support() {
	local codec_list missing_encoders arg ffmpeg_ver ffmpeg_is_too_old
	#  bc – For the floating point calculations, that are necessary
	#       e.g. in determining scene_complexity.
	REQUIRED_UTILS+=(bc)
	for arg in "$@"; do
		case "$arg" in
			video)
				REQUIRED_UTILS+=(
					#  For encoding. 3.4.2+ recommended.
					ffmpeg
					#  For retrieving data from the source video
					#  and verifying resulting video.
					ffprobe
					#  For the parts not retrievable with ffprobe
					#  and as a fallback option for when ffprobe fails.
					mediainfo
				)
				;;
			subs)
				REQUIRED_UTILS+=(
					#  To get the list of attachments in the source video.
					mkvmerge
					#  To extract subtitles and fonts from the source video.
					#  (subtitles are needed for hardsubbing, and the hardsub
					#  will be poor without built-in fonts).
					mkvextract
				)
				;;
			crop_gui)
				# REQUIRED_UTILS+=(
				# 	#  Shutter allows to select a rectangle on the screen
				# 	#  and adjust(!) it.
				# 	shutter
				# 	#  Visgrep finds the coordinates of the cropped image.
				# 	#  Not imagemagick, because the imagemagick docs them-
				# 	#  selves recommend visgrep as a faster program.
				# 	visgrep
				# )
				;;
			time_stat)
				REQUIRED_UTILS+=(
					#  To output how many seconds the encoding took.
					#  Only pass1 and pass2, no fonts/subtitles extraction.
					time
				)
				;;
		esac
	done
	check_required_utils
	#  Checking ffmpeg version
	readarray -t ffmpeg_ver < <( \
		$ffmpeg -version \
		    | sed -rn '1s/ffmpeg version (\S+) .*/\1/p
		                s/libav(util|codec|format)\s+([0-9]{2,3})\..*/\2/p'
	)
	info "System ffmpeg: ${ffmpeg_ver[0]} ${ffmpeg_ver[1]}/${ffmpeg_ver[2]}/${ffmpeg_ver[3]}."
	for ((i=1; i<4; i++)); do
		[ ${ffmpeg_ver[i]} -lt ${ffmpeg_minver[i]} ] \
			&& ffmpeg_is_too_old=t
	done
	[ -v ffmpeg_is_too_old ] && {
		warn 'The FFmpeg version you are running is too old!'
		cat <<-EOF | column -t  -o '    '  -N ' ','Needed','In your FFmpeg'
		  libavutil      ${ffmpeg_minver[1]}+    ${ffmpeg_ver[1]}
		  libavcodec     ${ffmpeg_minver[2]}+    ${ffmpeg_ver[2]}
		  libavformat    ${ffmpeg_minver[3]}+    ${ffmpeg_ver[3]}
		EOF
		err 'FFmpeg is too old.'
	}
	codec_list=$($ffmpeg -hide_banner -codecs)
	for arg in "$@"; do
		case "$arg" in
			video)
				grep -qE "\s.EV... .*encoders:.*$ffmpeg_vcodec" \
					<<<"$codec_list" || {
					warn "FFmpeg doesn’t support $ffmpeg_vcodec encoder."
					missing_encoders=t
				}
				;;
			audio)
				grep -qE "\s.EA... .*encoders:.*$ffmpeg_acodec" \
					<<<"$codec_list" || {
					warn "FFmpeg doesn’t support $ffmpeg_acodec encoder."
					missing_encoders=t
				}
				;;
			subs)
				grep -qE "\s.ES... ass" <<<"$codec_list" || {
					warn "FFmpeg doesn’t support encoding ASS/SSA subtitles."
					missing_encoders=t
				}
				;;
		esac
	done
	[ -v missing_encoders ] \
		&& err "FFmpeg doesn’t support requested encoder(s)."
	return 0
}


check_container_and_codec_set() {
	local i  combination  combination_passes
	[ "$container" = auto ] && {
		for combination in "${can_be_used_together[@]}"; do
		[[ "$combination" =~ ^([^[:space:]]+)[[:space:]]+$ffmpeg_vcodec[[:space:]]+$ffmpeg_acodec$ ]] \
			&& container="${BASH_REMATCH[1]}"
		done
	}
	for combination in "${can_be_used_together[@]}"; do
		[[ "$combination" =~ ^$container[[:space:]]+$ffmpeg_vcodec[[:space:]]+$ffmpeg_acodec$ ]] \
			&& combination_passes=t && break
	done
	[ -v combination_passes ] || {
		warn "“$container”, “$ffmpeg_vcodec” and “$ffmpeg_acodec” cannot be used together.
		      Possible combinations:
		      $(for ((i=0; i<${#can_be_used_together[@]}; i++)); do
		            echo "  $((i+1)). ${can_be_used_together[i]//[[:space:]]/ \+ }"
		        done)"
		err 'Incompatible set of container format and A/V codecs.'
	}
	return 0
}


check_mutually_exclusive_options() {
	[ -v abitrate  -a  ! -v audio ] \
		&& err "“noaudio” cannot be used with forced audio bitrate."
	[ -v crop  -a  -v scale ] \
		&& err "“crop” and “scale” cannot be used at the same time."
	return 0
}


check_times() {
	#  Getting video duration to compare with the requested.
	#  If we couldn’t retrieve it, it’s not critical.
	new_time_array "$(get_mediainfo_attribute "$video" g 'Duration')" \
	               'mediainfo_source_duration'  || :

	[ ! -v time1  -a  ! -v time2 ] && {
		#  If neither Time1 nor Time2 is set, use the full video duration.
		new_time_array "00:00:00.000" 'time1'  \
			|| err 'Couldn’t set Time1 to 00:00:00.000'
		new_time_array "${mediainfo_source_duration[ts]}" 'time2' \
			|| err "Couldn’t set Time2 to ${mediainfo_source_duration[ts]}"
	}
	[ ${time2[total_ms]} -gt ${time1[total_ms]} ]  \
		&& declare -gn start='time1'  stop='time2' \
		|| declare -gn start='time2'  stop='time1'
	[ ${time1[total_ms]} -eq ${time2[total_ms]} ] \
		&& err 'Time1 and Time2 must differ!'

	new_time_array "$(total_ms_to_total_s_ms "$((   ${stop[total_ms]}
	                                              - ${start[total_ms]} ))" )" \
	               'duration'
	if [ -v mediainfo_source_duration ]; then
		if [[ "${mediainfo_source_duration[total_s]}" =~ ^[0-9]+$ ]]; then
			#  Trying to prevent negative space_for_video_track.
			[ ${start[total_s]} -gt ${mediainfo_source_duration[total_s]} ] \
				&& err "Start time is behind the end: ${start[ts]}."
			[ ${stop[total_s]}  -gt ${mediainfo_source_duration[total_s]} ] \
				&& err "Stop time is behind the end: ${stop[ts]}."
		else
			unset mediainfo_source_duration
		fi
	else
		#  We still can try to work, there is a check
		#  for negative space_for_video_track ahead.
		unset mediainfo_source_duration
	fi
	return 0
}


check_subtitles() {
	declare -g subs_need_extraction  subs_need_conversion  prepped_ext_subs
	local  codec_name  such  known_sub_codecs_list  ext_subtitle_type

	if  [ -v subs_external_file ]; then
		#  If “subs” is set, and the subtitles are in the external file,
		#  let’s verify, that it’s in the ASS/SSA format, or a format
		#  conversible to it.
		ext_subtitle_type="$(file --mime-type -L -b -d "$subs_external_file")"
		case "$ext_subtitle_type" in
			'SSA subtitles')
				;&
			'ASS subtitles')
				#  Nothing to do, but to rename – on the last stage.
				subs_source_format='ASS/SSA'
				prepped_ext_subs="$TMPDIR/subs.ass"
				cp "$subs_external_file" "$prepped_ext_subs"
				;;
			'WebVTT subtitles')
				subs_source_format='SubRip/WebVTT'
				prepped_ext_subs="$TMPDIR/subs.vtt"
				cp "$subs_external_file" "$prepped_ext_subs"
				#  WebVTT and SRT need to be converted before use.
				#  Proceeding to prepare_subtitles().
				subs_need_conversion=t
				;;
			'SubRip subtitles')
				subs_source_format='SubRip/WebVTT'
				prepped_ext_subs="$TMPDIR/subs.srt"
				cp "$subs_external_file" "$prepped_ext_subs"
				#  WebVTT and SRT need to be converted before use.
				#  Proceeding to prepare_subtitles().
				subs_need_conversion=t
				;;
			#'“bitmap subtitles”')
				#  Bitmap subtitles technically can be rendered, but:
				#  - VobSub subtitles extracted are two files –
				#    .idx. and .sub. It is unclear, how to include
				#    and manipulate them with -map;
				#  - there are no examples of how it should be done.
				#  Thus, unless there’s a precedent, VobSub as external
				#  files won’t be supported, a workaround may be building
				#  them into a mkv (a simply stream copy would do, and
				#  it would be fast), then Nadeshiko can overlay them,
				#  when they are included as a stream.
				#;;
			*)
				#  External subs can only be requested,
				#  so it’s always an error, when they can’t be rendered.
				err "Cannot add external subtitles: “$ext_subtitle_type” format is not supported. Add “nosub”?"
				;;
		esac
	else
		#  Now if “subs” is set, and we use an internal track,
		#  verify, that it’s the type, that we can hardsub.
		codec_name=$(
			get_ffmpeg_attribute "$video" \
			                     "s:${subs_track_id:-0?}" \
			                     codec_name
		)
		[ -v subtitle_track_id ] \
			&& such="${subtitle_track_id}th" \
			|| such='default'

		[ -z "$codec_name" ] && {
			if  [ -v subs_explicitly_requested ];  then
				err "Adding subtitles was requested, but there’s no $such subtitle stream. Add “nosub”?"
			else
				#  It was just RC default setting,
				#  it isn’t an error, that a video had no subs at all.
				info "No subtitles to add. Disabling hardsub."
				unset subs
				#  Stopping subs processing.
				return 1
			fi
		}

		known_sub_codecs_list=$(IFS='|'; echo "${known_sub_codecs[*]}")
		#  Unlike with a video that simply has no subtitle stream,
		#  having one, that we cannot encode is always an error.
		[[ "$codec_name" =~ ^($known_sub_codecs_list)$ ]]  \
			|| err "Cannot add subtitles: “$codec_name” is not supported. Add “nosub”?"
		if [[ "$codec_name" =~ ^(ass|ssa)$ ]]; then
			subs_source_format='ASS/SSA'
			prepped_ext_subs="$TMPDIR/subs.ass"
			#  For now extract every type of subtitles, even ASS.
			subs_need_extraction=t
		elif [[ "$codec_name" =~ ^(subrip|srt)$ ]]; then
			subs_source_format='SubRip/WebVTT'
			prepped_ext_subs="$TMPDIR/ext.srt"
			subs_need_extraction=t
			subs_need_conversion=t
		elif [[ "$codec_name" =~ ^(vtt|webvtt)$ ]]; then
			subs_source_format='SubRip/WebVTT'
			#  FFmpeg differentiates between srt and vtt formats.
			prepped_ext_subs="$TMPDIR/ext.vtt"
			subs_need_extraction=t
			subs_need_conversion=t
		elif [[ "$codec_name" =~ ^(dvd_subtitle)$ ]]; then
			subs_source_format='VobSub'
			subs_need_overlay=t
		elif [[ "$codec_name" =~ ^(hdmv_pgs_subtitle)$ ]]; then
			subs_source_format='PGS'
			subs_need_overlay=t
		fi
		#  Before this function we didn’t know, if there’s a default
		#  track, and which we should use. We must have differentiated
		#  between a concrete track number passed via command line and
		#  the default “0:s:0?” track. Now at this point we don’t need
		#  to keep this difference any more, and we know for sure, that
		#  there is a default track № 0.
		: ${subs_track_id:=0}
	fi

	return 0
}


prepare_subtitles() {
	[ -v dryrun ] && {
		info 'Dry run: skipping subtitle preparation.'
		return 0
	}
	local  mkvmerge_output  id  font_name
	[ -v subs_need_extraction ] && {
		info "Extracting subs and fonts."
		# NB: -map uses 0:s:<subtitle_track_id> syntax here.
		#   It’s the number among SUBTITLE tracks, not overall!
		# “?” in 0:s:0? is to ignore the lack of subtitle track.
		#   If the default setting is to add subs, it shouldn’t lead
		#   to an error, if the source simply doesn’t have subs:
		#   specifying “nosub” for them shouldn’t be a requirement.
		# NB: -map uses 0:s:<subtitle_track_id> syntax here.
		#   It’s the number among SUBTITLE tracks, not overall!

		FFREPORT=file=$LOGDIR/ffmpeg-subs-extraction.log:level=32 \
		$ffmpeg -y -hide_banner \
		        -i "$video" \
		        -map 0:s:$subs_track_id \
		        "$prepped_ext_subs" \
			|| err "Cannot extract subtitle stream $subs_track_id: ffmpeg error."

		#  Extracting built-in fonts for built-in subs
		#  MKV may be reported as \n\n\n\nMatroska video,
		#  so we don’t match for a literal string ^Mastroska\ video$
		if [[ "$source_video_container" =~ 'Matroska video' ]]; then  # sic!
			mkvmerge_output=$(mkvmerge -i "$video") \
				|| err "Cannot get the list of attachments: mkvmerge error."
			while read -r ; do
				id=${REPLY%$'\t'*}
				font_name=${REPLY#*$'\t'}
				mkvextract attachments \
				           "$video" $id:"$TMPDIR/fonts/$font_name" \
				           &>"$LOGDIR/mkvextract.log" \
					|| err "Cannot extract attachment font $id “$font_name”: mkvextract error."
			done < <(
				echo "$mkvmerge_output" \
					| sed -rn "s/Attachment ID ([0-9]+):.*\s+'(.*)(ttf|TTF|otf|OTF)'$/\1\t\2\3/p"
			)
		else
			warn-ns "Font extraction from “$source_video_container” is not implemented yet."
		fi
	}
	[ -v subs_need_conversion ] && {
		#  If external file was in ASS/SSA format, it was already placed
		#  in $TMPDIR as subs.ass.
		FFREPORT=file=$LOGDIR/ffmpeg-subs-conversion.log:level=32 \
		$ffmpeg -hide_banner -i "$prepped_ext_subs"  "$TMPDIR/subs.ass" \
			|| err "Cannot convert subtitles to ASS: ffmpeg error."
	}
	return 0
}


 # When external audio tracks will be supported, parts of this code
#  should be uncommented.
check_audio_track() {
	local  codec_name  such
	# if  [ -v audio_external_file ]; then
	# 	: "Currently, external audio tracks are not supported."
	# else
		codec_name=$(
			get_ffmpeg_attribute "$video" \
			                     "a:${audio_track_id:-0?}" \
			                     codec_name
		)
		[ -v audio_track_id ] \
			&& such="${audio_track_id}th" \
			|| such='default'

		[ -z "$codec_name" ] && {
			if  [ -v audio_explicitly_requested ];  then
				err "Adding an audio track was requested, but there’s no $such sound stream. Add “noaudio”?"
			else
				#  It was just RC default setting,
				#  it isn’t an error, that a video had no audio track at all.
				info "No audio track to add. Disabling sound."
				unset audio
				return 1
			fi
		}
	# fi
	return 0
}
prepare_audio_track() { : "dummy"; return 0; }


 # Determines how fast the scenes in the video change.
#  For example, a 30 seconds video may contain 2–3 static scenes with somebody
#    having a dinner under a tree, or it may be an opening, which is filled
#    with dynamic scenes that change every 2–3 seconds on top of that.
#  These two videos would have different requirements for the bitrate to pre-
#    serve quality, hence for the dynamic one we want to lock available bit-
#    rates to the desired value (and if it won’t fit, then IMMEDIATELY go one
#    resolution lower, unless the difference between the desried bitrate and
#    what fits is marginal.
#  See also:
#  https://github.com/deterenkelt/Nadeshiko/wiki/Tests.-Video-complexity
#
#  TAKES
#    $1 – video
#    $2 – start time (whatever format ffmpeg reads)
#    $3 – duration (between start and stop time, in total_s_ms, e.g. 125.500)
#    $4 – duration in total seconds with rounded up milliseconds.
#
#  SETS
#    scene_complexity to either “static” or “dynamic”.
#
determine_scene_complexity() {
	declare -g  scene_complexity  scene_complexity_assumed
	local video="$1" start_time="$2" duration_total_s_ms="$3" \
	      duration_total_s="$4" total_scenes is_dynamic
	info 'Determining video complexity.
	      It takes 2–20 seconds depending on video.'
	total_scenes=$(
		FFREPORT=file=$LOGDIR/ffmpeg-scene-complexity.log:level=32 \
		$ffmpeg  -ss "$start_time"  -t "$duration_total_s_ms"  -i "$video" \
		         -vf "select='gte(scene,0.3)',metadata=print:file=-" \
		         -an -sn -f null -
	) || err "Couldn’t determine scene complexity: ffmpeg error."
	total_scenes=$(
		grep -cE '^lavfi\.scene_score=0\.[0-9]{6}$' <<<"$total_scenes" || :
		# When ffmpeg finds no scene changes – and there may be none, if the
		# clip is simply too short to have them – grep will print the count
		# as “0” to stdout, but will quit with return code 1 as no matches
		# were found. || : is to prevent quitting here.
	)
	[[ "$total_scenes" =~ ^[0-9]+$ ]] && {
		((total_scenes++, 1))  # add the initial scene
		sps_ratio=$(echo "scale=2; $duration_total_s / $total_scenes" | bc) \
			||:
		#                      dynamic < $video_sps_threshold < static
		is_dynamic=$( echo "$sps_ratio < $video_sps_threshold" | bc ) \
			||:
		[[ "$is_dynamic" =~ ^[01]$ ]] && {
			case "$is_dynamic" in
				0) # 0 = negative in bc
					scene_complexity='static'
					;;
				1) # 1 = positive in bc
					scene_complexity='dynamic'
					;;
			esac
		}
	}
	#  If the type is undeterminable, allow the use
	#  of bitrate–resolution ranges.
	[ -v scene_complexity ] || {
		warn 'Cannot determine video complexity, assuming static.'
		scene_complexity='static'
		scene_complexity_assumed=t
	}
	return 0
}


 # Verifies the input data further, prepares the necessary files
#    and sets (or unsets) variables.
#  Uses only warnings and errors, info for the user is printed
#    later by display_settings().
#
set_vars() {
	local  i  is_16_9
	declare -g source_video_container=$(file --mime-type -L -b -d "$video")

	check_container_and_codec_set
	[ -v max_size ] || declare -g max_size=$max_size_default
	check_mutually_exclusive_options
	check_times

	# Getting the original video and audio bitrate.
	orig_video_bitrate=$(get_mediainfo_attribute "$video" v 'Nominal bit rate')
	[ "$orig_video_bitrate" ] \
		|| orig_video_bitrate=$(get_mediainfo_attribute "$video" v 'Bit rate')
	if [ "$orig_video_bitrate" != "${orig_video_bitrate%kb/s}" ]; then
		orig_video_bitrate=${orig_video_bitrate%kb/s}
		orig_video_bitrate=${orig_video_bitrate%.*}
	elif [ "$orig_video_bitrate" != "${orig_video_bitrate%Mb/s}" ]; then
		orig_video_bitrate=${orig_video_bitrate%Mb/s}
		orig_video_bitrate=${orig_video_bitrate%.*}
		orig_video_bitrate=$((orig_video_bitrate*1000))
	fi
	if [[ "$orig_video_bitrate" =~ ^[0-9]+$ ]]; then
		orig_video_bitrate_bits=$((orig_video_bitrate*1000))
	else
		#  Unlike with the resolution, original bitrate
		#  is of less importance, as the source will most likely
		#  have bigger bit rate, and no bad things will happen
		#  from wasting (limited) space on quality.
		no_orig_video_bitrate=t
	fi

	# There are three sources for subtitles:
	# - default subtitle track (if any present at all), ffmpeg’s -map 0:s:0?;
	# - an external file, specified in the “subs” parameter
	#   in the command line as subs=/path/to/external/file;
	# - an internal subtitle track, but not the default one: it’s specified
	#   through the command line as well, as subs:5 for example.
	[ -v subs ] && check_subtitles && prepare_subtitles

	[ -v audio ] && check_audio_track && prepare_audio_track


	# Original resolution is a prerequisite for the intelligent mode.
	#   Dumb mode with some hardcoded default bitrates bears
	#   little usefulness, so it was decided to flex it out.
	#   Intelligent and forced modes (that overrides things in the former)
	#   are the two modes now.
	# Getting native video resolution is of utmost importance
	#   to not do accidental upscale. It is also needed for knowing,
	#   with which resolution to start scaling down, if needed.
	orig_width=$(get_ffmpeg_attribute "$video" v width)
	orig_height=$(get_ffmpeg_attribute "$video" v height)
	if [[ "$orig_width" =~ ^[0-9]+$ && "$orig_height" =~ ^[0-9]+$ ]]; then
		have_orig_res=t
	else
		#  Files in which native resolution could not be obtained,
		#  haven’t been met in the wild, but let’s try a different
		#  way of obtaining it.
		orig_width=$(get_mediainfo_attribute "$video" v Width)
		orig_width="${orig_width%pixels}"
		orig_height=$(get_mediainfo_attribute "$video" v Height)
		orig_height="${orig_height%pixels}"
		[[ "$orig_width" =~ ^[0-9]+$ && "$orig_height" =~ ^[0-9]+$ ]] \
			&& have_orig_res=t
	fi
	[ -v have_orig_res ] || err "Cannot determine source video resolution."

	[ -v have_orig_res ] && orig_res_total_px=$(( orig_width * orig_height ))
	#  Since the values in our bitrate–resolution profiles are given
	#  for 16:9 aspect ratio, 4:3 video and special ones like 1920×820
	#  would require less  bitrate, as there’s less pixels.
	orig_ar=$(get_mediainfo_attribute "$video" v 'Display aspect ratio')
	[[ "$orig_ar" =~ ^[0-9\.]+:[0-9\.]+$ ]] || {
		#  Calculating it by orig_res
		if [ -v have_orig_res ]; then
			if  is_16_9=$(
					echo "scale=5; (16/9) == ($orig_width/$orig_height)" | bc
				)
			then
				case "$is_16_9" in
					0)  orig_ar='not 16:9'
						;;
					1)  orig_ar='16:9'
						;;
				esac
			else
				warn "Couldn’t calculate source video aspect ratio.
				      Will assume 16:9 bitrate standards."
				unset orig_ar
			fi
		else
			#  Let the original aspect ratio be undefined.
			unset orig_ar
		fi
	}
	[ -v orig_ar ] && [ "$orig_ar" != '16:9' ] \
		&& needs_bitrate_correction_by_origres=t

	[ -v have_orig_res ] && {
		#  Videos with nonstandard resolutions must be associated
		#    with a higher profile.
		#  [ -v doesn’t work here, somehow O_o
		declare -p bitres_profile_${orig_height}p  &>/dev/null  || {
			for ((i=${#known_res_list[@]}-1; i>0; i--)); do
				[ $orig_height -gt ${known_res_list[i]} ] && continue || break
			done
			[ $i -eq -1 ] && ((i++, 1))  # sic!
			closest_res=${known_res_list[i]}
			needs_bitrate_correction_by_origres=t
		}
	}

	[ -v crop  -a  ! -v crop_uses_profile_vbitrate ] \
		&& needs_bitrate_correction_by_cropres=t

	[ -v scale ] && [ $scale -eq $orig_height ] && {
		warn "Disabling scale to ${scale}p – it is the native resolution."
		unset scale
	}
	[ -v scale ] && [ $scale -gt $orig_height ] && {
		warn "Disabling scale to ${scale}p – would be an upscale."
		unset scale
	}

	orig_format=$(get_mediainfo_attribute "$video" v 'Format')
	codec_format=${codec_names_as_formats[$ffmpeg_vcodec]}
	[ "$orig_format" = "$codec_format" ] && orig_codec_same_as_enc=t

	closest_lowres_index=0
	for ((i=0; i<${#known_res_list[@]}; i++ )); do
		# If a profile resolution is greater than or equal
		#   to the source video height, such resolution isn’t
		#   actually lower, and we don’t need upscales.
		# If we intend to scale down the source and the desired
		#   resolution if higher than the table resolution,
		#   again, it should be skipped.
		(
			[ -v orig_height ] && [ ${known_res_list[i]} -ge $orig_height ]
		)||(
			[ -v scale ] && [ ${known_res_list[i]} -gt $scale ]
		) \
		&& ((closest_lowres_index++, 1))
	done

	 # If any of these variables are set by this time,
	#  they force (fixate) corresponding settings.
	[ -v vbitrate ] && forced_vbitrate=t
	[ -v abitrate ] && forced_abitrate=t
	# scale is special, it can be set in RC file.
	[ -v scale  -a  ! -v rc_default_scale ] && forced_scale=t

	[ -v scene_complexity ] \
		|| determine_scene_complexity "$video" \
		                              "${start[ts]}" \
		                              "${duration[total_s_ms]}" \
		                              "${duration[total_s]}"
	[ "$scene_complexity" = dynamic ] && bitrates_locked_on_desired=t

	return 0
}


 # Prints the initial settings to the user.
#  This output combines the data from the RC file, the command line,
#  and the source video. No decision how to fit the clip in the constraints
#  has been made yet.
#
display_settings() {
	local sub_hl  audio_hl  crop_string  sub_hl  audio_hl
	# The colours for all the output should be:
	# - default colour for default/computed/retrieved data;
	# - bright white colour indicates command line overrides;
	# - bright yellow colour shows the changes, that the code applied itself.
	#   This includes lowering bitrates for 4:3 videos, going downscale,
	#   when the size doesn’t allow for encode at the native resolution etc.
	info 'Requested settings:' && milinc
	info "$ffmpeg_vcodec + $ffmpeg_acodec → $container"
	# Highlight only overrides of the defaults.
	# The defaults are defined in $rc_file.
	[ -v rc_default_subs -a -v subs ] \
		&& sub_hl="${__g}" \
		|| sub_hl="${__b}"
	[ -v subs ] \
		&& info "Subtitles are ${sub_hl}ON${__s}." \
		|| info "Subtitles are ${sub_hl}OFF${__s}."
	[ -v rc_default_audio -a -v audio ] \
		&& audio_hl="${__g}" \
		|| audio_hl="${__b}"
	[ -v audio ] \
		&& info "Audio is ${audio_hl}ON${__s}." \
		|| info "Audio is ${audio_hl}OFF${__s}."
	[ -v scale ] && {
		[ "${rc_default_scale:-}" != "${scale:-}" ] && scale_hl=${__b}
		info "Scaling to ${scale_hl:-}${scale}p${__s}."
	}
	[ -v crop ] && {
		crop_string="${__b}$crop_w×$crop_h${__s}, X:$crop_x, Y:$crop_y"
		info "Cropping to: $crop_string."
	}
	[ "$max_size" = "$max_size_default" ] \
		&& info "Size to fit into: $max_size (kilo=$kilo)." \
		|| info "Size to fit into: ${__b}$max_size${__s} (kilo=$kilo)."
	info "Slice duration: ${duration[ts_short_no_ms]} (exactly ${duration[total_s_ms]})."

	mildec
	info 'Source video:'
	milinc

	[ -v have_orig_res ] \
		&& info "Resolution: $orig_width×$orig_height." \
		|| warn "Resolution: ${__y}–${__s}."
	case "${orig_ar:-}" in
		'')  warn "Aspect ratio: ${__b}${__y}undefined${__s}";;
		'16:9')  info "Aspect ratio: 16:9.";;
		*)  info "Aspect ratio: ${__y}not 16:9${__s}.";;
	esac
	[ -v no_orig_video_bitrate ] \
		&& warn "Bit rate: ${__y}unknown${__s}." \
		|| info "Bit rate: $orig_video_bitrate kbps."
	if [ -v scene_complexity_assumed ]; then
		warn "Scene complexity: assumed to be $scene_complexity."
	else
		[ -v forced_scene_complexity ] \
			&& info "Scene complexity: ${__b}$scene_complexity${__s}." \
			|| info "Scene complexity: $scene_complexity."
	fi
	milinc
	[ "$scene_complexity" = dynamic ] \
		&& info "Locking video bitrates on desired values."
	#  Not set if scene_complexity is forced.
	[ -v sps_ratio ] && info "SPS ratio: $sps_ratio."
	mildec 2
	[ "$ffmpeg_pix_fmt" != "yuv420p" ] \
		&& info "Encoding to pixel format “${__b}$ffmpeg_pix_fmt${__s}”."
	[ -v ffmpeg_colorspace ] \
		&& info "Converting to colourspace “${__b}$ffmpeg_colorspace${__s}”."
	[    -v needs_bitrate_correction_by_origres \
	  -o -v needs_bitrate_correction_by_cropres ] && {
	  	infon 'Bitrate corrections to be applied: '
		[ -v needs_bitrate_correction_by_origres ] \
			&& echo -en "by ${__y}${__b}orig_res${__s} "
		[ -v needs_bitrate_correction_by_cropres ] \
			&& echo -en "by ${__y}${__b}crop_res${__s} "
		echo
	}
	return 0
}


return 0