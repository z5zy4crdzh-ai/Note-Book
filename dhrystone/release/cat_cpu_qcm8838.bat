@echo off
adb devices
adb root
adb shell "cd /sys/devices/system/cpu/cpufreq/policy0 && cat scaling_min_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy0 && cat scaling_max_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy0 && cat scaling_available_frequencies"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy6 && cat scaling_min_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy6 && cat scaling_max_freq"
adb shell "cd /sys/devices/system/cpu/cpufreq/policy6 && cat scaling_available_frequencies"
adb shell "cd /sys/devices/system/cpu/bus_dcvs/DDR&& cat boost_freq"
adb shell "cd /sys/devices/system/cpu/bus_dcvs/DDRQOS&& cat boost_freq"
adb shell "cd /sys/devices/system/cpu/bus_dcvs/LLCC&& cat boost_freq"
pause