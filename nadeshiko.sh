#! /usr/bin/env bash

#  nadeshiko.sh
#  A Linux tool to cut small videos with ffmpeg.
#  deterenkelt © 2018

 # This program is free software; you can redistribute it and/or modify it
#    under the terms of the GNU General Public License as published
#    by the Free Software Foundation; either version 3 of the License,
#    or (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#    but without any warranty; without even the implied warranty
#    of merchantability or fitness for a particular purpose.
#    See the GNU General Public License for more details.


set -feEuT
shopt -s extglob
#  Logging, error handling, messages to console and desktop.
. "$(dirname "$(realpath "$0")")/lib/bahelite/bahelite.sh"
prepare_cachedir
start_log
set +f
rm -f "$LOGDIR/"ffmpeg*  "$LOGDIR/"mkvextract*  "$LOGDIR/time_output"
set -f
set_libdir
#  For parsing ffprobe and mediainfo output into usable format.
. "$LIBDIR/gather_file_info.sh"
#  For manipulating timestamp forms.
. "$LIBDIR/time_functions.sh"
set_modulesdir
set +f
for module in "$MODULESDIR"/nadeshiko_*.sh ; do
	. "$module" || err "Couldn’t source module $module."
done
set -f
set_exampleconfdir
prepare_confdir

declare -r version='2.3.3'
info "Nadeshiko v$version" >>"$LOG"
declare -r release_notes_url="http://github.com/deterenkelt/Nadeshiko/blob/master/RELEASE_NOTES"
declare -r rcfile_minver='2.0.1'
#  [0]=ffmpeg own full version (not compared, because it may be a commit hash)
#  [1]=libavutil version
#  [2]=libavcodec version
#  [3]=libavformat version
declare -r ffmpeg_minver=( 'any' 55 57 57 )
declare where_to_place_new_file="$PWD"
#  Defining them here, so that the definition in the RC file would be shorter
#  and didn’t confuse users with “declare -gA …”.
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
RCFILE_BOOLEAN_VARS+=(
	desktop_notifications
	check_for_updates
	subs
	audio
	scale
	pedantic
	time_stat
	crop_uses_profile_vbitrate
	create_windows_friendly_filenames
)


show_help() {
	cat <<-EOF
	Usage
	./nadeshiko.sh  [start_time] [stop_time] [<other options>] <source_video>

	The order of options is free.

	       source_video – Path to the source video file.
	         start_time – Time on which clip should start.
	          stop_time – Time on which it should end.
	                      Any time format is valid:
	                      11:23:45.670   =  11 h 23 min 45 s 670 ms
	                         23:45.1     =  23 min 45 s 100 ms
	                           125.340   =  2 min  5 s 340 ms
	                             5       =  5 s
	                      Padding zeroes aren’t required.

	           (no)subs – enable/disable burning subtitles into video,
	                      also called hardsubbing. The default is to burn.
	          (no)audio – use/throw away audio track.
	                      The default is to add.
	         si, k=1000 – when converting [kMG] suffixes, use SI units.
	                      (Use it, if uploading limit is set in MB, not MiB).
	          <height>p – force encoding to the bitres profile for this height.
	                      Requesting upscale will result in an error.
	     tiny | small | – override the default maximum file size ($max_size_default).
	 normal | unlimited   Values must be set in nadeshiko.rc.sh beforehand.
	                      Default presets are: normal=$max_size_normal, small=$max_size_small, tiny=$max_size_tiny.
	    vb<number>[kMG] – force encoding with this exact video bitrate.
	                      A suffix may be applied: vb300000, vb1200k, vb2M.
	      ab<number>[k] – force encoding with this exact audio bitrate.
	                      Example: ab128000, ab192k, ab88k.
	       crop=W:H:X:Y – crop video. Cannot be used together with scaling.
	           <folder> – place encoded file into <folder>.
	           <config> – alternate config file to use.
	                      Must be a file in $CONFDIR
	                      The filename must end with “.rc.sh”
	 fname_pfx=<string> – A custom string to be added to the name of the
	                      encoded file. Will be put at the beginning.


	Option descriptions are shortened for convenience,
	see the full version in the wiki: https://git.io/fx8DV

	Post bugs here: https://github.com/deterenkelt/Nadeshiko/issues
	EOF
	exit 0
}


show_version() {
	cat <<-EOF
	nadeshiko.sh $version
	© deterenkelt 2018.
	Licence: GNU GPL version 3  <http://gnu.org/licenses/gpl.html>
	This is free software: you are free to change and redistribute it.
	There is no warranty, to the extent permitted by law.
	EOF
	exit 0
}



#  Stage 1
set_rcfile_from_args "$@"
read_rcfile  "$rcfile_minver"
post_read_rcfile
[ -v check_for_updates ] && check_for_new_release_on_github
#  Stage 2
parse_args "${args[@]}"
check_util_support video ${audio:+audio} ${subs:+subs} ${time_stat:+time_stat}
set_vars
display_settings
until [ -v size_fits ]; do
	#  Stage 3
	fit_bitrate_to_filesize
	#  Stage 4
	encode
	new_file_size_in_bytes=$(stat --printf %s "$new_file_name")
	[ $new_file_size_in_bytes -le $max_size_in_bytes ] \
	    && size_fits=t \
	    || on_size_overshoot
done
info-ns "Encoded successfully."
new_file_name=${new_file_name//\$/\\\$}
info "${new_file_name##*/}"
[ -v time_stat ] && print_stats
which xclip &>/dev/null && {
	# trapondebug unset
	echo -n "$new_file_name" | xclip
	# trapondebug set
	info 'Copied path to clipboard.'
}
# [ -v pedantic ] && comme_il_faut_check "$new_file_name"  # needs update

exit 0