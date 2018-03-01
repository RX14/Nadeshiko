# nadeshiko.rc.sh

 # Default values
#
# Output container.
container=mp4
#
# Output size. kMG suffixes use powers of 2, unless $kilo is set to 1000.
max_size=20M
#
# Video bitrate, in kbit/s.
# In “dumb” mode serves as a lower border, beyond which Nadeshiko
# will refuse to encode.
vbitrate=1500k
#
# Audio bitrate, in kbit/s. CBR.
abitrate=98k
#
#  Multiplier for max_size “k” “M” “G” suffixes. Can be 1024 or 1000.
#  Reducing this value may solve the problem with videos not uploading,
#  because file size limit uses powers of 10 (10, 100, 1000…)
kilo=1024
#
# Space in bits required for container metadata.
# Currently set to 0, because ffmpeg fits everything nicely
# to whatever is in $max_size.
container_own_size=0
#
# “small” command line parameter to override max_size
video_size_small=10M
#
# “tiny” command line parameter to override max_size
video_size_tiny=2M


 # Encoder options
#
#   FFmpeg binary.
ffmpeg='ffmpeg -hide_banner -v error'
#
#   Chroma subsampling.
#   Browsers do not support yuv444p yet.
ffmpeg_pix_fmt='yuv420p'
#
#  Video codec.
#  Browsers do not support libx265 yet.
ffmpeg_vcodec='libx264'
#
#  Video codec preset.
#  “veryslow” > “slow”. “medium” and lower make visible artifacts.
ffmpeg_preset='veryslow'
#
#   Video codec preset tune.
#   “film” > “animation”.
ffmpeg_tune='film'
#
#   Video codec profile.
#   Browsers do not support high10 or high444p
ffmpeg_profile='high'
#
#   Video codec profile level.
#   Higher profiles optimise bitrate better.
#   Old devices, that you don’t need to care about,
#   may require something more old, like 4.2 or 3.0.
ffmpeg_level='6.2'
#
#   Audio codec.
#   If you don’t have libfdk_aac, use either “libvorbis” or “aac″.
ffmpeg_acodec='aac'


 # The following lines describe bitrate-resolution profiles.
#  Desired bitrate is the one that we aim to have, and the minimal one
#  is the lowest on which we agree /with this resolution/.
#
#  To find the balance between resolution and quality,
#  nadeshiko.sh offers three modes:
#  - dumb mode: use default values of max_size and abitrate, ignore vbitrate
#    and fit as much video bitrate as max_size allows.
#  - intelligent mode: operates on desired and minimal bitrate,
#    can lower resolution to preserve more quality. Requires the table
#    of resolutions and bitrates to be present (it is found right below),
#  - forced mode: this mode is set by the commandline options, that force
#    scale and bitrates for audio/video.
#    forced > intelligent > dumb
#
video_360p_desired_bitrate=500k
video_360p_minimal_bitrate=220k
audio_360p_bitrate=98k
#
video_480p_desired_bitrate=1000k
video_480p_minimal_bitrate=400k
audio_480p_bitrate=128k
#
video_576p_desired_bitrate=1500k
video_576p_minimal_bitrate=720k
audio_576p_bitrate=128k
#
video_720p_desired_bitrate=2000k
video_720p_minimal_bitrate=800k
audio_720p_bitrate=128k
#
video_1080p_desired_bitrate=3500k
video_1080p_minimal_bitrate=1500k
audio_1080p_bitrate=128k