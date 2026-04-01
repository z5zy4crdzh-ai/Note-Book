
@echo off
adb devices
adb root
adb shell "stop perf-hal-2-3"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy0 && cat scaling_available_frequencies && echo 2208000 > scaling_min_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy3 && cat scaling_available_frequencies && echo 2707200 > scaling_min_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy7 && cat scaling_available_frequencies && echo 2956800 > scaling_min_freq" 
adb shell "for dir in /sys/class/thermal/thermal_zone*;do echo disabled >$dir/mode;done"
adb shell "echo 4224000 > /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq"
adb shell "echo 1 > /sys/devices/system/cpu/bus_dcvs/DDRQOS/boost_freq"
adb shell "echo 1804800> /sys/devices/system/cpu/bus_dcvs/L3/boost_freq"
adb shell "echo 1066000 > /sys/devices/system/cpu/bus_dcvs/LLCC/boost_freq"
pause