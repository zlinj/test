#!/bin/ash

###########################################################
# Before do standby, reboot first
# If call standby on tinatest by adb, this script will do
# standby without any log or tinatest will go wrong.
# To fix it, I set this test as may_reboot, and set
# run_times to 2, which enable reboot before do standby test.
# By this, this will reboot in first time and do standby
# test in next time
may_reboot=$(mjson_fetch ${testcase_path}/may_reboot)
if [ "$may_reboot" = "true" ]
then
    REBOOT_STATUS="/mnt/UDISK/tinatest.reboot.status"
    [ -f "${REBOOT_STATUS}" ] && \
        [ "$(head -n 1 ${REBOOT_STATUS})" == "0" ] && reboot -f
fi
###########################################################

SCENE_CHOOSE=$1

testcase_path="/stress/standby"
# TEST_ROUNDS - counts of test round
TEST_ROUNDS=`mjson_fetch ${testcase_path}/test_rounds`
# STANDBY_PERIOD_TABLE - standby duration lookup table
STANDBY_PERIOD_TABLE=`mjson_fetch ${testcase_path}/standby_period_table`
# RUNNING_PERIOD_TABLE - running duration lookup table
RUNNING_PERIOD_TABLE=`mjson_fetch ${testcase_path}/running_period_table`
# times of standby & resume each case
TIMES_EACH_CASE=`mjson_fetch ${testcase_path}/times_each_case`

TARGET=$(get_target)
echo =========The platform is : $TARGET=========
case $TARGET in
	sitar-* | banjo-*)
		STANDBY_TYPE="normal_standby"
		;;
	astar-*)
		STANDBY_TYPE="earlysuspend"
		;;
	azalea-* | tulip-* | koto_*)
		STANDBY_TYPE="super_standby"
		;;
	*)
		STANDBY_TYPE="super_standby"
		;;
esac


help_info()
{
	echo ""
	echo "*****************************************************************"
	echo "Four input parameters:"
	echo "1. counts of test round : Rounds"
	echo "   TEST_ROUNDS          = $TEST_ROUNDS"
	echo "2. standby period       : [S1 S2 ... Sm]"
	echo "   STANDBY_PERIOD_TABLE = [$STANDBY_PERIOD_TABLE]"
	echo "3. running period       : [R1 R2 ... Rn]"
	echo "   RUNNING_PERIOD_TABLE = [$RUNNING_PERIOD_TABLE]"
	echo "4. times each case      : Times"
	echo "   TIMES_EACH_CASE      = $TIMES_EACH_CASE"

	standby_period_sum=0
	running_period_sum=0
	standby_period_num=`echo $STANDBY_PERIOD_TABLE | awk '{print NF}'`
	running_period_num=`echo $RUNNING_PERIOD_TABLE | awk '{print NF}'`
	for standby_period in $STANDBY_PERIOD_TABLE; do
		standby_period_sum=$(busybox expr $standby_period_sum + $standby_period)
	done
	for running_period in $RUNNING_PERIOD_TABLE; do
		running_period_sum=$(busybox expr $running_period_sum + $running_period)
	done

	total_time=$(busybox expr $TEST_ROUNDS \* \( $running_period_num \* $standby_period_sum + $standby_period_num \* $running_period_sum \) \* $TIMES_EACH_CASE)
	total_times=$(busybox expr $TEST_ROUNDS \* $standby_period_num \* $running_period_num \* $TIMES_EACH_CASE)

	echo ""
	echo "The whole test will need time (second):"
	echo "   Rounds * [ (S1+S2+...+Sm) * n + (R1+R2+...+Rn) * m ] * Times"
	echo "   ------$total_time------"
	echo ""
	echo "The whole test will standby-resume times:"
	echo "   Rounds * m * n * Times"
	echo "   ------$total_times------"
	echo "*****************************************************************"
	echo ""
}

set_env()
{
	echo none >/sys/power/pm_test

	echo "setting console suspend setting value to : "
	backup_console_suspend=$(cat /sys/module/printk/parameters/console_suspend)
	echo N > /sys/module/printk/parameters/console_suspend
	cat /sys/module/printk/parameters/console_suspend
	echo backup_console_suspend equal = $backup_console_suspend

	echo "setting initcall_debug setting value to : "
	backup_initcall_debug=$(cat /sys/module/kernel/parameters/initcall_debug)
	echo Y > /sys/module/kernel/parameters/initcall_debug
	cat /sys/module/kernel/parameters/initcall_debug
	echo backup_initcall_debug = $backup_initcall_debug

	echo "setting loglevel setting value to:  "
	backup_loglevel=$(cat /proc/sys/kernel/printk)
	echo 8 > /proc/sys/kernel/printk
	cat /proc/sys/kernel/printk
	echo backup_loglevel = $backup_loglevel

	backup_time_to_wakeup=$(cat /sys/module/pm_tmp/parameters/time_to_wakeup)
	echo "backup_time_to_wakeup = $backup_time_to_wakeup "

:<<BLOCK
	echo start memster
	memtester 100M  &
	memtester 100M  &
	PID1=$!
	echo pid = $PID1
	memtester 50M >>/dev/null &
	PID2=$!
	echo pid = $PID2
	memtester 50M >>/dev/null &
	PID3=$!
	echo pid = $PID3
	memtester 100M >>/dev/null &
	PID4=$!
	echo pid = $PID4
	memtester 150M  &
	memtester 50M  &
	memtester 50M  &
	memtester 50M  &
BLOCK

	if [ -f /sys/devices/platform/sunxi-arisc/debug_mask ]; then
		echo "setting arisc debug_mask setting value to : "
		backup_arisc_debug=$(cat /sys/devices/platform/sunxi-arisc/debug_mask)
		echo 2 > /sys/devices/platform/sunxi-arisc/debug_mask
		cat /sys/devices/platform/sunxi-arisc/debug_mask
		echo backup_arisc_debug = $backup_arisc_debug
	fi

	# sync from DTS memory node.
	if [ "x$TARGET" == "xcello-perf1" -o "x$TARGET" == "xcello-pro" ]; then
		echo "setting for dram crc: 0x40000000 0x4000000"
		echo 1 0x40000000 0x4000000 > /sys/power/aw_ex_standby/dram_crc_paras
		cat /sys/power/aw_ex_standby/dram_crc_paras
	fi

	if [ -f /sys/power/scene_lock ]; then
		echo "backup scene_lock: "
		backup_scene_lock=`cat /sys/power/scene_lock | awk -vRS="]" -vFS="[" '{print $2}'`
		echo backup_scene_lock = $backup_scene_lock
	fi
}

restore_env()
{
	if [ -f /sys/power/scene_lock ]; then
		echo "restore scene_lock. "
		for scene in $backup_scene_lock; do
			echo $scene > /sys/power/scene_lock
		done
		cat /sys/power/scene_lock
	fi

	if [ -f /sys/devices/platform/sunxi-arisc/debug_mask ]; then
		echo "restore arisc debug_mask setting value. "
		echo $backup_arisc_debug > /sys/devices/platform/sunxi-arisc/debug_mask
		cat /sys/devices/platform/sunxi-arisc/debug_mask
	fi

	echo "restore console suspend setting value. "
	echo $backup_console_suspend > /sys/module/printk/parameters/console_suspend
	cat /sys/module/printk/parameters/console_suspend

	echo "restore initcall_debug setting value."
	echo $backup_initcall_debug > /sys/module/kernel/parameters/initcall_debug
	cat /sys/module/kernel/parameters/initcall_debug

	echo "restore loglevel setting value. "
	echo $backup_loglevel > /proc/sys/kernel/printk
	cat /proc/sys/kernel/printk

	echo "restore the system auto wakeup para. "
	echo $backup_time_to_wakeup > /sys/module/pm_tmp/parameters/time_to_wakeup
	cat /sys/module/pm_tmp/parameters/time_to_wakeup

:<<BLOCK
	echo " kill memtest. "
	kill $PID1
	kill $PID2
	kill $PID3
	kill $PID4
BLOCK
}

set_auto_wakeup()
{
	case $TARGET in
		banjo-*)
			time_to_wakeup=$(busybox expr $1 \* 1000)
			echo Y > /sys/module/printk/parameters/console_suspend
			;;
		      *)
			if [ -f /sys/class/rtc/rtc0/wakealarm ]; then
				echo 0 > /sys/class/rtc/rtc0/wakealarm
				echo "+$1" > /sys/class/rtc/rtc0/wakealarm
				wakeup_time=`cat /sys/class/rtc/rtc0/wakealarm`
				return 0
			fi
			time_to_wakeup=$1
			;;
	esac

	echo "time_to_wakeup = $time_to_wakeup"
	echo $time_to_wakeup > /sys/module/pm_tmp/parameters/time_to_wakeup
	cat /sys/module/pm_tmp/parameters/time_to_wakeup
}

clear_all_scene_lock()
{
	if [ -f /sys/power/scene_unlock ]; then
		scene_lock_valid=`cat /sys/power/scene_lock | awk -vRS="]" -vFS="[" '{print $2}'`
		if [ "x$scene_lock_valid" != "x" ]; then
			for scene_tmp in $scene_lock_valid; do
				echo $scene_tmp >/sys/power/scene_unlock
			done
		fi
	fi
}

clear_all_wake_lock()
{
	if [ -f /sys/power/wake_lock ]; then
		wake_lock_valid=`cat /sys/power/wake_lock`
		if [ "x$wake_lock_valid" != "x" ]; then
			for wake_lock_tmp in $wake_lock_valid; do
				echo $wake_lock_tmp > /sys/power/wake_unlock
			done
		fi
	fi
}

enter_standby()
{
	echo mem > /sys/power/state
}

#===================================main function===============================
#just for tips.
help_info

echo "++++++++++++++++++ set env ++++++++++++++++++"
set_env

i=1
j=0
while [ $i -le $TEST_ROUNDS ] ; do
	echo "================================================================="
	echo "Begin: rounds No.$i !"

	for STANDBY_PERIOD in $STANDBY_PERIOD_TABLE ; do
		for RUNNING_PERIOD in $RUNNING_PERIOD_TABLE ; do
			t=1
			while [ $t -le $TIMES_EACH_CASE ] ; do
				TYPE=$STANDBY_TYPE
				j=$(busybox expr $j + 1)

				echo "========================================="
				echo "Begin: standby-resume times No.$j !"
				echo "TYPE == $TYPE"
				echo "STANDBY_PERIOD == $STANDBY_PERIOD"
				echo "RUNNING_PERIOD == $RUNNING_PERIOD"
				echo ""
				echo "--------------- start"

				# Set standby type: normal, super or earlysuspend
				if [ -f /sys/power/scene_lock ]; then
					grep $TYPE /sys/power/scene_lock > /dev/null
					if [ $? -eq 0 ]; then
						clear_all_scene_lock
						echo $TYPE > /sys/power/scene_lock
						echo "set scene lock: $TYPE"
					fi
				fi

				# running time
				echo "running $RUNNING_PERIOD seconds."
				if [ -f /sys/class/rtc/rtc0/time ]; then
					cat /sys/class/rtc/rtc0/time
				fi
				sleep $RUNNING_PERIOD
				if [ -f /sys/class/rtc/rtc0/time ]; then
					cat /sys/class/rtc/rtc0/time
				fi
				echo "running $RUNNING_PERIOD seconds done."

				# set standby period
				set_auto_wakeup $STANDBY_PERIOD

				# for earlysuspend, remove the wake_tmp wake lock.
				if [ "x$TYPE" == "xearlysuspend" ]; then
					if [ -f /sys/power/wake_unlock ]; then
						grep wake_tmp /sys/power/wake_lock > /dev/null
						if [ $? -eq 0 ]; then
							echo wake_tmp > /sys/power/wake_unlock
						fi
						# clear all wake_lock before entering standby
						clear_all_wake_lock
					fi
				fi

				# enter standby
				echo "=========enter standby========="
				enter_standby
				echo "=========exit  standby========="

				# for earlysuspend, enter_standby is non-blocking, so we must ensure:
				# 1. It must have entered standby.
				# 2. Preventing the system from entering standby again after it resumed.
				if [ "x$TYPE" == "xearlysuspend" ]; then
					if [ -f /sys/power/wake_lock ]; then
						time_now=`date +%s`

						while [ "$time_now" -le "$wakeup_time" ]; do
							time_now=`date +%s`
						done

						echo "time_now is $time_now, wakeup_time is $wakeup_time"
						echo wake_tmp > /sys/power/wake_lock
					fi
				fi

				echo "---------- resume ok!"
				echo ""
				echo "Success: standby-resume times No.$j !"
				echo "========================================="
				echo ""

				t=$(busybox expr $t + 1)
			done
		done
	done

	echo "Success: rounds No.$i !"
	echo "================================================================="
	echo ""

	i=$(busybox expr $i + 1)
done

echo "++++++++++++++++++ restore env ++++++++++++++++++"
restore_env

echo "-------------------------------------------------------------------------"
echo ""
echo "Standby Test Finished. "
echo "== total times: $j =="
