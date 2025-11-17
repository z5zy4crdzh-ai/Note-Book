### All

```
:~$ grep -r "boot_progress" logcat_1.txt
01-01 08:00:23.604 I/boot_progress_start(67): 21272                     // 系统进入用户空间，标志着kernel启动完成
01-01 08:00:25.351 I/boot_progress_preload_start(67): 23020             // Zygote启动       
01-01 08:00:27.844 I/boot_progress_preload_end(67): 25513               // Zygote结束
01-01 08:00:28.338 I/boot_progress_system_run(698): 26007               // Systemserver ready,开始启动android系统服务
01-01 08:00:29.054 I/boot_progress_pms_start(698): 26722                // PMS开始扫描安装的应用
01-01 08:00:29.360 I/boot_progress_pms_system_scan_start(698): 27029    // PMS先行扫描/system目录下的安装包
01-01 08:00:31.208 I/boot_progress_pms_data_scan_start(698): 28877      // PMS扫描/data目录下的安装包 
01-01 08:00:31.241 I/boot_progress_pms_scan_end(698): 28910             // PMS扫描结束
01-01 08:00:31.677 I/boot_progress_pms_ready(698): 29346                // PMS就绪
11-16 14:49:18.149 I/boot_progress_ams_ready(698): 30950                // AMS就绪
11-16 14:49:19.151 I/boot_progress_enable_screen(698): 31952            // AMS启动完成后开始激活屏幕，从此以后屏幕才能响应用户的触摸，它在WindowManagerService发出退出开机动画的时间节点之前
```

#### boot_progress_start

```
// frameworks/base/core/jni/AndroidRuntime.cpp
void AndroidRuntime::start(const char* className, const Vector<String8>& options, bool zygote)
{
    ALOGD(">>>>>> START %s uid %d <<<<<<\n",
            className != NULL ? className : "(unknown)", getuid());

    static const String8 startSystemServer("start-system-server");

    /*
     * 'startSystemServer == true' means runtime is obsolete and not run from
     * init.rc anymore, so we print out the boot start event here.
     */
    for (size_t i = 0; i < options.size(); ++i) {
        if (options[i] == startSystemServer) {
           /* track our progress through the boot sequence */
           const int LOG_BOOT_PROGRESS_START = 3000;
           LOG_EVENT_LONG(LOG_BOOT_PROGRESS_START,  ns2ms(systemTime(SYSTEM_TIME_MONOTONIC)));   // 打印log，进入用户空间，kernel完成
        }
    }
```

#### boot_progress_preload_start

```
// frameworks/base/core/java/com/android/internal/os/ZygoteInit.java
public static void main(String[] argv){
    if(!enableLazyPreload){
        bootTimingsTraceLog.traceBegin("ZygotePreload");
        EventLog.writeEvent(BOOT_PROGRESS_PRELOAD_START, SystemClock.uptimeMillis());
        preload(bootTimingsTraceLog);
        EventLog.writeEvent(BOOT_PROGRESS_PRELOAD_END, SystemClock.uptimeMillis());
        bootTimingsTraceLog.traceEnd();
    }
}
```

#### boot_progress_system_run

```
// frameworks/base/services/java/com/android/server/SystemServer.java
private void run() {
   Slog.i(TAG, "Entered the Android system server!");
   final long uptimeMillis = SystemClock.elapsedRealtime();
   EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_SYSTEM_RUN, uptimeMillis);
   if (!mRuntimeRestart){
            FrameworkStatsLog.write(FrameworkStatsLog.BOOT_TIME_EVENT_ELAPSED_TIME_REPORTED,
FrameworkStatsLog.BOOT_TIME_EVENT_ELAPSED_TIME__EVENT__SYSTEM_SERVER_INIT_START,uptimeMillis);
      }
    }
```

#### boot_progress_pms_start

```
    public PackageManagerService(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
        LockGuard.installLock(mPackages, LockGuard.INDEX_PACKAGES);
        Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "create package manager");
        //第一阶段BOOT_PROGRESS_PMS_START 开始
        EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_START,
                SystemClock.uptimeMillis());
 
        if (mSdkVersion <= 0) {
            Slog.w(TAG, "**** ro.build.version.sdk not set!");
        }
        // 上下文
        mContext = context;
        // 一般为false，即非工厂生产模式
        // 当设置了启动模式是工厂模式后，开机启动后进入工厂测试程序，
        mFactoryTest = factoryTest;
        mOnlyCore = onlyCore; //// onlyCore为true表示只处理系统应用，通常为false
        //1. 构造 DisplayMetrics ，保存分辨率等相关信息
        mMetrics = new DisplayMetrics();
        //2. 创建Installer对象，与installd交互，这个类协助安装过程，更多的是将针对文件/路径的操作放在c和cpp里面去实现，真正的工作是由install承担的，Install只是通过named socket "installd" 连接 install
        mInstaller = installer;
 
        // Create sub-components that provide services / data. Order here is important.
        //创建提供服务/数据的子组件。这里的顺序很重要,使用到了两个重要的同步锁
        // synchronized可以保证方法或者代码块在运行时，同一时刻只有一个方法可以进入到临界区
        synchronized (mInstallLock) {  //用来保护所有安装apk的访问权限，此操作通常涉及繁重的磁盘数据读写等操作，并且是单线程操作，故有时候会处理很慢
        synchronized (mPackages) {  // 用来解析内存中所有apk的package信息及相关状态
            // Expose private service for system components to use.
            // 公开系统组件使用的私有服务
            // 本地服务
            LocalServices.addService(
                    PackageManagerInternal.class, new PackageManagerInternalImpl());
            // 多用户管理服务
            sUserManager = new UserManagerService(context, this,
                    new UserDataPreparer(mInstaller, mInstallLock, mContext, mOnlyCore), mPackages);
            //解析所有Android组件类型对象[activities, services, providers and receivers]
            mComponentResolver = new ComponentResolver(sUserManager,
                    LocalServices.getService(PackageManagerInternal.class),
                    mPackages);
            //3. 创建mPermissionManager对象，进行权限管理；
            mPermissionManager = PermissionManagerService.create(context,
                    mPackages /*externalLock*/);
            mDefaultPermissionPolicy = mPermissionManager.getDefaultPermissionGrantPolicy();
            //创建Settings对象，结构体
            //构造Settings类，保存安装包信息，清除路径不存在的孤立应用，特别的是Settings针对shareUser和origPackage做了特别的关照。另外，为了加速启动速度，Settings的内容会写入/data/system/packages.xml、packages-backup.xml和packages.list，下次启动时会直接载入。
            // 主要涉及 /data/system/目录的packages.xml，packages-backup.xml， packages.list， packages-stopped.xml，packages-stopped-backup.xml等文件
            mSettings = new Settings(Environment.getDataDirectory(),
                    mPermissionManager.getPermissionSettings(), mPackages);
        }
        }
        // 添加system, phone, log, nfc, bluetooth, shell，se，networkstack 这8种 shareUserId 到 mSettings
        // 不同的APK会具有不同的userId，因此运行时属于不同的进程中，而不同进程中的资源是不共享的（比如只能访问/data/data/自己包名下面的文件），保障了程序运行的稳定。然后在有些时候，我们自己开发了多个APK并且需要他们之间互相共享资源，那么就需要通过设置shareUserId来实现这一目的
        mSettings.addSharedUserLPw("android.uid.system", Process.SYSTEM_UID,
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.phone", RADIO_UID,    // Phone进程使用的UID, int类型的UID对应起来，UID的定义在Process.java
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.log", LOG_UID,        
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.nfc", NFC_UID,
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.bluetooth", BLUETOOTH_UID,
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.shell", SHELL_UID,    // shell进程使用的UID
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.se", SE_UID,
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
        mSettings.addSharedUserLPw("android.uid.networkstack", NETWORKSTACK_UID,
                ApplicationInfo.FLAG_SYSTEM, ApplicationInfo.PRIVATE_FLAG_PRIVILEGED);
 
        String separateProcesses = SystemProperties.get("debug.separate_processes");
        if (separateProcesses != null && separateProcesses.length() > 0) {
            if ("*".equals(separateProcesses)) {
                mDefParseFlags = PackageParser.PARSE_IGNORE_PROCESSES;
                mSeparateProcesses = null;
                Slog.w(TAG, "Running with debug.separate_processes: * (ALL)");
            } else {
                mDefParseFlags = 0;
                mSeparateProcesses = separateProcesses.split(",");
                Slog.w(TAG, "Running with debug.separate_processes: "
                        + separateProcesses);
            }
        } else {
            mDefParseFlags = 0;
            mSeparateProcesses = null;
        }
        //5. 构造PackageDexOptimizer及DexManager类，处理dex优化
    //DexOpt优化 ,优化 DEX 文件是为了提高应用程序的运行效率和启动速度，DEX文件是Android应用程序的可执行文件格式，其中包含了应用程序的字节码和相关信息
        mPackageDexOptimizer = new PackageDexOptimizer(installer, mInstallLock, context,
                "*dexopt*");
        mDexManager = new DexManager(mContext, this, mPackageDexOptimizer, installer, mInstallLock);
        // ART虚拟机管理服务 ART 的全称是 Android Runtime，它是 Android 系统的应用程序执行环境，负责将应用程序的字节码转换为机器代码并执行，ART 在应用安装时会预先将应用的字节码编译为本地机器代码
        mArtManagerService = new ArtManagerService(mContext, this, installer, mInstallLock);
        mMoveCallbacks = new MoveCallbacks(FgThread.get().getLooper());
 
        mViewCompiler = new ViewCompiler(mInstallLock, mInstaller);
        //权限变化监听器
        mOnPermissionChangeListeners = new OnPermissionChangeListeners(
                FgThread.get().getLooper());
        // 获取默认分辨率
        getDefaultDisplayMetrics(context, mMetrics);
 
        Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "get system config");
        //6.创建SystemConfig实例，获取系统配置信息，配置共享lib库,xml文件中定义的各个节点读取出来
        // 拿到SystemConfig()的对象，其中会调用SystemConfig的readPermissions()完成权限的读取
        SystemConfig systemConfig = SystemConfig.getInstance();
        //获取该设备支持的功能，这些功能是从系统配置文件中读取的
        mAvailableFeatures = systemConfig.getAvailableFeatures();
        Trace.traceEnd(TRACE_TAG_PACKAGE_MANAGER);
 
        mProtectedPackages = new ProtectedPackages(mContext);
 
        mApexManager = new ApexManager(context);
 
 
            //启动"PackageManager"线程，负责apk的安装、卸载, 用HanderThread来实现
            mHandlerThread = new ServiceThread(TAG,
                    Process.THREAD_PRIORITY_BACKGROUND, true /*allowIo*/);
            mHandlerThread.start();
            // 应用handler  PackageHandler是PKMS中的内部类,绑定到ServiceThread的消息队列，传递 mHandlerThread 内部的一个 looper
            mHandler = new PackageHandler(mHandlerThread.getLooper());
            // 进程记录handler
            mProcessLoggingHandler = new ProcessLoggingHandler();
            //Watchdog监听ServiceThread是否超时：10分钟
            Watchdog.getInstance().addThread(mHandler, WATCHDOG_TIMEOUT);
            // Instant应用注册
            mInstantAppRegistry = new InstantAppRegistry(this);
            // 共享lib库配置
            ArrayMap<String, SystemConfig.SharedLibraryEntry> libConfig
                    = systemConfig.getSharedLibraries();
            final int builtInLibCount = libConfig.size();
            for (int i = 0; i < builtInLibCount; i++) {
                String name = libConfig.keyAt(i);
                SystemConfig.SharedLibraryEntry entry = libConfig.valueAt(i);
                addBuiltInSharedLibraryLocked(entry.filename, name);
            }
 
            // Now that we have added all the libraries, iterate again to add dependency
            // information IFF their dependencies are added.
            long undefinedVersion = SharedLibraryInfo.VERSION_UNDEFINED;
            for (int i = 0; i < builtInLibCount; i++) {
                String name = libConfig.keyAt(i);
                SystemConfig.SharedLibraryEntry entry = libConfig.valueAt(i);
                final int dependencyCount = entry.dependencies.length;
                for (int j = 0; j < dependencyCount; j++) {
                    final SharedLibraryInfo dependency =
                        getSharedLibraryInfoLPr(entry.dependencies[j], undefinedVersion);
                    if (dependency != null) {
                        getSharedLibraryInfoLPr(name, undefinedVersion).addDependency(dependency);
                    }
                }
            }
            // 读取安装相关SELinux策略
            SELinuxMMAC.readInstallPolicy();
 
            Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "loadFallbacks");
            // 返回栈加载
            FallbackCategoryProvider.loadFallbacks();
            Trace.traceEnd(TRACE_TAG_PACKAGE_MANAGER);
 
            Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "read user settings");
             // 判断是否是第一次启动
            mFirstBoot = !mSettings.readLPw(sUserManager.getUsers(false));
            Trace.traceEnd(TRACE_TAG_PACKAGE_MANAGER);
 
            // Clean up orphaned packages for which the code path doesn't exist
            // and they are an update to a system app - caused by bug/32321269
            // 清理代码路径不存在的孤立软件包
            final int packageSettingCount = mSettings.mPackages.size();
            for (int i = packageSettingCount - 1; i >= 0; i--) {
                PackageSetting ps = mSettings.mPackages.valueAt(i);
                if (!isExternal(ps) && (ps.codePath == null || !ps.codePath.exists())
                        && mSettings.getDisabledSystemPkgLPr(ps.name) != null) {
                    mSettings.mPackages.removeAt(i);
                    mSettings.enableSystemPackageLPw(ps.name);
                }
            }
           // 如果不是首次启动，也不是CORE应用，则拷贝预编译的DEX文件
            if (!mOnlyCore && mFirstBoot) {
                requestCopyPreoptedFiles();
            }
 
.....
.....
    
   
    // 这个类表示它服务处理设置和读取包的各种状态，它是动态的，比如userId，shareUser、permission、signature以及origPackg相关信息
    
     Settings(File dataDir, PermissionSettings permission,
            Object lock) {
        mLock = lock;
        mPermissions = permission;
        mRuntimePermissionsPersistence = new RuntimePermissionPersistence(mLock);
        //mSystemDir指向目录"/data/system"
        mSystemDir = new File(dataDir, "system");
        //创建 "/data/system"
        mSystemDir.mkdirs();
        //设置权限
        FileUtils.setPermissions(mSystemDir.toString(),
                FileUtils.S_IRWXU|FileUtils.S_IRWXG
                |FileUtils.S_IROTH|FileUtils.S_IXOTH,
                -1, -1);
        //(1)指向目录"/data/system/packages.xml"
        mSettingsFilename = new File(mSystemDir, "packages.xml");
        //(2)指向目录"/data/system/packages-backup.xml
        mBackupSettingsFilename = new File(mSystemDir, "packages-backup.xml");
        //(3)指向目录"/data/system/packages.list"
        mPackageListFilename = new File(mSystemDir, "packages.list");
        FileUtils.setPermissions(mPackageListFilename, 0640, SYSTEM_UID, PACKAGE_INFO_GID);
 
        final File kernelDir = new File("/config/sdcardfs");
        mKernelMappingFilename = kernelDir.exists() ? kernelDir : null;
 
        // Deprecated: Needed for migration
        //(4)指向目录"/data/system/packages-stopped.xml"
        mStoppedPackagesFilename = new File(mSystemDir, "packages-stopped.xml");
        //(5) 指 向 目 录 "/data/system/packages-stopped-backup.xml"
        mBackupStoppedPackagesFilename = new File(mSystemDir, "packages-stopped-backup.xml");
    }
```

#### boot_progress_pms_system_scan_start

1 从init.rc中获取环境变量BOOTCLASSPATH和SYSTEMSERVERCLASSPATH； 2 对于旧版本升级的情况，将安装时获取权限变更为运行时申请权限； 3 扫描system/vendor/product/odm/oem等目录的priv-app、app、overlay包； 4 清除安装时临时文件以及其他不必要的信息。

```
 public PackageManagerService(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
......
 //第二阶段,扫描系统阶段
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_SYSTEM_SCAN_START,
                    startTime);
            // 从init.rc中获取环境变量BOOTCLASSPATH和 SYSTEMSERVERCLASSPATH；
            //获取环境变量，init.rc
            final String bootClassPath = System.getenv("BOOTCLASSPATH");
            final String systemServerClassPath = System.getenv("SYSTEMSERVERCLASSPATH");
 
            if (bootClassPath == null) {
                Slog.w(TAG, "No BOOTCLASSPATH found!");
            }
 
            if (systemServerClassPath == null) {
                Slog.w(TAG, "No SYSTEMSERVERCLASSPATH found!");
            }
            // 创建system/framework目录
            File frameworkDir = new File(Environment.getRootDirectory(), "framework");
            // 获取内部版本
            final VersionInfo ver = mSettings.getInternalVersion();
            // 判断fingerprint是否有更新 当前设备的指纹信息 Build.FINGERPRINT 和应用程序版本的指纹信息 ver.fingerprint 是否相等
            mIsUpgrade = !Build.FINGERPRINT.equals(ver.fingerprint);
            if (mIsUpgrade) {
                logCriticalInfo(Log.INFO,
                        "Upgrading from " + ver.fingerprint + " to " + Build.FINGERPRINT);
            }
 
            // when upgrading from pre-M, promote system app permissions from install to runtime
        //对于旧版本升级的情况，将安装时获取权限变更为运行时申请权限；
        // 对于Android M（6）之前版本升级上来的情况，需将系统应用程序权限从安装升级到运行时
            mPromoteSystemApps =
                    mIsUpgrade && ver.sdkVersion <= Build.VERSION_CODES.LOLLIPOP_MR1;
 
            // When upgrading from pre-N, we need to handle package extraction like first boot,
            // as there is no profiling data available.
        // 对于Android N（7）之前版本升级上来的情况，需像首次启动一样处理package
            mIsPreNUpgrade = mIsUpgrade && ver.sdkVersion < Build.VERSION_CODES.N;
 
            mIsPreNMR1Upgrade = mIsUpgrade && ver.sdkVersion < Build.VERSION_CODES.N_MR1;
            mIsPreQUpgrade = mIsUpgrade && ver.sdkVersion < Build.VERSION_CODES.Q;
 
            int preUpgradeSdkVersion = ver.sdkVersion;
 
            // save off the names of pre-existing system packages prior to scanning; we don't
            // want to automatically grant runtime permissions for new system apps
        // 在扫描之前保存预先存在的系统package的名称，不希望自动为新系统应用授予运行时权限
            if (mPromoteSystemApps) {
                Iterator<PackageSetting> pkgSettingIter = mSettings.mPackages.values().iterator();
                while (pkgSettingIter.hasNext()) {
                    PackageSetting ps = pkgSettingIter.next();
                    if (isSystemApp(ps)) {
                        mExistingSystemPackages.add(ps.name);
                    }
                }
            }
            // 准备解析package的缓存
            mCacheDir = preparePackageParserCache();
 
            // Set flag to monitor and not change apk file paths when
            // scanning install directories.
            // 设置flag，不在扫描安装时更改文件路径,监控apk路径
            int scanFlags = SCAN_BOOTING | SCAN_INITIAL;
 
            if (mIsUpgrade || mFirstBoot) {
                scanFlags = scanFlags | SCAN_FIRST_BOOT_OR_UPGRADE;
            }
 
            // Collect vendor/product/product_services overlay packages. (Do this before scanning
            // any apps.)
            // For security and version matching reason, only consider overlay packages if they
            // reside in the right directory.
 
        //扫描以下路径：
        // /vendor/overlay、/product/overlay、/product_services/overlay、/odm/overlay、/oem/ overlay、
        // /system/framework /system/priv-app、/system/app、/vendor/priv- app、
        // /vendor/app、/odm/priv-app、/odm/app、/oem/app、/oem/priv-app、 /product/priv-app、
        // /product/app、/product_services/priv- app、 /product_services/app、/product_services/priv-app
            scanDirTracedLI(new File(VENDOR_OVERLAY_DIR),
                    mDefParseFlags
                    | PackageParser.PARSE_IS_SYSTEM_DIR,
                    scanFlags
                    | SCAN_AS_SYSTEM
                    | SCAN_AS_VENDOR,
                    0);
 
..... //省略相同的scanDirTracedLI方法
 
 
            //delete tmp files
            // 清除安装时临时文件以及其他不必要的信息。
            deleteTempPackageFiles();
 
            final int cachedSystemApps = PackageParser.sCachedPackageReadCount.get();
 
            // Remove any shared userIDs that have no associated packages
            // 删除没有关联应用的共享UID标识
            mSettings.pruneSharedUsersLPw();
 
...
...
}
```

![Screenshot_20231205_151807]()

#### boot_progress_pms_data_scan_start

扫描/data/app和/data/app-private目录下的文件。/data目录用来存储所有用户的个人数据和配置文件 遍历possiblyDeletedUpdatedSystemApps列表，如果这个系统App的包信息不在PMS的变量mPackages中，说明是残留的App信息，后续会删除它的数据。如果这个系统App的包信息在mPackages中，说明是存在于Data分区，不属于系统App，那么移除其系统权限。

```
 public PackageManagerService(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
.....
 //对于不仅仅解析核心应用的情况下，还处理data目录的应用信息，及时更新，去除不必要的数据。
            if (!mOnlyCore) {
                //第三阶段 开始扫描data分区
                EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_DATA_SCAN_START,
                        SystemClock.uptimeMillis());
 
 // 如果更新不再存在，则完全删除该应用。否则，撤消其系统权限
                for (int i = possiblyDeletedUpdatedSystemApps.size() - 1; i >= 0; --i) {
                    final String packageName = possiblyDeletedUpdatedSystemApps.get(i);
                    final PackageParser.Package pkg = mPackages.get(packageName);
                    final String msg;
....
 
              try {
                            //扫描apk
                            scanPackageTracedLI(scanFile, reparseFlags, rescanFlags, 0, null);
                        } catch (PackageManagerException e) {
                            Slog.e(TAG, "Failed to parse original system package: "
                                    + e.getMessage());
                        }
 
 ....
    }
 
 // Uncompress and install any stubbed system applications.
                // This must be done last to ensure all stubs are replaced or disabled.
                // 解压缩并安装任何存根系统应用程序。必须最后执行此操作以确保替换或禁用所有存根
                installSystemStubPackages(stubSystemApps, scanFlags);
 
 
     // Resolve the storage manager.
            // 获取storage manager包名
            mStorageManagerPackage = getStorageManagerPackageName();
 
// 解决受保护的action过滤器。只允许setup wizard（开机向导）为这些action 设置高优先级过滤器
            mSetupWizardPackage = getSetupWizardPackageName();
 
 
                // 更新客户端以确保持有正确的共享库路径
            updateAllSharedLibrariesLocked(null, Collections.unmodifiableMap(mPackages));
 
 
 
            // Now that we know all the packages we are keeping,
            // read and update their last usage times.
        // 读取并更新要保留的package的上次使用时间
            mPackageUsage.read(mPackages);
            mCompilerStats.read();
 
 
....
 
}
```

#### boot_progress_pms_scan_end

sdk版本变更，更新权限； OTA升级后首次启动，清除不必要的缓存数据； 权限等默认项更新完后，清理相关数据； 把Settings的内容保存到packages.xml中，这样此后PMS再次创建时会读到此前保存的Settings的内容

```
 public PackageManagerService(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
.....
 
            //第四阶段 扫描结束阶段
            EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_SCAN_END,
                    SystemClock.uptimeMillis());
....
       // 如果这是第一次启动或来自Android M之前的版本的升级，并且它是正常启动，
        // 那需要在所有已定义的用户中初始化默认的首选应用程序
            if (!onlyCore && (mPromoteSystemApps || mFirstBoot)) {
                for (UserInfo user : sUserManager.getUsers(true)) {
                    mSettings.applyDefaultPreferredAppsLPw(user.id);
                    primeDomainVerificationsLPw(user.id);
                }
            }
 
// 在启动期间确实为系统用户准备存储，因为像SettingsProvider和SystemUI这样的核心系统应用程序无法等待用户启动
            final int storageFlags;
            if (StorageManager.isFileEncryptedNativeOrEmulated()) {
                storageFlags = StorageManager.FLAG_STORAGE_DE;
            } else {
                storageFlags = StorageManager.FLAG_STORAGE_DE | StorageManager.FLAG_STORAGE_CE;
            }
 
....
 // 如果是在OTA之后首次启动，并且正常启动，那需要清除代码缓存目录，但不清除应用程序配置文件
            if (mIsUpgrade && !onlyCore) {
                Slog.i(TAG, "Build fingerprint changed; clearing code caches");
                for (int i = 0; i < mSettings.mPackages.size(); i++) {
                    final PackageSetting ps = mSettings.mPackages.valueAt(i);
                    if (Objects.equals(StorageManager.UUID_PRIVATE_INTERNAL, ps.volumeUuid)) {
                        // No apps are running this early, so no need to freeze
                        clearAppDataLIF(ps.pkg, UserHandle.USER_ALL,
                                FLAG_STORAGE_DE | FLAG_STORAGE_CE | FLAG_STORAGE_EXTERNAL
                                        | Installer.FLAG_CLEAR_CODE_CACHE_ONLY);
                    }
                }
                ver.fingerprint = Build.FINGERPRINT;
            }
....
  //安装Android-Q前的非系统应用程序在Launcher中隐藏他们的图标
            if (!onlyCore && mIsPreQUpgrade) {
                Slog.i(TAG, "Whitelisting all existing apps to hide their icons");
                int size = mSettings.mPackages.size();
                for (int i = 0; i < size; i++) {
                    final PackageSetting ps = mSettings.mPackages.valueAt(i);
                    if ((ps.pkgFlags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                        continue;
                    }
                    ps.disableComponentLPw(PackageManager.APP_DETAILS_ACTIVITY_CLASS_NAME,
                            UserHandle.USER_SYSTEM);
                }
            }
 
            // 仅在权限或其它默认配置更新后清除
            mExistingSystemPackages.clear();
            mPromoteSystemApps = false;
 
            // All the changes are done during package scanning.
            //所有变更均在扫描过程中完成
            ver.databaseVersion = Settings.CURRENT_DATABASE_VERSION;
 
            // can downgrade to reader
            //把Settings的内容保存到packages.xml中
            Trace.traceBegin(TRACE_TAG_PACKAGE_MANAGER, "write settings");
            mSettings.writeLPr();
....
}
```

#### boot_progress_pms_ready

创建PackageInstallerService对象, PackageInstallerService是用于管理安装会话的服务，它会为每次安装过程分配一个SessionId

GC回收内存

```
public PackageManagerService(Context context, Installer installer,
            boolean factoryTest, boolean onlyCore) {
.....
     //第五阶段 准备阶段
    EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_READY,
                    SystemClock.uptimeMillis());
 
....
    //创建PackageInstallerService对象 负责安装应用程序服务
    mInstallerService = new PackageInstallerService(context, this, mApexManager);
...
 
 
 
   // 打开应用之后，及时回收处理
        Runtime.getRuntime().gc();    
 
.....
 
}
```

#### boot_progress_ams_ready

```
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
public void systemReady(final Runnable goingCallback, @NonNull TimingsTraceAndSlog t) {
        t.traceEnd();
        EventLog.writeBootProgressAmsReady(SystemClock.uptimeMillis());
    }
```

#### boot_progress_enable_screen

```
// frameworks/base/services/core/java/com/android/server/wm/ActivityTaskManagerService.java
 @Override
public void enableScreenAfterBoot(boolean booted) {
        writeBootProgressEnableScreen(SystemClock.uptimeMillis());
        mWindowManager.enableScreenAfterBoot();
        synchronized (mGlobalLock) {
            updateEventDispatchingLocked(booted);
        }
 }
```