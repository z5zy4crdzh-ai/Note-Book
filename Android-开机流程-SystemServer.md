### SystemServer

SystemServer进程的核心是SystemServer类，它是Android系统启动后的第一个Java进程。SystemServer类 负责启动系统的各种服务，它通过[Binder](https://so.csdn.net/so/search?q=Binder%E6%9C%BA%E5%88%B6&spm=1001.2101.3001.7020)[机制](https://so.csdn.net/so/search?q=Binder%E6%9C%BA%E5%88%B6&spm=1001.2101.3001.7020)提供各种服务接口:

(1)PowerManagerService：电源管理服务

(2) BatteryService：电池服务

(3) PackageManagerService：包管理服务

(4) ActivityManagerService：activity管理服务

(5) NetworkStatsService：网络状态服务

(6) WindowManagerService: 窗口管理服务

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/53567f0f3d1c4f35b1d3ef132d96a1d3~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1043&h=674&s=379423&e=png&b=f4f1fb)

#### SystemServer.main：

\build\android\frameworks\base\services\java\com\android\server\SystemServer.java

从Zygote进程fork而来的系统进程，当运行时重启或者手机重启时，标记mRuntimeRestart

```
public static void main(String[] args) {
        new SystemServer().run();
    }

    public SystemServer() {
        // Check for factory test mode.
        mFactoryTestMode = FactoryTest.getMode();

        // Record process start information.
        // Note SYSPROP_START_COUNT will increment by *2* on a FDE device when it fully boots;
        // one for the password screen, second for the actual boot.
        mStartCount = SystemProperties.getInt(SYSPROP_START_COUNT, 0) + 1;
        mRuntimeStartElapsedTime = SystemClock.elapsedRealtime();
        mRuntimeStartUptime = SystemClock.uptimeMillis();

        // Remember if it's runtime restart(when sys.boot_completed is already set) or reboot
        // We don't use "mStartCount > 1" here because it'll be wrong on a FDE device.
        // TODO: mRuntimeRestart will *not* be set to true if the proccess crashes before
        // sys.boot_completed is set. Fix it.
        mRuntimeRestart = "1".equals(SystemProperties.get("sys.boot_completed"));
    }

    private void run() {
        try {
            traceBeginAndSlog("InitBeforeStartServices");      //在android.log输出:"I SystemServer: InitBeforeStartServices"
            // 保证系统时间大于1970，部分API在时间小于此时会崩溃

            // Record the process start information in sys props.
            SystemProperties.set(SYSPROP_START_COUNT, String.valueOf(mStartCount));
            SystemProperties.set(SYSPROP_START_ELAPSED, String.valueOf(mRuntimeStartElapsedTime));
            SystemProperties.set(SYSPROP_START_UPTIME, String.valueOf(mRuntimeStartUptime));

            EventLog.writeEvent(EventLogTags.SYSTEM_SERVER_START,
                    mStartCount, mRuntimeStartUptime, mRuntimeStartElapsedTime);

            // If a device's clock is before 1970 (before 0), a lot of
            // APIs crash dealing with negative numbers, notably
            // java.io.File#setLastModified, so instead we fake it and
            // hope that time from cell towers or NTP fixes it shortly.
            if (System.currentTimeMillis() < EARLIEST_SUPPORTED_TIME) {
                Slog.w(TAG, "System clock is before 1970; setting to 1970.");
                SystemClock.setCurrentTimeMillis(EARLIEST_SUPPORTED_TIME);
            }

            //
            // Default the timezone property to GMT if not set.
            // 如果没有设置时区,统一设置为GMT
            String timezoneProperty = SystemProperties.get("persist.sys.timezone");
            if (timezoneProperty == null || timezoneProperty.isEmpty()) {
                Slog.w(TAG, "Timezone not set; setting to GMT.");
                SystemProperties.set("persist.sys.timezone", "GMT");
            }

            // If the system has "persist.sys.language" and friends set, replace them with
            // "persist.sys.locale". Note that the default locale at this point is calculated
            // using the "-Duser.locale" command line flag. That flag is usually populated by
            // AndroidRuntime using the same set of system properties, but only the system_server
            // and system apps are allowed to set them.
            //
            // NOTE: Most changes made here will need an equivalent change to
            // core/jni/AndroidRuntime.cpp
            // 设置系统语言，只有SystemServer进程和系统app允许修改
            if (!SystemProperties.get("persist.sys.language").isEmpty()) {
                final String languageTag = Locale.getDefault().toLanguageTag();

                SystemProperties.set("persist.sys.locale", languageTag);
                SystemProperties.set("persist.sys.language", "");
                SystemProperties.set("persist.sys.country", "");
                SystemProperties.set("persist.sys.localevar", "");
            }

            // The system server should never make non-oneway calls
            Binder.setWarnOnBlocking(true);
            // The system server should always load safe labels
            PackageItemInfo.forceSafeLabels();

            // Default to FULL within the system server.
            SQLiteGlobal.sDefaultSyncMode = SQLiteGlobal.SYNC_MODE_FULL;

            // Deactivate SQLiteCompatibilityWalFlags until settings provider is initialized
            SQLiteCompatibilityWalFlags.init(null);

            // Here we go!
            // 正式进入Android SystemServer
            Slog.i(TAG, "Entered the Android system server!");
            int uptimeMillis = (int) SystemClock.elapsedRealtime();//开机时间
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_SYSTEM_RUN, uptimeMillis);
            if (!mRuntimeRestart) {
                //非runtime重启或者手机重启进入
                //在event.log里输出:"sysui_histogram: [boot_system_server_init,11663]"
                MetricsLogger.histogram(null, "boot_system_server_init", uptimeMillis);
            }

            // In case the runtime switched since last boot (such as when
            // the old runtime was removed in an OTA), set the system
            // property so that it is in sync. We can | xq oqi't do this in
            // libnativehelper's JniInvocation::Init code where we already
            // had to fallback to a different runtime because it is
            // running as root and we need to be the system user to set
            // the property. http://b/11463182
            //设置运行时属性，防止如OTA更新导致运行时不同步
            //也就是设置虚拟机库文件
            SystemProperties.set("persist.sys.dalvik.vm.lib.2", VMRuntime.getRuntime().vmLibrary());

            // Mmmmmm... more memory!
             // 清除vm内存增长上限，由于启动过程需要较多的虚拟机内存空间
            VMRuntime.getRuntime().clearGrowthLimit();

            // The system server has to run all of the time, so it needs to be
            // as efficient as possible with its memory usage.
            // 系统服务会一直运行，所以设置内存的可能有效使用率为0.8，也就是增强程序堆内存的处理效率
            VMRuntime.getRuntime().setTargetHeapUtilization(0.8f);

            // Some devices rely on runtime fingerprint generation, so make sure
            // we've defined it before booting further.
            // 针对部分设备依赖于运行时就产生指纹信息，因此需要在开机完成前已经定义
            Build.ensureFingerprintProperty();

            // Within the system server, it is an error to access Environment paths without
            // explicitly specifying a user.
            // 访问环境变量前，需要明确指定用户
            Environment.setUserRequired(true);

            // Within the system server, any incoming Bundles should be defused
            // to avoid throwing BadParcelableException.
            // 系统服务中拒绝接收任何Bundle以避免抛出BadParcelableException
            BaseBundle.setShouldDefuse(true);

            // Within the system server, when parceling exceptions, include the stack trace
            Parcel.setStackTraceParceling(true);

            // Ensure binder calls into the system always run at foreground priority.
            // 确保系统Binder运行在前台优先级
            BinderInternal.disableBackgroundScheduling(true);

            // Increase the number of binder threads in system_server
            // 设置系统服务的最大Binder线程数为31
            BinderInternal.setMaxThreads(sMaxBinderThreads);

            // Prepare the main looper thread (this thread).
            // 设置当前进程的优先级为前台优先级，且不允许转为后台优先级
            android.os.Process.setThreadPriority(
                    android.os.Process.THREAD_PRIORITY_FOREGROUND);
            android.os.Process.setCanSelfBackground(false);
            Looper.prepareMainLooper();
            Looper.getMainLooper().setSlowLogThresholdMs(
                    SLOW_DISPATCH_THRESHOLD_MS, SLOW_DELIVERY_THRESHOLD_MS);

            // Initialize native services.
             // 初始化本地服务，也就是加载库文件: android_servers.so
            // 该库包含的源码在frameworks/base/services/目录下
            System.loadLibrary("android_servers");

            // Debug builds - allow heap profiling.
            if (Build.IS_DEBUGGABLE) {
                initZygoteChildHeapProfiling();
            }

            // Check whether we failed to shut down last time we tried.
            // This call may not return.
            // 检测上次关机过程是否失败，该方法可能不会返回[2.7.1]
            performPendingShutdown();

            // Initialize the system context.
             // 创建系统上下文,详细见Application创建流程
            createSystemContext();

            // Create the system service manager.
            mSystemServiceManager = new SystemServiceManager(mSystemContext);
            mSystemServiceManager.setStartInfo(mRuntimeRestart,
                    mRuntimeStartElapsedTime, mRuntimeStartUptime);
            LocalServices.addService(SystemServiceManager.class, mSystemServiceManager);
            // Prepare the thread pool for init tasks that can be parallelized
            // 为可以并行化的init任务准备线程池
            SystemServerInitThreadPool.get();
        } finally {
            traceEnd();  // InitBeforeStartServices
        }

        // Start services.
        //启动各类服务
        try {
            traceBeginAndSlog("StartServices");
            startBootstrapServices();           //启动引导服务
            startCoreServices();              //启动核心服务
            startOtherServices();              //启动其他服务
            SystemServerInitThreadPool.shutdown();      // 关闭SystemServerInitThreadPool
        } catch (Throwable ex) {
            Slog.e("System", "******************************************");
            Slog.e("System", "************ Failure starting system services", ex);
            throw ex;
        } finally {
            traceEnd();
        }

        StrictMode.initVmDefaults(null);

        if (!mRuntimeRestart && !isFirstBootOrUpgrade()) {         // 非重启且非第一次开机或者更新时进入
            int uptimeMillis = (int) SystemClock.elapsedRealtime();
            MetricsLogger.histogram(null, "boot_system_server_ready", uptimeMillis);
            final int MAX_UPTIME_MILLIS = 60 * 1000;
            if (uptimeMillis > MAX_UPTIME_MILLIS) {
                Slog.wtf(SYSTEM_SERVER_TIMING_TAG,
                        "SystemServer init took too long. uptimeMillis=" + uptimeMillis);
            }
        }

        // Diagnostic to ensure that the system is in a base healthy state. Done here as a common
        // non-zygote process.
        if (!VMRuntime.hasBootImageSpaces()) {
            Slog.wtf(TAG, "Runtime is not running with a boot image!");
        }

        // Loop forever.
        // 正常情况下，无限循环等待消息
        Looper.loop();
        throw new RuntimeException("Main thread loop unexpectedly exited");
    }

    private boolean isFirstBootOrUpgrade() {
        return mPackageManagerService.isFirstBoot() || mPackageManagerService.isDeviceUpgrading();
    }

    private void reportWtf(String msg, Throwable e) {
        Slog.w(TAG, "***********************************************");
        Slog.wtf(TAG, "BOOT FAILURE " + msg, e);
    }

    private void performPendingShutdown() {
        final String shutdownAction = SystemProperties.get(
                ShutdownThread.SHUTDOWN_ACTION_PROPERTY, "");
        if (shutdownAction != null && shutdownAction.length() > 0) {
            boolean reboot = (shutdownAction.charAt(0) == '1');

            final String reason;
            if (shutdownAction.length() > 1) {
                reason = shutdownAction.substring(1, shutdownAction.length());
            } else {
                reason = null;
            }

            // If it's a pending reboot into recovery to apply an update,
            // always make sure uncrypt gets executed properly when needed.
            // If '/cache/recovery/block.map' hasn't been created, stop the
            // reboot which will fail for sure, and get a chance to capture a
            // bugreport when that's still feasible. (Bug: 26444951)
            if (reason != null && reason.startsWith(PowerManager.REBOOT_RECOVERY_UPDATE)) {
                File packageFile = new File(UNCRYPT_PACKAGE_FILE);
                if (packageFile.exists()) {
                    String filename = null;
                    try {
                        filename = FileUtils.readTextFile(packageFile, 0, null);
                    } catch (IOException e) {
                        Slog.e(TAG, "Error reading uncrypt package file", e);
                    }

                    if (filename != null && filename.startsWith("/data")) {
                        if (!new File(BLOCK_MAP_FILE).exists()) {
                            Slog.e(TAG, "Can't find block map file, uncrypt failed or " +
                                    "unexpected runtime restart?");
                            return;
                        }
                    }
                }
            }
            Runnable runnable = new Runnable() {
                @Override
                public void run() {
                    synchronized (this) {
                        ShutdownThread.rebootOrShutdown(null, reboot, reason);
                    }
                }
            };
```

#### startBootstrapServices()：

\build\android\frameworks\base\services\java\com\android\server\SystemServer.java

ActivityManagerService是Android系统中一个特别重要的系统服务，也是我们上层APP打交道最多的系统服务之一。ActivityManagerService（以下简称AMS） 主要负责四大组件的启动、切换、调度以及应用进程的管理和调度工作。所有的APP应用都需要与AMS打交道. 符合C/S通信模式.

Client：由ActivityManager封装一部分服务接口供Client调用 Server:由ActivityManagerService实现，提供Server端的系统服务

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/7cf23daa9f1844e2b29144ca0315a1fc~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=741&h=641&s=45372&e=jpg&b=ffffff)

```
 private void startBootstrapServices() {
        // Start the watchdog as early as possible so we can crash the system server
        // if we deadlock during early boot
        traceBeginAndSlog("StartWatchdog");
        final Watchdog watchdog = Watchdog.getInstance();
        watchdog.start();
        traceEnd();
     
      
        Slog.i(TAG, "Reading configuration..."); // 在android.log输出:"I SystemServer: Reading configuration..."
        final String TAG_SYSTEM_CONFIG = "ReadingSystemConfig";
        traceBeginAndSlog(TAG_SYSTEM_CONFIG);
        SystemServerInitThreadPool.get().submit(SystemConfig::getInstance, TAG_SYSTEM_CONFIG);
        traceEnd();

        // Wait for installd to finish starting up so that it has a chance to
        // create critical directories such as /data/user with the appropriate
        // 等待installd完成启动，以便它有机会创建具有适当权限的关键目录，如/ data / user。
        // 在初始化其他服务之前，需要完成这个工作。  
        // permissions.  We need this to complete before we initialize other services.
        traceBeginAndSlog("StartInstaller");
        Installer installer = mSystemServiceManager.startService(Installer.class);
        traceEnd();

        // In some cases after launching an app we need to access device identifiers,
        // therefore register the device identifier policy before the activity manager.
        // 在某些情况下，启动应用程序后，我们需要访问设备标识符，因此在活动管理器之前注册设备标识符策略服务。 
        traceBeginAndSlog("DeviceIdentifiersPolicyService");
        mSystemServiceManager.startService(DeviceIdentifiersPolicyService.class);
        traceEnd();

        // Uri Grants Manager.
        traceBeginAndSlog("UriGrantsManagerService");
        mSystemServiceManager.startService(UriGrantsManagerService.Lifecycle.class);
        traceEnd();

        // Activity manager runs the show.
        // 启动AMS
        traceBeginAndSlog("StartActivityManager");
        // TODO: Might need to move after migration to WM.
        ActivityTaskManagerService atm = mSystemServiceManager.startService(
                ActivityTaskManagerService.Lifecycle.class).getService();
        mActivityManagerService = ActivityManagerService.Lifecycle.startService(
                mSystemServiceManager, atm);
        mActivityManagerService.setSystemServiceManager(mSystemServiceManager);
        mActivityManagerService.setInstaller(installer);
        mWindowManagerGlobalLock = atm.getGlobalLock();
        traceEnd();

        // Power manager needs to be started early because other services need it.
        // Native daemons may be watching for it to be registered so it must be ready
        // to handle incoming binder calls immediately (including being able to verify
        // the permissions for those calls).
        // 电源管理器需要尽早启动，因为其他服务需要它。
        // 本地守护进程可能正在注册，因此它必须准备好立即处理传入的绑定程序调用（包括能够验证这些调用的权限）。
        traceBeginAndSlog("StartPowerManager");
        mPowerManagerService = mSystemServiceManager.startService(PowerManagerService.class);
        traceEnd();

        traceBeginAndSlog("StartThermalManager");
        mSystemServiceManager.startService(ThermalManagerService.class);
        traceEnd();

        // Now that the power manager has been started, let the activity manager
        // initialize power management features.
        // 现在PowerManagerService已经启动，将其传入AMS
        traceBeginAndSlog("InitPowerManagement");
        mActivityManagerService.initPowerManagement();
        traceEnd();

        // Bring up recovery system in case a rescue party needs a reboot
        // 启动recovery系统服务
        traceBeginAndSlog("StartRecoverySystemService");
        mSystemServiceManager.startService(RecoverySystemService.class);
        traceEnd();

        // Now that we have the bare essentials of the OS up and running, take
        // note that we just booted, which might send out a rescue party if
        // we're stuck in a runtime restart loop.
        // OS启动的基础已经搭好，但是接来下的启动可能会陷入死循环，这里检测预防这种情况
        RescueParty.noteBoot(mSystemContext);

        // Manages LEDs and display backlight so we need it to bring up the display.
        // 启动灯光管理服务
        traceBeginAndSlog("StartLightsService");
        mSystemServiceManager.startService(LightsService.class);
        traceEnd();

        traceBeginAndSlog("StartSidekickService");
        // Package manager isn't started yet; need to use SysProp not hardware feature
        if (SystemProperties.getBoolean("config.enable_sidekick_graphics", false)) {
            mSystemServiceManager.startService(WEAR_SIDEKICK_SERVICE_CLASS);
        }
        traceEnd();

        // Display manager is needed to provide display metrics before package manager
        // starts up.
        // 启动显示管理服务，该服务需要在包管理服务前启动以提供相关服务
        traceBeginAndSlog("StartDisplayManager");
        mDisplayManagerService = mSystemServiceManager.startService(DisplayManagerService.class);
        traceEnd();

        // We need the default display before we can initialize the package manager.
        // 等待显示管理服务启动完毕
        // mCurrentPhase = -1
        // Phase 100: 在初始化package manager之前，需要默认的显示.
        traceBeginAndSlog("WaitForDisplay");
       // 逐个调用已启动的服务的onBootPharse()方法,也就是等待mServices中各个服务启动完毕
        mSystemServiceManager.startBootPhase(SystemService.PHASE_WAIT_FOR_DEFAULT_DISPLAY);
        traceEnd();
       
        // Only run "core" apps if we're encrypting the device.
        // 判断设备是否正在加密，是则仅运行核心
        String cryptState = VoldProperties.decrypt().orElse("");
        if (ENCRYPTING_STATE.equals(cryptState)) {
            Slog.w(TAG, "Detected encryption in progress - only parsing core apps");
            mOnlyCore = true;
        } else if (ENCRYPTED_STATE.equals(cryptState)) {
            Slog.w(TAG, "Device encrypted - only parsing core apps");
            mOnlyCore = true;
        }

        // Start the package manager.
       // 初始化包管理服务PMS
        if (!mRuntimeRestart) {
            MetricsLogger.histogram(null, "boot_package_manager_init_start",
                    (int) SystemClock.elapsedRealtime());
        }
        traceBeginAndSlog("StartPackageManagerService");
        // 启动PackageManagerService
        try {
            Watchdog.getInstance().pauseWatchingCurrentThread("packagemanagermain");
            mPackageManagerService = PackageManagerService.main(mSystemContext, installer,
                    mFactoryTestMode != FactoryTest.FACTORY_TEST_OFF, mOnlyCore);
        } finally {
            Watchdog.getInstance().resumeWatchingCurrentThread("packagemanagermain");
        }
        mFirstBoot = mPackageManagerService.isFirstBoot();
        mPackageManager = mSystemContext.getPackageManager();
        traceEnd();
        if (!mRuntimeRestart && !isFirstBootOrUpgrade()) {
            MetricsLogger.histogram(null, "boot_package_manager_init_ready",
                    (int) SystemClock.elapsedRealtime());
        }
        // Manages A/B OTA dexopting. This is a bootstrap service as we need it to rename
        // A/B artifacts after boot, before anything else might touch/need them.
        // Note: this isn't needed during decryption (we don't have /data anyways).
        if (!mOnlyCore) {
            boolean disableOtaDexopt = SystemProperties.getBoolean("config.disable_otadexopt",
                    false);
            if (!disableOtaDexopt) {
                traceBeginAndSlog("StartOtaDexOptService");
                try {
                    Watchdog.getInstance().pauseWatchingCurrentThread("moveab");
                    OtaDexoptService.main(mSystemContext, mPackageManagerService);
                } catch (Throwable e) {
                    reportWtf("starting OtaDexOptService", e);
                } finally {
                    Watchdog.getInstance().resumeWatchingCurrentThread("moveab");
                    traceEnd();
                }
            }
        }

        traceBeginAndSlog("StartUserManagerService");
        mSystemServiceManager.startService(UserManagerService.LifeCycle.class);
        traceEnd();

        // Initialize attribute cache used to cache resources from packages.
        // 初始化属性缓存，用于缓存来自包的资源
        traceBeginAndSlog("InitAttributerCache");
        AttributeCache.init(mSystemContext);
        traceEnd();

        // Set up the Application instance for the system process and get started.
       // 设置系统进程的应用程序实例
        traceBeginAndSlog("SetSystemProcess");
        mActivityManagerService.setSystemProcess();
        traceEnd();

        // Complete the watchdog setup with an ActivityManager instance and listen for reboots
        // Do this only after the ActivityManagerService is properly started as a system process
        traceBeginAndSlog("InitWatchdog");
        watchdog.init(mSystemContext, mActivityManagerService);
        traceEnd();

        // DisplayManagerService needs to setup android.display scheduling related policies
        // since setSystemProcess() would have overridden policies due to setProcessGroup
        // 因为AMS.setSystemProcess() 会覆盖策略,所以
        // DisplayManagerService需要设置android.display调度相关的策略
        mDisplayManagerService.setupSchedulerPolicies();

        // Manages Overlay packages
        // 启动OverlayManagerService，管理覆盖包
        traceBeginAndSlog("StartOverlayManagerService");
        mSystemServiceManager.startService(new OverlayManagerService(mSystemContext, installer));
        traceEnd();

        traceBeginAndSlog("StartSensorPrivacyService");
        mSystemServiceManager.startService(new SensorPrivacyService(mSystemContext));
        traceEnd();

        if (SystemProperties.getInt("persist.sys.displayinset.top", 0) > 0) {
            // DisplayManager needs the overlay immediately.
            mActivityManagerService.updateSystemUiContext();
            LocalServices.getService(DisplayManagerInternal.class).onOverlayChanged();
        }

        // The sensor service needs access to package manager service, app ops
        // service, and permissions service, therefore we start it after them.
        // Start sensor service in a separate thread. Completion should be checked
        // before using it.
        // 传感器服务需要访问PackageManagerService，AppOps和Permissions Service，因此我们在它们之后启动它
        // 启动传感器服务在一个单独的线程中，使用前应检查完成情况。
        mSensorServiceStart = SystemServerInitThreadPool.get().submit(() -> {
            TimingsTraceLog traceLog = new TimingsTraceLog(
                    SYSTEM_SERVER_TIMING_ASYNC_TAG, Trace.TRACE_TAG_SYSTEM_SERVER);
            traceLog.traceBegin(START_SENSOR_SERVICE);
            startSensorService();
            traceLog.traceEnd();
        }, START_SENSOR_SERVICE);
    }




 public static ActivityManagerService startService(
                SystemServiceManager ssm, ActivityTaskManagerService atm) {
            sAtm = atm;
            return 
//传入的是ActivityManagerService.Lifecycle.class对象
ssm.startService(ActivityManagerService.Lifecycle.class).getService();
}

```

#### Lifecycle：

\build\android\frameworks\base\services\core\java\com\android\server\am\ActivityManagerService.java

Life实例是AMS中的一个静态内部类，并且继承于SystemService

```
public static final public static final class Lifecycle extends SystemService {
        private final ActivityManagerService mService;
        private static ActivityTaskManagerService sAtm;

        public Lifecycle(Context context) {
            super(context);
            mService = new ActivityManagerService(context, sAtm);
        }

        public static ActivityManagerService startService(
                SystemServiceManager ssm, ActivityTaskManagerService atm) {
            sAtm = atm;
            //传入的是ActivityManagerService.Lifecycle.class对象
            return ssm.startService(ActivityManagerService.Lifecycle.class).getService();
        }

        @Override
        public void onStart() {
            mService.start();
        }

        @Override
        public void onBootPhase(int phase) {
            mService.mBootPhase = phase;
            if (phase == PHASE_SYSTEM_SERVICES_READY) {
                mService.mBatteryStatsService.systemServicesReady();
                mService.mServices.systemServicesReady();
            } else if (phase == PHASE_ACTIVITY_MANAGER_READY) {
                mService.startBroadcastObservers();
            } else if (phase == PHASE_THIRD_PARTY_APPS_CAN_START) {
                mService.mPackageWatchdog.onPackagesReady();
            }
        }

        @Override
        public void onCleanupUser(int userId) {
            mService.mBatteryStatsService.onCleanupUser(userId);
        }

        public ActivityManagerService getService() {
            return mService;
        }
    } extends SystemService {
        private final ActivityManagerService mService;
        private static ActivityTaskManagerService sAtm;
 
        public Lifecycle(Context context) {
            super(context);
            mService = new ActivityManagerServiceEx(context, sAtm);
        }
....
 
}
```

#### startService()：

\build\android\frameworks\base\services\core\java\com\android\server\SystemServiceManager.java

AMS是通过SystemServiceManager.startService去启动的，参数是ActivityTaskManagerService.Lifecycle.class

用传入进来的ActivityManagerService.Lifecycle.class作为参数, 通过反射方式创建对应的service服务. 所以创建的是Lifecycle的实例, 然后通过startService来启动服务

```
public <T extends SystemService> T startService(Class<T> serviceClass) {
        try {
            final String name = serviceClass.getName();
            Slog.i(TAG, "Starting " + name);
            Trace.traceBegin(Trace.TRACE_TAG_SYSTEM_SERVER, "StartService " + name);

            // Create the service.
            if (!SystemService.class.isAssignableFrom(serviceClass)) {
                throw new RuntimeException("Failed to create " + name
                        + ": service must extend " + SystemService.class.getName());
            }
            final T service;
            try {
                //获取AMS.Lifecycle类中 带context参数的构造方法
                Constructor<T> constructor = serviceClass.getConstructor(Context.class);
                //通过构造器的newInstance方法
               //实际上就是 new一个 AMSEx对象 而 AMSEx 是继承 AMS
                service = constructor.newInstance(mContext);
            } catch (InstantiationException ex) {
                throw new RuntimeException("Failed to create service " + name
                        + ": service could not be instantiated", ex);
            } catch (IllegalAccessException ex) {
                throw new RuntimeException("Failed to create service " + name
                        + ": service must have a public constructor with a Context argument", ex);
            } catch (NoSuchMethodException ex) {
                throw new RuntimeException("Failed to create service " + name
                        + ": service must have a public constructor with a Context argument", ex);
            } catch (InvocationTargetException ex) {
                throw new RuntimeException("Failed to create service " + name
                        + ": service constructor threw an exception", ex);
            }

            startService(service);
            return service;
        } finally {
            Trace.traceEnd(Trace.TRACE_TAG_SYSTEM_SERVER);
        }
    }


public void startService(@NonNull final SystemService service) {
        // Register it.
        mServices.add(service);
        // Start it.
        long time = SystemClock.elapsedRealtime();
        try {
            //执行AMS中的onStart()方法, 服务真正的启动起来
            service.onStart();
        } catch (RuntimeException ex) {
            throw new RuntimeException("Failed to start service " + service.getClass().getName()
                    + ": onStart threw an exception", ex);
        }
        warnIfTooLong(SystemClock.elapsedRealtime() - time, service, "onStart");
    }
```

#### mService.start()：

\build\android\frameworks\base\services\core\java\com\android\server\am\ActivityManagerService.java

最后执行到AMS中的start方法

```
 private void start() {
        removeAllProcessGroups();
        mProcessCpuThread.start();
 
        mBatteryStatsService.publish();
        mAppOpsService.publish(mContext);
        Slog.d("AppOps", "AppOpsService published");
        LocalServices.addService(ActivityManagerInternal.class, new LocalService());
        mActivityTaskManager.onActivityManagerInternalAdded();
        mUgmInternal.onActivityManagerInternalAdded();
        mPendingIntentController.onActivityManagerInternalAdded();
        // Wait for the synchronized block started in mProcessCpuThread,
        // so that any other access to mProcessCpuTracker from main thread
        // will be blocked during mProcessCpuTracker initialization.
        try {
//等待mProcessCpuThread完成初始化后， 释放锁，初始化期间禁止访问
            mProcessCpuInitLatch.await();
        } catch (InterruptedException e) {
            Slog.wtf(TAG, "Interrupted wait during start", e);
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted wait during start");
        }
    }
```

#### PkMS

0.  遍历/data/app和/system/app文件夹，找到apk文件

0.  解压apk文件

0.  dom解析AndroidManifest.xml文件，将xml信息存储起来提供给AMS使用

    ![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/bc43980b2f994e8eab95983ef2407064~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1145&h=742&s=190131&e=png&b=fdfdfd)

开机，内核进程启动init进程，init进程启动SeriviceManager进程和启动Zygote进程，Zygote进程启动SystemServer，SystemServer进程启动AMS、PMS，并注册到ServiceManager。 PMS被SystemServer初始化后，开始扫描/data/app/和/system/app/目录下的所有apk文件，获取每个apk文件的AndroidManifest.xml文件，并进行dom解析。 解析AndroidManifest.xml将应用信息、权限、四大组件等数据信息转换为Java Bean缓存到内存中。 当AMS需要获取apk数据信息时，通过ServiceManager获取到PMS的Binder代理通过Binder通信获取。

##### startBootstrapServices()：

\build\android\frameworks\base\services\java\com\android\server\SystemServer.java

```
// Start the package manager.
if (!mRuntimeRestart) {
            MetricsLogger.histogram(null, "boot_package_manager_init_start",
                    (int) SystemClock.elapsedRealtime());
        }
        traceBeginAndSlog("StartPackageManagerService");
        // 启动PackageManagerService
        try {
        //  Watchdog 是 Android 系统中的一种机制，用于监控应用程序的运行状态，以防止出现长时间的无响应或卡顿情况。当 Watchdog 检测到某个线程长时间没有响应时，它可以采取一些措施来保护系统的稳定性，例如终止该线程或者进行其他的故障处理
            // 暂停对当前线程进行监控，允许线程继续执行,getInstance外部接口
            Watchdog.getInstance().pauseWatchingCurrentThread("packagemanagermain");
        //调用PackageManagerService.main()方法，在main()方法中创建PMS的对象，并向ServiceManager注册Binder
            mPackageManagerService = PackageManagerService.main(mSystemContext, installer,
                    mFactoryTestMode != FactoryTest.FACTORY_TEST_OFF, mOnlyCore);
        } finally {
            Watchdog.getInstance().resumeWatchingCurrentThread("packagemanagermain");
        }
        mFirstBoot = mPackageManagerService.isFirstBoot();
        // 初始化PackageManager对象.
        mPackageManager = mSystemContext.getPackageManager();
        traceEnd();
        if (!mRuntimeRestart && !isFirstBootOrUpgrade()) {
            MetricsLogger.histogram(null, "boot_package_manager_init_ready",
                    (int) SystemClock.elapsedRealtime());
        }
```

##### PackageManagerService.main：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

```
public static PackageManagerService main(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
        // Self-check for initial settings.
        // 检查Package编译相关系统属性
        PackageManagerServiceCompilerMapping.checkProperties();
        // 创建PMS对象
        PackageManagerService m = new PackageManagerService(context, installer,
                factoryTest, onlyCore);
        //启用部分应用服务于多用户场景
        m.enableSystemUserPackages();
        // 注册PMS对象到ServiceManager中
        ServiceManager.addService("package", m);
        // 创建PMN对象，内部使用的类，在底层实现了与应用程序包管理相关的功能，包括应用安装、卸载、版本管理等
        final PackageManagerNative pmn = m.new PackageManagerNative();
        // 注册PMN对象
        ServiceManager.addService("package_native", pmn);
        return m;
    }
```

##### PackageManagerService：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

```
private static final File sAppInstallDir =
            // data/app目录
            new File(Environment.getDataDirectory(), "app");
public PackageManagerService(Context context, Installer installer,boolean factoryTest, boolean onlyCore) {
        Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "create package manager");
        //第一阶段boot_progress_pms_start   PMS开始扫描安装的应用
        EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_START,
                SystemClock.uptimeMillis());
    
           // 第二阶段boot_progress_pms_system_scan_start 扫描system/app目录
            long startTime = SystemClock.uptimeMillis();
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_SYSTEM_SCAN_START,
                    startTime);
            // Collect ordinary system packages.
            // 扫描system/app目录
            final File systemAppDir = new File(Environment.getRootDirectory(), "app");
            scanDirTracedLI(systemAppDir,
                    mDefParseFlags
                    | PackageParser.PARSE_IS_SYSTEM_DIR,
                    scanFlags
                    | SCAN_AS_SYSTEM,
                    0);

    ......
        final long systemScanTime = SystemClock.uptimeMillis() - startTime;
        final int systemPackagesCount = mPackages.size();
        Slog.i(TAG, "Finished scanning system apps. Time: " + systemScanTime
                    + " ms, packageCount: " + systemPackagesCount
                    + " , timePerPackage: "
                    + (systemPackagesCount == 0 ? 0 : systemScanTime / systemPackagesCount)
                    + " , cached: " + cachedSystemApps);
        if (mIsUpgrade && systemPackagesCount > 0) {
            FrameworkStatsLog.write(FrameworkStatsLog.BOOT_TIME_EVENT_DURATION_REPORTED,                
BOOT_TIME_EVENT_DURATION__EVENT__OTA_PACKAGE_MANAGER_SYSTEM_APP_AVG_SCAN_TIME,
     systemScanTime / systemPackagesCount);
            }
          // 对于不仅仅解析核心应用的情况下，还处理data目录的应用信息，及时更新，去除不必要的数据
            if (!mOnlyCore) {
            //第三阶段boot_progress_pms_data_scan_start  扫描data/app目录
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_DATA_SCAN_START,
            SystemClock.uptimeMillis());
            scanDirTracedLI(sAppInstallDir, 0, scanFlags | SCAN_REQUIRE_KNOWN, 0,
                        packageParser, executorService);
            }
   ......
            
            // Now that we know all the packages we are keeping,
            // read and update their last usage times.
            mPackageUsage.read(mPackages);
            mCompilerStats.read();
            //第四阶段boot_progress_pms_scan_end PMS扫描结束
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_SCAN_END,
                    SystemClock.uptimeMillis());
            Slog.i(TAG, "Time to scan packages: "
                    + ((SystemClock.uptimeMillis()-startTime)/1000f)
                    + " seconds");
    ......
            // Uncompress and install any stubbed system applications.
            // This must be done last to ensure all stubs are replaced or disabled.
            // 安装APK
            installSystemStubPackages(stubSystemApps, scanFlags);
    
    ......
            // can downgrade to reader
            //第五阶段boot_progress_pms_ready PMS就绪
            Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "write settings");
            mSettings.writeLPr();
            Trace.traceEnd(TRACE_TAG_PACKAGE_MANAGER);
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_READY,
                    SystemClock.uptimeMillis());
    ......
          }

```

##### scanDirLI()：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

扫描某个目录的apk文件

```
private void scanDirLI(File scanDir, int parseFlags, int scanFlags, long currentTime) {
        final File[] files = scanDir.listFiles();
        if (ArrayUtils.isEmpty(files)) {
            Log.d(TAG, "No files in app dir " + scanDir);
            return;
        }

        if (DEBUG_PACKAGE_SCANNING) {
            Log.d(TAG, "Scanning app dir " + scanDir + " scanFlags=" + scanFlags
                    + " flags=0x" + Integer.toHexString(parseFlags));
        }
        // parallelPackageParser是一个队列，收集系统 apk 文件， 进行多线程扫描apk
        // 然后从这个队列里面一个个取出 apk 调用PackageParser 解析
        try (ParallelPackageParser parallelPackageParser = new ParallelPackageParser(
                mSeparateProcesses, mOnlyCore, mMetrics, mCacheDir,
                mParallelPackageParserCallback)) {
            // Submit files for parsing in parallel
            int fileCount = 0;
            for (File file : files) {
                // 是Apk文件，或者是目录
                final boolean isPackage = (isApkFile(file) || file.isDirectory())
                        && !PackageInstallerService.isStageName(file.getName());
                if (!isPackage) {
                    // Ignore entries which are not packages
                    // 过滤掉非apk文件，如果不是则跳过继续扫描
                    continue;
                }
                // 把APK信息存入parallelPackageParser中的对象 mQueue，PackageParser()函数赋给了队列中的pkg成员
                // 遍历完/data/app和/system/app文件夹，找到apk文件，然后通过submit()方法进行了apk的解析
                parallelPackageParser.submit(file, parseFlags);
                fileCount++;
            }

            // Process results one by one
            // 从parallelPackageParser中取出队列apk的信息
            for (; fileCount > 0; fileCount--) {
                ParallelPackageParser.ParseResult parseResult = parallelPackageParser.take();
                Throwable throwable = parseResult.throwable;
                int errorCode = PackageManager.INSTALL_SUCCEEDED;

                if (throwable == null) {
                    // TODO(toddke): move lower in the scan chain
                    // Static shared libraries have synthetic package names
                    if (parseResult.pkg.applicationInfo.isStaticSharedLibrary()) {
                        renameStaticSharedLibraryPackage(parseResult.pkg);
                    }
                    // 调用 scanPackageChildLI 方法扫描一个特定的 apk 文件 
                    // 该类的实例代表一个APK文件，所以它就是和apk文件对应的数据结构。
                    try {
                        scanPackageChildLI(parseResult.pkg, parseFlags, scanFlags,
                                currentTime, null);
                    } catch (PackageManagerException e) {
                        errorCode = e.error;
                        Slog.w(TAG, "Failed to scan " + parseResult.scanFile + ": " + e.getMessage());
                    }
                } else if (throwable instanceof PackageParser.PackageParserException) {
                    PackageParser.PackageParserException e = (PackageParser.PackageParserException)
                            throwable;
                    errorCode = e.error;
                    Slog.w(TAG, "Failed to parse " + parseResult.scanFile + ": " + e.getMessage());
                } else {
                    throw new IllegalStateException("Unexpected exception occurred while parsing "
                            + parseResult.scanFile, throwable);
                }

                 //如果是非系统 apk 并且解析失败
                // Delete invalid userdata apps
                if ((scanFlags & SCAN_AS_SYSTEM) == 0 &&
                        errorCode != PackageManager.INSTALL_SUCCEEDED) {
                    logCriticalInfo(Log.WARN,
                            "Deleting invalid package at " + parseResult.scanFile);
                    // 非系统 Package 扫描失败，删除文件
                    removeCodePathLI(parseResult.scanFile);
                }
            }
        }
    }
```

##### submit()：

\build\android\frameworks\base\services\core\java\com\android\server\pm\ParallelPackageParser.java

将上面找到的apk文件路径传入PackageParser对象的`parsePackage()`进行apk的解析

```
class ParallelPackageParser implements AutoCloseable {

    private static final int QUEUE_CAPACITY = 10; // 多线程队列容量
    private static final int MAX_THREADS = 4; // 最大线程数

    private final String[] mSeparateProcesses;
    private final boolean mOnlyCore;
    private final DisplayMetrics mMetrics;
    private final File mCacheDir;
    private final PackageParser.Callback mPackageParserCallback;
    private volatile String mInterruptedInThread;
    // 存储解析结果
    private final BlockingQueue<ParseResult> mQueue = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    // 线程池
    private final ExecutorService mService = ConcurrentUtils.newFixedThreadPool(MAX_THREADS,
            "package-parsing-thread", Process.THREAD_PRIORITY_FOREGROUND);
   
    ParallelPackageParser(String[] separateProcesses, boolean onlyCoreApps,
            DisplayMetrics metrics, File cacheDir, PackageParser.Callback callback) {
        mSeparateProcesses = separateProcesses;
        mOnlyCore = onlyCoreApps;
        mMetrics = metrics;
        mCacheDir = cacheDir;
        mPackageParserCallback = callback;
    }

    static class ParseResult {

        PackageParser.Package pkg; // Parsed package
        File scanFile; // File that was parsed
        Throwable throwable; // Set if an error occurs during parsing

        @Override
        public String toString() {
            return "ParseResult{" +
                    "pkg=" + pkg +
                    ", scanFile=" + scanFile +
                    ", throwable=" + throwable +
                    '}';
        }
    }

    /**
     * Take the parsed package from the parsing queue, waiting if necessary until the element
     * appears in the queue.
     * @return parsed package
     */
    public ParseResult take() {
        try {
            if (mInterruptedInThread != null) {
                throw new InterruptedException("Interrupted in " + mInterruptedInThread);
            }
            return mQueue.take();
        } catch (InterruptedException e) {
            // We cannot recover from interrupt here
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    /**
     * Submits the file for parsing
     * @param scanFile file to scan
     * @param parseFlags parse falgs
     */
    public void submit(File scanFile, int parseFlags) {
        // 提交到线程池
        mService.submit(() -> {
            ParseResult pr = new ParseResult();
            Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "parallel parsePackage [" + scanFile + "]");
            try {
                PackageParser pp = new PackageParser();
                pp.setSeparateProcesses(mSeparateProcesses);
                pp.setOnlyCoreApps(mOnlyCore);
                pp.setDisplayMetrics(mMetrics);
                pp.setCacheDir(mCacheDir);
                pp.setCallback(mPackageParserCallback);
                // 需要解析的apk路径,赋值给ParseResult()
                pr.scanFile = scanFile;
                // 获取 PackageParser.Package 对象，通过PackageParser对apk进行解析
                pr.pkg = parsePackage(pp, scanFile, parseFlags);
            } catch (Throwable e) {
                pr.throwable = e;
            } finally {
                Trace.traceEnd(TRACE_TAG_PACKAGE_MANAGER);
            }
            try {
                // 把解析出的apk内容放入mQueue队列
                mQueue.put(pr);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                // Propagate result to callers of take().
                // This is helpful to prevent main thread from getting stuck waiting on
                // ParallelPackageParser to finish in case of interruption
                mInterruptedInThread = Thread.currentThread().getName();
            }
        });
    }

    @VisibleForTesting
    protected PackageParser.Package parsePackage(PackageParser packageParser, File scanFile,
            int parseFlags) throws PackageParser.PackageParserException {
        return packageParser.parsePackage(scanFile, parseFlags, true /* useCaches */);
    }

    @Override
    public void close() {
        List<Runnable> unfinishedTasks = mService.shutdownNow();
        if (!unfinishedTasks.isEmpty()) {
            throw new IllegalStateException("Not all tasks finished before calling close: "
                    + unfinishedTasks);
        }
    }
}
```

##### parsePackage：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

```
      @UnsupportedAppUsage
      public Package parsePackage(File packageFile, int flags, boolean useCaches)
              throws PackageParserException {
         Package parsed = useCaches ? getCachedResult(packageFile, flags) : null;
          if (parsed != null) {
                  // 直接返回缓存
             return parsed;
          }
 
         long parseTime = LOG_PARSE_TIMINGS ? SystemClock.uptimeMillis() : 0;
              // 如果是目录，执行parseClusterPackage()
         if (packageFile.isDirectory()) {
             parsed = parseClusterPackage(packageFile, flags);
         } else {
               // apk文件非目录，执行parseMonolithicPackage()解析
              parsed = parseMonolithicPackage(packageFile, flags);
          }
......
          return parsed;
      }

```

##### parseClusterPackage：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

解析给定目录中包含的所有apk，将它们视为单个包。这还可以执行完整性检查，比如需要相同的包名和版本代码、单个基本APK和惟一的拆分名称

对目录下的apk文件进行初步分析，主要区别是核心应用还是非核心应用。核心应用只有一个，非核心应用可以没有，或者多个，非核心应用的作用主要用来保存资源和代码。然后对核心应用调用parseBaseApk分析并生成Package。对非核心应用调用parseSplitApk，分析结果放在前面的Package对象中

```
 
private Package parseClusterPackage(File packageDir, int flags) throws PackageParserException {
    //获取应用目录的PackageLite对象，这个对象分开保存了目录下的核心应用以及非核心应用的名称
    final PackageLite lite = parseClusterPackageLite(packageDir, 0);
    //如果lite中没有核心应用，退出
    if (mOnlyCoreApps && !lite.coreApp) {
        throw new PackageParserException(INSTALL_PARSE_FAILED_MANIFEST_MALFORMED,
                "Not a coreApp: " + packageDir);
    }
 
    // Build the split dependency tree.
    //构建分割的依赖项树
    SparseArray<int[]> splitDependencies = null;
    final SplitAssetLoader assetLoader;
    if (lite.isolatedSplits && !ArrayUtils.isEmpty(lite.splitNames)) {
        try {
            splitDependencies = SplitAssetDependencyLoader.createDependenciesFromPackage(lite);
            assetLoader = new SplitAssetDependencyLoader(lite, splitDependencies, flags);
        } catch (SplitAssetDependencyLoader.IllegalDependencyException e) {
            throw new PackageParserException(INSTALL_PARSE_FAILED_BAD_MANIFEST, e.getMessage());
        }
    } else {
        assetLoader = new DefaultSplitAssetLoader(lite, flags);
    }
 
    try {
        final AssetManager assets = assetLoader.getBaseAssetManager();
        final File baseApk = new File(lite.baseCodePath);
        //对核心应用解析
        final Package pkg = parseBaseApk(baseApk, assets, flags);
        if (pkg == null) {
            throw new PackageParserException(INSTALL_PARSE_FAILED_NOT_APK,
                    "Failed to parse base APK: " + baseApk);
        }
 
        if (!ArrayUtils.isEmpty(lite.splitNames)) {
            final int num = lite.splitNames.length;
            pkg.splitNames = lite.splitNames;
            pkg.splitCodePaths = lite.splitCodePaths;
            pkg.splitRevisionCodes = lite.splitRevisionCodes;
            pkg.splitFlags = new int[num];
            pkg.splitPrivateFlags = new int[num];
            pkg.applicationInfo.splitNames = pkg.splitNames;
            pkg.applicationInfo.splitDependencies = splitDependencies;
            pkg.applicationInfo.splitClassLoaderNames = new String[num];
 
            for (int i = 0; i < num; i++) {
                final AssetManager splitAssets = assetLoader.getSplitAssetManager(i);
                //对非核心应用的处理
                parseSplitApk(pkg, i, splitAssets, flags);
            }
        }
 
        pkg.setCodePath(packageDir.getCanonicalPath());
        pkg.setUse32bitAbi(lite.use32bitAbi);
        return pkg;
    } catch (IOException e) {
        throw new PackageParserException(INSTALL_PARSE_FAILED_UNEXPECTED_EXCEPTION,
                "Failed to get path: " + lite.baseCodePath, e);
    } finally {
        IoUtils.closeQuietly(assetLoader);
    }
}
```

##### parseMonolithicPackage：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

```
public Package parseMonolithicPackage(File apkFile, int flags) throws PackageParserException {
        final PackageLite lite = parseMonolithicPackageLite(apkFile, flags);
        if (mOnlyCoreApps) {
            if (!lite.coreApp) {
                throw new PackageParserException(INSTALL_PARSE_FAILED_MANIFEST_MALFORMED,
                        "Not a coreApp: " + apkFile);
            }
        }

        final SplitAssetLoader assetLoader = new DefaultSplitAssetLoader(lite, flags);
        try {
             // apk解析方法parseBaseApk()
            final Package pkg = parseBaseApk(apkFile, assetLoader.getBaseAssetManager(), flags);
            pkg.setCodePath(apkFile.getCanonicalPath());
            pkg.setUse32bitAbi(lite.use32bitAbi);
            return pkg;
        } catch (IOException e) {
            throw new PackageParserException(INSTALL_PARSE_FAILED_UNEXPECTED_EXCEPTION,
                    "Failed to get path: " + apkFile, e);
        } finally {
            IoUtils.closeQuietly(assetLoader);
        }
    }
```

##### parseBaseApk：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

主要是对AndroidManifest.xml进行解析，解析后所有的信息放在Package对象中

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/d38e9fb5216d43998179b8e4df770cf7~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1578&h=1160&s=1284248&e=png&b=f8f7f7)

```
private Package parseBaseApk(File apkFile, AssetManager assets, int flags)
            throws PackageParserException {
        final String apkPath = apkFile.getAbsolutePath();

        String volumeUuid = null;
        if (apkPath.startsWith(MNT_EXPAND)) {
            final int end = apkPath.indexOf('/', MNT_EXPAND.length());
            volumeUuid = apkPath.substring(MNT_EXPAND.length(), end);
        }

        mParseError = PackageManager.INSTALL_SUCCEEDED;
        mArchiveSourcePath = apkFile.getAbsolutePath();

        if (DEBUG_JAR) Slog.d(TAG, "Scanning base APK: " + apkPath);
         // 开始 dom 解析 AndroidManifest.xml
        XmlResourceParser parser = null;
        try {
            final int cookie = assets.findCookieForPath(apkPath);
            if (cookie == 0) {
                throw new PackageParserException(INSTALL_PARSE_FAILED_BAD_MANIFEST,
                        "Failed adding asset path: " + apkPath);
            }
            //获得一个 XML 资源解析对象，该对象解析的是 APK 中的 AndroidManifest.xml 文件
            parser = assets.openXmlResourceParser(cookie, ANDROID_MANIFEST_FILENAME);
            final Resources res = new Resources(assets, mMetrics, null);

            final String[] outError = new String[1];
            //再调用重载函数parseBaseApk()最终到parseBaseApkCommon()，解析AndroidManifest.xml 后得到一个Package对象
            final Package pkg = parseBaseApk(apkPath, res, parser, flags, outError);
            if (pkg == null) {
                throw new PackageParserException(mParseError,
                        apkPath + " (at " + parser.getPositionDescription() + "): " + outError[0]);
            }

            pkg.setVolumeUuid(volumeUuid);
            pkg.setApplicationVolumeUuid(volumeUuid);
            pkg.setBaseCodePath(apkPath);
            pkg.setSigningDetails(SigningDetails.UNKNOWN);

            return pkg;

        } catch (PackageParserException e) {
            throw e;
        } catch (Exception e) {
            throw new PackageParserException(INSTALL_PARSE_FAILED_UNEXPECTED_EXCEPTION,
                    "Failed to read manifest from " + apkPath, e);
        } finally {
            IoUtils.closeQuietly(parser);
        }
    }



   // 解析AndroidManifest.xml
 @UnsupportedAppUsage(maxTargetSdk = Build.VERSION_CODES.P, trackingBug = 115609023)
      private Package parseBaseApk(String apkPath, Resources res, XmlResourceParser parser, int flags,
              String[] outError) throws XmlPullParserException, IOException {
          final String splitName;
          final String pkgName;
  
          try {
              // 解析包名
             Pair<String, String> packageSplit = parsePackageSplitNames(parser, parser);
              pkgName = packageSplit.first; 
             splitName = packageSplit.second;
......
          }
......
              // 将解析的信息（四大组件、权限等）存储到Package
          final Package pkg = new Package(pkgName);
.....
          return parseBaseApkCommon(pkg, null, res, parser, flags, outError);
     }
......
      /**
       * Representation of a full package parsed from APK files on disk. A package
       * consists of a single base APK, and zero or more split APKs.
       */
       public final static class Package implements Parcelable {
......
              // 包名
         @UnsupportedAppUsage
          public String packageName; 
              // 应用信息
          @UnsupportedAppUsage
         public ApplicationInfo applicationInfo = new ApplicationInfo();
  
              // 权限相关信息
          @UnsupportedAppUsage
          public final ArrayList<Permission> permissions = new ArrayList<Permission>(0);
         @UnsupportedAppUsage
          public final ArrayList<PermissionGroup> permissionGroups = new ArrayList<PermissionGroup>(0);
              // 四大组件相关信息
          @UnsupportedAppUsage
          public final ArrayList<Activity> activities = new ArrayList<Activity>(0);
          @UnsupportedAppUsage
          public final ArrayList<Activity> receivers = new ArrayList<Activity>(0);
          @UnsupportedAppUsage
          public final ArrayList<Provider> providers = new ArrayList<Provider>(0);
          @UnsupportedAppUsage
          public final ArrayList<Service> services = new ArrayList<Service>(0);
......
      }
 

```

##### parseBaseApkCommon：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

从AndroidManifest.xml中获取标签名，解析标签中的各个item的内容，存入Package对象中

```
 
private Package parseBaseApkCommon(Package pkg, Set<String> acceptedTags, Resources res,
        XmlResourceParser parser, int flags, String[] outError) throws XmlPullParserException,
        IOException {
  TypedArray sa = res.obtainAttributes(parser,
            com.android.internal.R.styleable.AndroidManifest);
  //拿到AndroidManifest.xml 中的sharedUserId, 一般情况下有“android.uid.system”等信息
  String str = sa.getNonConfigurationString(
            com.android.internal.R.styleable.AndroidManifest_sharedUserId, 0);
      
  while ((type = parser.next()) != XmlPullParser.END_DOCUMENT
            && (type != XmlPullParser.END_TAG || parser.getDepth() > outerDepth)) {
    //从AndroidManifest.xml中获取标签名
    String tagName = parser.getName();
    //如果读到AndroidManifest.xml中的tag是"application",执行parseBaseApplication()进行解析
    if (tagName.equals(TAG_APPLICATION)) {
            if (foundApp) {
        ...
            }
            foundApp = true;
      //解析"application"的信息，赋值给pkg
            if (!parseBaseApplication(pkg, res, parser, flags, outError)) {
                return null;
            }
      ...
      //如果标签是"permission"
      else if (tagName.equals(TAG_PERMISSION)) {
      //进行"permission"的解析
            if (!parsePermission(pkg, res, parser, outError)) {
                return null;
            }
      ....
        } 
        }
  }
}
```

##### parseBaseApplication：

\build\android\frameworks\base\core\java\android\content\pm\PackageParser.java

解析Application标签

```
private boolean parseBaseApplication(Package owner, Resources res,
            XmlResourceParser parser, int flags, String[] outError)
  while ((type = parser.next()) != XmlPullParser.END_DOCUMENT
                && (type != XmlPullParser.END_TAG || parser.getDepth() > innerDepth)) {
    //获取"application"子标签的标签内容
    String tagName = parser.getName();
    //如果标签是"activity"
        if (tagName.equals("activity")) {
      //解析Activity的信息，把activity加入Package对象
            Activity a = parseActivity(owner, res, parser, flags, outError, cachedArgs, false,
                    owner.baseHardwareAccelerated);
            if (a == null) {
                mParseError = PackageManager.INSTALL_PARSE_FAILED_MANIFEST_MALFORMED;
                return false;
            }
 
            hasActivityOrder |= (a.order != 0);
            owner.activities.add(a);
 
        } else if (tagName.equals("receiver")) {
      //如果标签是"receiver"，获取receiver信息，加入Package对象
            Activity a = parseActivity(owner, res, parser, flags, outError, cachedArgs,
                    true, false);
            if (a == null) {
                mParseError = PackageManager.INSTALL_PARSE_FAILED_MANIFEST_MALFORMED;
                return false;
            }
 
            hasReceiverOrder |= (a.order != 0);
            owner.receivers.add(a);
 
        }else if (tagName.equals("service")) {
      //如果标签是"service"，获取service信息，加入Package对象
            Service s = parseService(owner, res, parser, flags, outError, cachedArgs);
            if (s == null) {
                mParseError = PackageManager.INSTALL_PARSE_FAILED_MANIFEST_MALFORMED;
                return false;
            }
 
            hasServiceOrder |= (s.order != 0);
            owner.services.add(s);
 
        }else if (tagName.equals("provider")) {
      //如果标签是"provider"，获取provider信息，加入Package对象
            Provider p = parseProvider(owner, res, parser, flags, outError, cachedArgs);
            if (p == null) {
                mParseError = PackageManager.INSTALL_PARSE_FAILED_MANIFEST_MALFORMED;
                return false;
            }
 
            owner.providers.add(p);
        }
    ...
  }
}
```

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/a636bc8a81694523a29ca0d1e2c04854~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1315&h=726&s=105927&e=png&b=000000)

##### 安装apk

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/974523ccab1647269199a660d0a468a1~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=872&h=789&s=78568&e=png&a=1&b=2e6cc9)

APK拷贝完成后，进入真正的安装

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/c34cf0a0af32428fbd33e37cea22c7c6~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=662&h=616&s=58656&e=png&b=fdfdfd)

###### processPendingInstall：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

主要是post了一个消息，这样安装过程将以异步的方式继续执行。

```
private void processPendingInstall(final InstallArgs args, final int currentStatus) {
        if (args.mMultiPackageInstallParams != null) {
            args.mMultiPackageInstallParams.tryProcessInstallRequest(args, currentStatus);
        } else {
            // 1. 设置安装参数
            PackageInstalledInfo res = createPackageInstalledInfo(currentStatus);
            // 2. 创建一个新线程，处理安装参数，进行安装
            processInstallRequestsAsync(
                    res.returnCode == PackageManager.INSTALL_SUCCEEDED,
                    Collections.singletonList(new InstallRequest(args, res)));
        }
    }
 
private void processInstallRequestsAsync(boolean success,
            List<InstallRequest> installRequests) {
        mHandler.post(() -> {
            if (success) {
                for (InstallRequest request : installRequests) {
                    // 1. 如果之前安装失败，清除无用信息
                    request.args.doPreInstall(request.installResult.returnCode);
                }
                synchronized (mInstallLock) {
                    // 2. installPackagesTracedLI是安装过程的核心方法
                    // 然后调用installPackagesLI进行安装
                    installPackagesTracedLI(installRequests);
                }
                for (InstallRequest request : installRequests) {
                    // 3. 如果安装失败，清除无用信息
                    request.args.doPostInstall(
                            request.installResult.returnCode, request.installResult.uid);
                }
            }
            for (InstallRequest request : installRequests) {
                restoreAndPostInstall(request.args.user.getIdentifier(), request.installResult,
                        new PostInstallData(request.args, request.installResult, null));
            }
        });
    }
 
int doPreInstall(int status) {
            if (status != PackageManager.INSTALL_SUCCEEDED) {
                // 清除无用信息
                cleanUp();
            }
            return status;
        }
 
int doPostInstall(int status, int uid) {
            // 安装失败也会调用这个
            if (status != PackageManager.INSTALL_SUCCEEDED) {
                // 调用cleanUp清除无用信息
                cleanUp();
            }
            return status;
        }
```

###### installPackagesLI：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

在installPackagesLI方法中，以原子的方式安装一个或多个包。此操作分为四个阶段：

1）Prepare准备：分析任何当前安装状态，分析包并对其进行初始验证。

2）Scan 扫描：扫描分析准备阶段拿到的包

3） Reconcile 协调：包的扫描结果，用于协调可能向系统中添加的一个或多个包

4） Commit 提交：提交所有扫描的包并更新系统状态，这是安装流程中唯一可以修改系统状态的地方放，必须在此阶段之前确定所有的可预测的错误

5）完成APK的安装

```
private void installPackagesLI(List<InstallRequest> requests) {
 
    .....
 
    // 1. Prepare 准备：分析任何当前安装状态，分析包并对其进行初始验证
    prepareResult = preparePackageLI(request.args, request.installResult);
                
    .....               
 
    // 2. Scan 扫描：扫描分析准备阶段拿到的包
    final ScanResult result = scanPackageTracedLI(
                            prepareResult.packageToScan, prepareResult.parseFlags,
                            prepareResult.scanFlags, System.currentTimeMillis(),
                            request.args.user, request.args.abiOverride);
    ....    
 
    // 3. Reconcile 协调：包的扫描结果，用于协调可能向系统中添加的一个或多个包
    ReconcileRequest reconcileRequest = new ReconcileRequest(preparedScans, installArgs,
                    installResults,
                    prepareResults,
                    mSharedLibraries,
                    Collections.unmodifiableMap(mPackages), versionInfos,
                    lastStaticSharedLibSettings);
    
    ......
 
    // 4. Commit 提交：提交所有扫描的包并更新系统状态。这是安装流程中唯一可以修改系统状态的地方，
    // 必须在此阶段之前确定所有的可预测的错误
    commitPackagesLocked(commitRequest);
    
    .....
 
    // 5. 完成APK的安装
    executePostCommitSteps(commitRequest);
       
}
```

###### executePostCommitSteps：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

安装APK，并为新的代码路径准备应用程序配置文件，并在此检查是否需要dex优化。

如果是直接安装新包，会为新的代码路径准备应用程序配置文件；如果是替换安装，其主要过程为更新设置，清除原有的某些APP数据，重新生成相关的app数据目录等步骤，同时要区分系统应用替换和非系统应用替换。而安装新包，则直接更新设置，生成APP数据即可

```
private void executePostCommitSteps(CommitRequest commitRequest) {
       
    for (ReconciledPackage reconciledPkg : commitRequest.reconciledPackages.values()) {
            
        ......
 
       // 1) 进行安装
        prepareAppDataAfterInstallLIF(pkg);
      //  2) 如果需要替换安装，则需要清除原有的App数据
        if (reconciledPkg.prepareResult.clearCodeCache) {
            clearAppDataLIF(pkg, UserHandle.USER_ALL, FLAG_STORAGE_DE | FLAG_STORAGE_CE
                | FLAG_STORAGE_EXTERNAL | Installer.FLAG_CLEAR_CODE_CACHE_ONLY);
        }
        
        ...
            
       // 3) 为新的代码路径准备应用程序配置文件。这需要在调用dexopt之前完成，以便任何安装时配置文件都可以用于优化
        mArtManagerService.prepareAppProfiles(
                    pkg,
                    resolveUserIds(reconciledPkg.installArgs.user.getIdentifier()),
                    /* updateReferenceProfileContent= */ true);
 
       // 4) 检查是否需要优化dex文件
        final boolean performDexopt =
                    (!instantApp || Global.getInt(mContext.getContentResolver(),
                    Global.INSTANT_APP_DEXOPT_ENABLED, 0) != 0)
                    && !pkg.isDebuggable()
                    && (!onIncremental);
 
        if (performDexopt) {               
 
 
           // 5) 执行dex优化
            mPackageDexOptimizer.performDexOpt(pkg, realPkgSetting,
                        null /* instructionSets */,
                        getOrCreateCompilerPackageStats(pkg),
                        mDexManager.getPackageUseInfoOrDefault(packageName),
                        dexoptOptions);
                
        }
 
            
        BackgroundDexOptService.notifyPackageChanged(packageName);
 
        notifyPackageChangeObserversOnUpdate(reconciledPkg);
    }
}
```

###### prepareAppDataAfterInstallLIF：

\build\android\frameworks\base\services\core\java\com\android\server\pm\PackageManagerService.java

通过一系列的调用，最终会调用到Installer.java的createAppData()方法进行安装，交给installed进程进行APK的安

```
private void prepareAppDataAfterInstallLIF(AndroidPackage pkg) {
        
    ..... 
 
    for (UserInfo user : mUserManager.getUsers(false /*excludeDying*/)) {
           
        ......
 
        if (ps.getInstalled(user.id)) {
            // TODO: when user data is locked, mark that we're still dirty
            prepareAppDataLIF(pkg, user.id, flags);
                
        }
    }
}
 
 
private void prepareAppDataLIF(AndroidPackage pkg, int userId, int flags) {
    if (pkg == null) {
        Slog.wtf(TAG, "Package was null!", new Throwable());
        return;
    }
    // 调用prepareAppDataLeafLIF方法
    prepareAppDataLeafLIF(pkg, userId, flags);
}
 
 
private void prepareAppDataLeafLIF(AndroidPackage pkg, int userId, int flags) {
        
    ......
 
    try {
        // 调用Install守护进程的入口
        ceDataInode = mInstaller.createAppData(volumeUuid, packageName, userId, flags,
                    appId, seInfo, pkg.getTargetSdkVersion());
    } catch (InstallerException e) {
        if (pkg.isSystem()) {
             destroyAppDataLeafLIF(pkg, userId, flags);
             try {
                 ceDataInode = mInstaller.createAppData(volumeUuid, packageName, userId,                 
                     flags,appId, seInfo, pkg.getTargetSdkVersion());
                    
             } catch (InstallerException e2) {
                 ......
             }
         }
    }
}
```

###### Installer.java：

\build\android\frameworks\base\services\core\java\com\android\server\pm\Installer.java

```
 public long createAppData(String uuid, String packageName, int userId, int flags, int     
        appId,String seInfo, int targetSdkVersion) throws InstallerException {
    if (!checkBeforeRemote()) return -1;
    try {
        // mInstalld为Install的对象，即通过Binder调用到进程installd,
        // 最终调用installd的createAppData()
        return mInstalld.createAppData(uuid, packageName, userId, flags, appId, seInfo,
                    targetSdkVersion);
    } catch (Exception e) {
        throw InstallerException.from(e);
    }
}
```

APK的安装主要分为以下四步：

1）将APK的信息通过IO流的形式写入到 PackageInstaller.Session中

2）调用PackageInstaller.Session的commit方法，将APK的信息交由PKMS处理。

3）拷贝APK

4）最后进行安装

```
   system_server以system用户的身份运行，PMS运行在system_server中，所以PMS也是system用户。installd是root用户，system用户并没有访问应用程序目录的权限。但是作为root用户的installd却可以访问data/data/下的目录，这就是installd存在的原因
   最终是交给Installd守护进程进行真正的安装操作
   
   PackageManagerService通过套接字的方式访问installd服务进程，在Android启动脚本init.rc中通过服务配置启动了installd服务进程。
   service installd /system/bin/installd
    class main
    socket installd stream 600 system system
```

 struct cmdinfo cmds[] = {  // { 命令名称， 参数个数，命令执行函数}  { "ping", 0, do_ping },  { "install", 3, do_install },  { "create_app_data", 7, do_create_app_data },  { "dexopt", 3, do_dexopt },  { "movedex", 2, do_move_dex },  { "rmdex", 1, do_rm_dex },  { "remove", 2, do_remove },  { "rename", 2, do_rename },  { "fixuid", 3, do_fixuid },  { "freecache", 1, do_free_cache },  { "rmcache", 1, do_rm_cache },  { "protect", 2, do_protect },  { "getsize", 4, do_get_size },  { "rmuserdata", 2, do_rm_user_data },  { "movefiles", 0, do_movefiles },  { "linklib", 2, do_linklib },  { "unlinklib", 1, do_unlinklib },  { "mkuserdata", 3, do_mk_user_data },  { "rmuser", 1, do_rm_user },  { "cloneuserdata", 3, do_clone_user_data },  };

```
int install(const char *pkgname, uid_t uid, gid_t gid)
{
    char pkgdir[PKG_PATH_MAX];//程序目录路径最长为256
    char libdir[PKG_PATH_MAX];//程序lib路径最长为256
    //权限判断
    if ((uid < AID_SYSTEM) || (gid < AID_SYSTEM)) {
        ALOGE("invalid uid/gid: %d %d\n", uid, gid);
        return -1;
    }
    //组合应用程序安装目录pkgdir=/data/data/应用程序包名
    if (create_pkg_path(pkgdir, pkgname, PKG_DIR_POSTFIX, 0)) {
        ALOGE("cannot create package path\n");
        return -1;
    }
    //组合应用程序库目录libdir=/data/data/应用程序包名/lib
    if (create_pkg_path(libdir, pkgname, PKG_LIB_POSTFIX, 0)) {
        ALOGE("cannot create package lib path\n");
        return -1;
    }
    //创建目录pkgdir=/data/data/应用程序包名
    if (mkdir(pkgdir, 0751) < 0) {
        ALOGE("cannot create dir '%s': %s\n", pkgdir, strerror(errno));
        return -errno;
    }
    //修改/data/data/应用程序包名目录的权限
    if (chmod(pkgdir, 0751) < 0) {
        ALOGE("cannot chmod dir '%s': %s\n", pkgdir, strerror(errno));
        unlink(pkgdir);
        return -errno;
    }
    //创建目录libdir=/data/data/应用程序包名/lib
    if (mkdir(libdir, 0755) < 0) {
        ALOGE("cannot create dir '%s': %s\n", libdir, strerror(errno));
        unlink(pkgdir);
        return -errno;
    }
    //修改/data/data/应用程序包名/lib目录的权限
    if (chmod(libdir, 0755) < 0) {
        ALOGE("cannot chmod dir '%s': %s\n", libdir, strerror(errno));
        unlink(libdir);
        unlink(pkgdir);
        return -errno;
    }
    //修改/data/data/应用程序包名目录的所有权限
    if (chown(libdir, AID_SYSTEM, AID_SYSTEM) < 0) {
        ALOGE("cannot chown dir '%s': %s\n", libdir, strerror(errno));
        unlink(libdir);
        unlink(pkgdir);
        return -errno;
    }
    //修改/data/data/应用程序包名/lib目录的所有权限
    if (chown(pkgdir, uid, gid) < 0) {
        ALOGE("cannot chown dir '%s': %s\n", pkgdir, strerror(errno));
        unlink(libdir);
        unlink(pkgdir);
        return -errno;
    }
    return 0;
}
```