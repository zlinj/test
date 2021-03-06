#!/bin/sh

keypath="/base/audio/codec/mic_volume_adjust"
ucm_params="-c audiocodec -v Record"

volume_adjust_step=$(mjson_fetch "${keypath}/volume_adjust_step")
volume_adjust_interval_sec=$(mjson_fetch "${keypath}/volume_adjust_interval_sec")
capture_channels=$(mjson_fetch "${keypath}/capture_channels")
capture_format=$(mjson_fetch "${keypath}/capture_format")
capture_rate=$(mjson_fetch "${keypath}/capture_rate")
capture_duration_sec=$(mjson_fetch "${keypath}/capture_duration_sec")
records_dir=$(mjson_fetch "${keypath}/records_dir")
remove_records=$(mjson_fetch "${keypath}/remove_records")
playback_volume=$(mjson_fetch "${keypath}/playback_volume")

if [ ! -d "$records_dir" ]; then
    mkdir -p "$records_dir"
    created_dir="$records_dir"
fi

mic_number=$(alsa-ucm-aw $ucm_params get MicNumber 2>/dev/null)
if [ $? -ne "0" ]; then
    mic_number=1
    mic_names="Mic"
else
    mic_names="$(alsa-ucm-aw $ucm_params get MicNames)"
fi

# $1: UCM device name
# $2: capture PCM device name
capture_adjust_volume() {
    is_increase=1
    volume=$(alsa-ucm-aw $ucm_params -d "$1" -r getvol)
    volume_min=$(alsa-ucm-aw $ucm_params -d "$1" get CaptureVolumeMin)
    volume_max=$(alsa-ucm-aw $ucm_params -d "$1" get CaptureVolumeMax)

    record="${records_dir}/record_${1}.wav"
    ttips "Start recording with \"$1\" (in $capture_duration_sec seconds)"
    arecord -D "$2" -c "$capture_channels" -f "$capture_format" \
        -r "$capture_rate" -d "$capture_duration_sec" "$record" -q &

    while true; do
        if [ $is_increase -eq "1" ]; then
            volume=$(expr $volume + $volume_adjust_step)
            if [ $volume -ge $volume_max ]; then
                volume=$volume_max
                is_increase=0
            fi
        else
            volume=$(expr $volume - $volume_adjust_step)
            if [ $volume -le $volume_min ]; then
                volume=$volume_min
                is_increase=1
            fi
        fi
        alsa-ucm-aw $ucm_params -d "$1" -r setvol $volume
        ttips "Current volume: $volume"
        background=$(jobs)
        background=$(echo "$background" | grep "Running")
        if [ "x$background" == "x" ]; then
            break
        fi
        sleep $volume_adjust_interval_sec
    done
}

ttrue "Is the playback device (e.g. headphone, speaker, etc.) ready?"
if [ $? -ne "0" ]; then
    ttips "ERROR: playback device is not ready"
    exit 1
fi
alsa-ucm-aw -p enable
alsa-ucm-aw -p setvol $playback_volume
playback_pcm_device=$(alsa-ucm-aw -p get Card)

exit_code=0
result="Result:"
for i in $mic_names; do
    alsa-ucm-aw $ucm_params -d "$i" enable
    if [ $? -ne "0" ]; then
        ttips "Failed to enable the UCM device \"$i\""
        continue
    fi
    pcm_device=$(alsa-ucm-aw $ucm_params -d "$i" get CapturePCM)
    if [ $? -ne "0" ]; then
        ttips "Failed to get the \"CapturePCM\" of \"$i\""
        continue
    fi

    capture_adjust_volume "$i" "$pcm_device"

    ttips "Finish recording, and start playing the record of \"$i\""
    aplay -D "$playback_pcm_device" "$record" -q
    ttrue "Finish playing. Does \"$i\" volume adjustment work well?"
    if [ $? -eq "0" ]; then
        result=${result}" -n ${i}: PASS"
    else
        result=${result}" -n ${i}: FAIL"
        exit_code=1
    fi
    if [ "x$remove_records" == "xtrue" ]; then
        rm -f "$record"
    fi
    alsa-ucm-aw $ucm_params -d "$i" disable
done

alsa-ucm-aw -p disable

if [ "x$remove_records" == "xtrue" -a "x$created_dir" != "x" ]; then
    if [ "x$(ls -A $created_dir)" == "x" ]; then
        rm -r "$created_dir"
    fi
fi

ttips $result
exit $exit_code
