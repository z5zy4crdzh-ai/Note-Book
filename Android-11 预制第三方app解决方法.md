## Android 11 预制第三方app解决方法

Android原先低版本预制第三方app方案

先创建data/priv-app文件夹

android/device/qcom/trinket/init.target.rc

```
service sec_nvm /vendor/bin/sec_nvm
    class core
    user system
    group system

on post-fs-data
    mkdir /data/vendor/hbtp 0750 system system
    mkdir /persist/qti_fp 0700 system system
    mkdir /data/vendor/nnhal 0700 system system
    mkdir /data/priv-app 0770 system system

```

添加selinux

android/vendor/gtyc/sepolicy/private/file_contexts

```

#preinstall path
/data/priv-app(/.*)?                    u:object_r:apk_data_file:s0

```

修改PMS源码

```
/** Directory where installed applications are stored */
    private static final File sAppInstallDir =
            new File(Environment.getDataDirectory(), "app");
    private static final File sAppPreinstallDir =
             new File(Environment.getDataDirectory(), "priv-app");
.....
    if (!mOnlyCore) {
                EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_PMS_DATA_SCAN_START,
                        SystemClock.uptimeMillis());
                scanDirTracedLI(sAppInstallDir, 0, scanFlags | SCAN_REQUIRE_KNOWN, 0);
                // When it is the first time of device boot, the path of data/priv-app
                // will do scanDirTracedLI without judging whether the apks under the path
                // have been known by the device. Otherwise, SCAN_REQUIRE_KNOWN flag
                // will be required to do function of scanDirTracedLI.
                if(mFirstBoot){
                    Slog.i(TAG, "FirstBoot scanDirTracedLI.");   //添加扫描apk流程
                    scanDirTracedLI(sAppPreinstallDir, 0, scanFlags, 0);
                }else{
                    Slog.i(TAG, "Not FirstBoot scanDirTracedLI.");
                    scanDirTracedLI(sAppPreinstallDir, 0, scanFlags | SCAN_REQUIRE_KNOWN, 0);
                }
                // Remove disable package settings for updated system apps that were
                // removed via an OTA. If the update is no longer present, remove the
                // app completely. Otherwise, revoke their system privileges.
    

```

编译mk文件

```
$(shell mkdir -p $(PRODUCT_OUT)/data/priv-app)
PRODUCT_COPY_FILES += \
    vendor/common/prethird/Aiqiyi.apk:$(PRODUCT_OUT)/data/priv-app/Aiqiyi.apk
```

经过编译报错原因分析

```
01-01 00:03:46.594   686   686 I PackageManager: /data/priv-app/Aiqiyi changed; collecting certs
01-01 00:03:46.594   686   686 W PackageManager: Failed to scan /data/priv-app/Aiqiyi: Failed collecting certificates for /data/priv-app/Aiqiyi/Aiqiyi.apk
01-01 00:03:46.594   686   686 W PackageManager: Deleting invalid package at /data/priv-app/Aiqiyi
01-01 00:03:46.595   744   753 E installd: Invalid path /data/priv-app/Aiqiyi: No such process
```

不知道为什么这里走了签名验证流程，PMS源码如下：

```
private void scanDirLI(File scanDir, int parseFlags, int scanFlags, long currentTime,
            PackageParser2 packageParser, ExecutorService executorService) {
        final File[] files = scanDir.listFiles();
        if (ArrayUtils.isEmpty(files)) {
            Log.d(TAG, "No files in app dir " + scanDir);
            return;
        }

        if (DEBUG_PACKAGE_SCANNING) {
            Log.d(TAG, "Scanning app dir " + scanDir + " scanFlags=" + scanFlags
                    + " flags=0x" + Integer.toHexString(parseFlags));
        }

        ParallelPackageParser parallelPackageParser =
                new ParallelPackageParser(packageParser, executorService);

        // Submit files for parsing in parallel
        int fileCount = 0;
        for (File file : files) {
            final boolean isPackage = (isApkFile(file) || file.isDirectory())
                    && !PackageInstallerService.isStageName(file.getName());
            if (!isPackage) {
                // Ignore entries which are not packages
                continue;
            }

            if (mPackagesToBeDisabled.values() != null &&
                    mPackagesToBeDisabled.values().contains(file.toString())) {
                // Ignore entries contained in {@link #mPackagesToBeDisabled}
                Slog.d(TAG, "ignoring package: " + file);
                continue;
            }

            parallelPackageParser.submit(file, parseFlags);
            fileCount++;
        }

        // Process results one by one
        for (; fileCount > 0; fileCount--) {
            ParallelPackageParser.ParseResult parseResult = parallelPackageParser.take();
            Throwable throwable = parseResult.throwable;
            int errorCode = PackageManager.INSTALL_SUCCEEDED;
            String errorMsg = null;

            if (throwable == null) {
                // TODO(toddke): move lower in the scan chain
                // Static shared libraries have synthetic package names
                if (parseResult.parsedPackage.isStaticSharedLibrary()) {
                    renameStaticSharedLibraryPackage(parseResult.parsedPackage);
                }
                try {
                    addForInitLI(parseResult.parsedPackage, parseFlags, scanFlags,
                            currentTime, null);
                } catch (PackageManagerException e) {
                    errorCode = e.error;               //  报错log在这里打印，证明addForInitLI函数没走通
                    errorMsg = "Failed to scan " + parseResult.scanFile + ": " + e.getMessage();
                    Slog.w(TAG, errorMsg);
                }
            } else if (throwable instanceof PackageParserException) {
                PackageParserException e = (PackageParserException)
                        throwable;
                errorCode = e.error;
                errorMsg = "Failed to parse " + parseResult.scanFile + ": " + e.getMessage();
                Slog.w(TAG, errorMsg);
            } else {
                throw new IllegalStateException("Unexpected exception occurred while parsing "
                        + parseResult.scanFile, throwable);
            }
```

addForInitLI函数没走通，那我们就看看这个函数，这个函数是安卓11之后加的

```
private AndroidPackage addForInitLI(ParsedPackage parsedPackage,
            @ParseFlags int parseFlags, @ScanFlags int scanFlags, long currentTime,
            @Nullable UserHandle user)
                    throws PackageManagerException {
        

            

        // Verify certificates against what was last scanned. Force re-collecting certificate in two
        // special cases:
        // 1) when scanning system, force re-collect only if system is upgrading.
        // 2) when scannning /data, force re-collect only if the app is privileged (updated from
        // preinstall, or treated as privileged, e.g. due to shared user ID).
        final boolean forceCollect = scanSystemPartition ? mIsUpgrade
                : PackageManagerServiceUtils.isApkVerificationForced(pkgSetting);
        if (DEBUG_VERIFY && forceCollect) {
            Slog.d(TAG, "Force collect certificate of " + parsedPackage.getPackageName());
        }

        // Full APK verification can be skipped during certificate collection, only if the file is
        // in verified partition, or can be verified on access (when apk verity is enabled). In both
        // cases, only data in Signing Block is verified instead of the whole file.
        // TODO(b/136132412): skip for Incremental installation
        final boolean skipVerify = scanSystemPartition
                || (forceCollect && canSkipForcedPackageVerification(parsedPackage));
        collectCertificatesLI(pkgSetting, parsedPackage, forceCollect, skipVerify);   // 应该是这里报错了
```

collectCertificatesLI(pkgSetting, parsedPackage, forceCollect, skipVerify); 后面在加log后发现，这里的skipVerify已经是false了，说明也没有走签名验证

后面发现直接adb install apk也会报错，不止install第三方apk，高通平台自带apk也没有install成功

```
adb: failed to install Aiqiyi.apk: Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed collecting certificates for /data/app/vmdl766318034.tmp/base.apk: Failed to collect certificates from /data/app/vmdl766318034.tmp/base.apk: META-INF/CERT.SF indicates /data/app/vmdl766318034.tmp/base.apk is signed using APK Signature Scheme v2, but no such signature was found. Signature stripped?]
```

到这里原因分析应该是编译出来的apk就是会报这种错误，没编译过apk可以install，问题出来编译mk文件上，修改mk文件：

```
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE        := Aiqiyi
LOCAL_MODULE_TAGS   := optional
LOCAL_MODULE_CLASS  := DATA
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES     := $(LOCAL_MODULE).apk
LOCAL_MODULE_PATH   := $(PRODUCT_OUT)/data/app/Aiqiyi
include $(BUILD_PREBUILT)
```

编译后发现还是会报错，一起看下log

```
01-01 00:11:53.749   772   772 W PackageManager: Failed to scan /data/priv-app/Aiqiyi:  /data/priv-app/Aiqiyi/Aiqiyi.apk not found; ignoring
```

再修改PMS源码，把报错位置注释掉，注释掉这里后，就可以成功预制app了

```
if (!pkg.getPath().equals(known.getPathString())) {
                            throw new PackageManagerException(INSTALL_FAILED_PACKAGE_CHANGED,
                                    "Application package " + pkg.getPackageName()
                                    + " found at " + pkg.getPath()
                                    + " but expected at " + known.getPathString()
                                    + "; ignoring.");
                        }
                    //Add for data app install start
                    //} else {
                    //    throw new PackageManagerException(INSTALL_FAILED_INVALID_INSTALL_LOCATION,
                    //            "Application package " + pkg.getPackageName()
                    //            + " not found; ignoring.");
                    //Add for data app install end
```