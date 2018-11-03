#! /usr/bin/env bash

#  mpv_crop_script_installer.sh
#  Helper script, that installs mpv_crop_script.lua by TheAMM.
#  deterenkelt © 2018
#
#  For licence see nadeshiko.sh
#  mpv_crop_script.lua is licensed under GPL v3.

set -feEuT
. "$(dirname "$0")/bahelite/bahelite.sh"
prepare_cachedir 'nadeshiko'
start_log


#  Nadeshiko-mpv passes mpv config directory as the first parameter.
[ "${1:-}" ] && [ -d "$1" ] && mpv_confdir="$1"

latest_release_url="https://github.com/TheAMM/mpv_crop_script/releases/latest"
#  If mpv config directory was not passed with $1, try to determine
#  the directory.
set_mpv_confdir_paths() {
	declare -g mpv_confdir
	if [ -v MPV_HOME ] && [ -r "$MPV_HOME/config" ]; then
		mpv_confdir="$MPV_HOME"
	elif [ -v XDG_CONFIG_HOME ] && [ -r "$XDG_CONFIG_HOME/mpv/config" ]; then
		mpv_confdir="$XDG_CONFIG_HOME/mpv/"
	elif [ -r "$HOME/.config/mpv/config" ]; then
		mpv_confdir="$HOME/.config/mpv"
	elif [ -r "$HOME/.mpv/config" ]; then
		mpv_confdir="$HOME/.mpv"
	else
		err "Cannot determine mpv config directory."
	fi

	#  set script dir to ./scripts.
	#
	#  set path to crop tool
	# croptool="$mpv_confdir/scripts/mpv_crop_script.lua"
	#
	#  set scripts-opts dir to ./script-opts or lua-settings.
	#
	#  set path to crop tool config
	# croptool_config="$mpv_confdir/lua-settings/mpv_crop_script.conf"
	return 0
}
[ ! -v mpv_confdir ] && set_mpv_confdir_paths

#  Getting URL to the latest crop script.
lr_page=$( wget -O- "$latest_release_url" )
lr_script_href=$( sed -rn 's/^\s*<a\shref="(.*\.lua)".*$/\1/p'  <<<"$lr_page" )
[[ "$lr_script_href" =~ ^/TheAMM.*\.lua$ ]] \
	|| err 'Couldn’t retrieve the URL to the latest version.'
lr_script_name="${lr_script_href##*/}"
lr_script_url="https://github.com$lr_script_href"


confdir_luafile="$mpv_confdir/scripts/$lr_script_name"
[ -r "$confdir_luafile" ] \
	&& err "$lr_script_name is already installed! Aborting."


tmp_luafile="$TMPDIR/${lr_script_url##*/}"

#  Downloading crop script.
wget -O- "$lr_script_url"  >"$tmp_luafile"
[ -r "$tmp_luafile" ] || err 'Couldn’t download crop script.'

tmp_luafile_mime=$(file --mime-type -b "$tmp_luafile")
[[ "$tmp_luafile_mime" =~ ^text/x-lua$ ]] \
	|| err 'Downloaded file is not a Lua script.'

#  Copying crop script.
[ -d "$mpv_confdir/scripts" ] || mkdir "$mpv_confdir/scripts"
cp "$tmp_luafile" "$confdir_luafile"

#  Setting up config directory.
[ -d "$mpv_confdir/lua-settings" ] || mkdir "$mpv_confdir/lua-settings"


exit 0


#  Setting up the config
#  This is only for testing how the script works by itself,
#    in normal use the script will already quit.
#  Nadeshiko-mpv backs up the config and places a temporary one –
#    users will have their own config untouched.
luafile_own_config="$mpv_confdir/lua-settings/mpv_crop_script.conf"
[ -r "$luafile_own_config" ] \
	&& err "Crop script config file already exists! Aborting."
cat <<"EOF"  >"$luafile_own_config"
output_template=/tmp/crop=${crop_w}:${crop_h}:${crop_x}:${crop_y}.jpg
create_directories=no
keep_original=no
disable_keybind=yes
EOF


exit 0