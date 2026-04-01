
@echo off
adb devices
adb root
adb shell "stop perf2-hal-1-0"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy0 && cat scaling_available_frequencies && echo 2745600 > scaling_min_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy6 && cat scaling_available_frequencies && echo 4185600 > scaling_min_freq"
adb shell "for dir in /sys/class/thermal/thermal_zone*;do echo disabled >$dir/mode;done"
adb shell "echo 547000 > /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq"
adb shell "echo 1 > /sys/devices/system/cpu/bus_dcvs/DDRQOS/boost_freq"
adb shell "echo 282000 > /sys/devices/system/cpu/bus_dcvs/LLCC/boost_freq"
pause