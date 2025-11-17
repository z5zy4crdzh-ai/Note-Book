## Android 预制SystemUI Launcher应用

预制现有的SystemUI和Launcher应用到system_ext分区中，system_ext分区

其中Settings.apk和SystemUi.apk就存在在该区域。

/system/system_ext/priv-app/Settings/Settins.apk

为此，Settings模块android.bp还特意指定了模块安装分区, 利用标签：system_ext_specific：

```
platform_compat_config {
    name: "settings-platform-compat-config",
    src: ":Settings-core",
    system_ext_specific: true,
}

android_app {
    name: "Settings",
    platform_apis: true,
    certificate: "platform",
    system_ext_specific: true,
    privileged: true,
    required: [
        "privapp_whitelist_com.android.settings",
        "settings-platform-compat-config",
    ],
    static_libs: ["Settings-core"],
    resource_dirs: [],
    optimize: {
        proguard_flags_files: ["proguard.flags"],
    },
}
```

说其是分区吧，AOSP代码编译出来的结果似乎不像product分区和odm分区那样有有个product.img和odm.img, 并没看到system_ext.img.

从官网AOSP官网动态分区相关表述来看，这就是个分区。

![AOSP官网动态分区相关表述system_ext](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/287061974eaf407e90615d3899e37b53~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=1518&h=715&s=155814&e=png&b=ffffff)

这就是Android R才引入的动态分区定制概念，和odm分区类似用法,为了应对单个项目满足不同多样的需求而进一步完善的动态定制型框架。

system_ext放置的内容树

```
system/system_ext/
├── apex
│   ├── com.android.adbd
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.art.debug
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   ├── javalib
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.cellbroadcast
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   └── priv-app
│   ├── com.android.conscrypt
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   ├── javalib
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.extservices
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   └── priv-app
│   ├── com.android.i18n
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   └── etc
│   ├── com.android.ipsec
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   └── javalib
│   ├── com.android.media
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   ├── javalib
│   │   └── lib64
│   ├── com.android.mediaprovider
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   ├── javalib
│   │   └── priv-app
│   ├── com.android.media.swcodec
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   └── lib64
│   ├── com.android.neuralnetworks
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.os.statsd
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   ├── javalib
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.permission
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── javalib
│   │   └── priv-app
│   ├── com.android.resolv
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   └── lib64
│   ├── com.android.runtime
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.sdkext
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── bin
│   │   ├── etc
│   │   └── javalib
│   ├── com.android.tethering
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── javalib
│   │   └── priv-app
│   ├── com.android.tzdata
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   └── etc
│   ├── com.android.vndk.current
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.vndk.v28
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.vndk.v28.apex
│   ├── com.android.vndk.v29
│   │   ├── apex_manifest.pb
│   │   ├── apex_pubkey
│   │   ├── etc
│   │   ├── lib
│   │   └── lib64
│   ├── com.android.vndk.v29.apex
│   └── com.android.wifi
│       ├── apex_manifest.pb
│       ├── apex_pubkey
│       ├── app
│       ├── etc
│       ├── javalib
│       └── priv-app
├── bin
│   └── stagefright
├── build.prop
├── etc
│   ├── compatconfig
│   │   └── settings-platform-compat-config.xml
│   ├── group
│   ├── init
│   │   ├── config
│   │   └── init.gsi.rc
│   ├── NOTICE.xml.gz
│   ├── passwd
│   ├── permissions
│   │   ├── com.android.carrierconfig.xml
│   │   ├── com.android.emergency.xml
│   │   ├── com.android.launcher3.xml
│   │   ├── com.android.provision.xml
│   │   ├── com.android.sdksetup.xml
│   │   ├── com.android.settings.xml
│   │   ├── com.android.storagemanager.xml
│   │   └── com.android.systemui.xml
│   ├── selinux
│   │   └── system_ext_sepolicy_and_mapping.sha256
│   └── vintf
│       └── manifest.xml
├── lib64
│   └── libemulator_multidisplay_jni.so
└── priv-app
    ├── CarrierConfig
    │   └── CarrierConfig.apk
    ├── EmergencyInfo
    │   └── EmergencyInfo.apk
    ├── Launcher3QuickStep
    │   └── Launcher3QuickStep.apk
    ├── MultiDisplayProvider
    │   ├── lib
    │   └── MultiDisplayProvider.apk
    ├── Provision
    │   └── Provision.apk
    ├── SdkSetup
    │   └── SdkSetup.apk
    ├── Settings
    │   └── Settings.apk
    ├── StorageManager
    │   └── StorageManager.apk
    ├── SystemUI
    │   └── SystemUI.apk
    └── WallpaperCropper
        └── WallpaperCropper.apk
```

在vendor下创建预制目录和mk文件

Android.mk

这里用了LOCAL_OVERRIDES_PACKAGES来覆盖编译，不编原生的Launcher

```
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE             := oem-launcher
LOCAL_MODULE_STEM        := Launcher3QuickStep
LOCAL_OVERRIDES_PACKAGES := Home Launcher2 Launcher3 Launcher3QuickStep Launcher3Go
LOCAL_MODULE_TAGS        := optional
LOCAL_MODULE_CLASS       := DATA
LOCAL_REQUIRED_MODULES := privapp_whitelist_com.android.car.carlauncher
LOCAL_SRC_FILES          := Launcher3QuickStep.apk
LOCAL_MODULE_SUFFIX      := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_MODULE_PATH        := $(PRODUCT_OUT)/system_ext/priv-app/Launcher3QuickStep/
include $(BUILD_PREBUILT)
```

```
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE             := oem-SystemUI
LOCAL_MODULE_STEM        := SystemUI
LOCAL_OVERRIDES_PACKAGES := SystemUI
LOCAL_MODULE_TAGS        := optional
LOCAL_MODULE_CLASS       := DATA
LOCAL_SRC_FILES          := SystemUI.apk
LOCAL_MODULE_SUFFIX      := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_MODULE_PATH        := $(PRODUCT_OUT)/system_ext/priv-app/SystemUI/
include $(BUILD_PREBUILT)
```

Product.mk

这里因为还要拷贝一个文件夹到system/etc/下，加了一个拷贝文件

如果出现拷贝的是apk文件，则有可能出现如下错误 Prebuilt apk found in PRODUCT_COPY_FILES: device/amlogic/f16ref/hello.apk:/system/app/hello.apk, use BUILD_PREBUILT instead!. Stop. 原因是build/core/Makefile中对copy file作了检测，如果是apk文件，会出错 此时注释掉build/core/Makefile里面的define check-product-copy-file函数内容即可，所以还是选择了覆盖编译的方法预制apk

```
PRODUCT_COPY_FILES += \
    vendor/xxxx/common/xxxx/xxx.rc:system/etc/init/xxx.rc
$(shell mkdir -p system/etc/xxxx)
PRODUCT_COPY_FILES += $(call find-copy-subdir-files,*,vendor/xxxx/common/xxxx3/xxxxx/,system/etc/xxxx/)
PRODUCT_PACKAGES += oem-SystemUI
PRODUCT_PACKAGES += oem-launcher
```

编译完成后，发现文件apk成功覆盖编译到out目录下

烧录设备后发现设备起不来，log分析

特权应用申请的特殊权限，需要在 xml 中声明权限。

开机会检查priv-app的权限是否和/etc/permissions/privapp-permissions-platform.xml（有可能在别的文件夹下，例如vendor/etc/permissions，也有可能叫其他名字，因为只要xml的节点是对的就行，pm中的SystemConfig会对这类文件夹的所有xml进行扫描）所声明的权限是否一样，不一样则无法开机，就会一直loop上面的crash。报错 log 中典型特征 Signature|privileged permissions not in privapp-permissions whitelist

```
--------- beginning of crash
10-16 14:18:39.065  3151  3151 E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: main
10-16 14:18:39.065  3151  3151 E AndroidRuntime: java.lang.IllegalStateException: Signature|privileged permissions not in privapp-permissions whitelist: {com.demo.permission: android.permission.DELETE_PACKAGES, com.demo.permission: android.permission.READ_NETWORK_USAGE_HISTORY, com.demo.permission: android.permission.READ_LOGS, com.demo.permission: android.permission.PACKAGE_USAGE_STATS, com.demo.permission: android.permission.CLEAR_APP_CACHE, com.demo.permission: android.permission.REAL_GET_TASKS, com.demo.permission: android.permission.READ_PRIVILEGED_PHONE_STATE}
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.pm.permission.PermissionManagerService.systemReady(PermissionManagerService.java:3118)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.pm.permission.PermissionManagerService.access$100(PermissionManagerService.java:122)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.pm.permission.PermissionManagerService$PermissionManagerServiceInternalImpl.systemReady(PermissionManagerService.java:3179)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.pm.PackageManagerService.systemReady(PackageManagerService.java:21886)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.SystemServer.startOtherServices(SystemServer.java:1995)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.SystemServer.run(SystemServer.java:513)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.server.SystemServer.main(SystemServer.java:350)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at java.lang.reflect.Method.invoke(Native Method)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:492)
10-16 14:18:39.065  3151  3151 E AndroidRuntime:        at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:916)
```

先从log中的PermissionManagerService#systemReady方法入手

base/services/core/java/com/android/server/pm/permission/PermissionManagerService.java

只要mPrivappPermissionsViolations这个数组中有数据，我们就永远无法开机，看看这个数组是怎么填充的。

```
private void systemReady() {
        // Now that we've scanned all packages, and granted any default
        // permissions, ensure permissions are updated. Beware of dragons if you
        // try optimizing this.
        updateAllPermissions(StorageManager.UUID_PRIVATE_INTERNAL, false);

        final PermissionPolicyInternal permissionPolicyInternal = LocalServices.getService(
                PermissionPolicyInternal.class);
        permissionPolicyInternal.setOnInitializedCallback(userId ->
                // The SDK updated case is already handled when we run during the ctor.
                updateAllPermissions(StorageManager.UUID_PRIVATE_INTERNAL, false)
        );

        mSystemReady = true;

        synchronized (mLock) {
            if (mPrivappPermissionsViolations != null) {
                throw new IllegalStateException("Signature|privileged permissions not in "
                        + "privapp-permissions allowlist: " + mPrivappPermissionsViolations);
            }
        }

        mPermissionControllerManager = mContext.getSystemService(PermissionControllerManager.class);
        mPermissionPolicyInternal = LocalServices.getService(PermissionPolicyInternal.class);
    }
```

```
// Only enforce the allowlist on boot
        if (!mSystemReady) {
            final ApexManager apexManager = ApexManager.getInstance();
            final String containingApexPackageName =
                    apexManager.getActiveApexPackageNameContainingPackage(packageName);
            final boolean isInUpdatedApex = containingApexPackageName != null
                    && !apexManager.isFactory(apexManager.getPackageInfo(containingApexPackageName,
                    MATCH_ACTIVE_PACKAGE));
            // Apps that are in updated apexs' do not need to be allowlisted
            if (!isInUpdatedApex) {
                Slog.w(TAG, "Privileged permission " + permissionName + " for package "
                        + packageName + " (" + pkg.getPath()
                        + ") not in privapp-permissions allowlist");
                if (RoSystemProperties.CONTROL_PRIVAPP_PERMISSIONS_ENFORCE) {
                    synchronized (mLock) {
                        if (mPrivappPermissionsViolations == null) {
                            mPrivappPermissionsViolations = new ArraySet<>();
                        }
                        mPrivappPermissionsViolations.add(packageName + " (" + pkg.getPath() + "): "
                                + permissionName);
                    }
                }
            }
        }
        return !RoSystemProperties.CONTROL_PRIVAPP_PERMISSIONS_ENFORCE;
    }
```

发现缺少权限后在\frameworks\base\data\etc\privapp-permissions-platform加入缺少权限

```
<permissions>

+    <privapp-permissions package="com.demo.permission">
+        <permission name="android.permission.DELETE_PACKAGES"/>
+        <permission name="android.permission.READ_NETWORK_USAGE_HISTORY"/>
+        <permission name="android.permission.READ_LOGS"/>
+        <permission name="android.permission.PACKAGE_USAGE_STATS"/>
+        <permission name="android.permission.CLEAR_APP_CACHE"/>
+        <permission name="android.permission.REAL_GET_TASKS"/>
+        <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE"/>
+    </privapp-permissions>

</permissions>
```

加完权限编译烧录后还是发现开不了机，报错还是报缺少权限，在机子下的xml文件也证明已经有已经加的权限，为什么没有扫描到呢

![image-20240408174931815]()

![image.png](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3493e813176f4825b208adcd1e6e7803~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=503&h=62&s=4182&e=png&b=0c0c0c)

权限文件加在了system目录底下，而apk则是预制在system_ext目录底下，我感觉是没有影响的，但是它就是没有扫描到，那就在system_ext目录底下看看

![image-20240408175133002]()

![image.png](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/31c92e31112f4b7fba45ccd02565fd88~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=763&h=235&s=36070&e=png&b=0c0c0c)

在这里看到有launcher原生的权限xml，他写在了这里，那我们就学他一样拷贝xml文件到system_ext目录底下

这里我看了它的launcher是怎么把这个xml文件拷贝到这里

```
LOCAL_PACKAGE_NAME := Launcher3QuickStep
LOCAL_PRIVILEGED_MODULE := true
LOCAL_SYSTEM_EXT_MODULE := true
LOCAL_OVERRIDES_PACKAGES := Home Launcher2 Launcher3
LOCAL_REQUIRED_MODULES := privapp_whitelist_com.android.launcher3

LOCAL_RESOURCE_DIR := $(LOCAL_PATH)/quickstep/res

LOCAL_FULL_LIBS_MANIFEST_FILES := \
    $(LOCAL_PATH)/quickstep/AndroidManifest-launcher.xml \
    $(LOCAL_PATH)/AndroidManifest-common.xml

LOCAL_MANIFEST_FILE := quickstep/AndroidManifest.xml
LOCAL_JACK_COVERAGE_INCLUDE_FILTER := com.android.launcher3.*

```

LOCAL_REQUIRED_MODULES := privapp_whitelist_com.android.launcher3这个在\frameworks\base\data\etc\Android.bp，然后把xml文件放在etc这个目录下，

单编确认是可以拷贝到out目录底下

```
prebuilt_etc {
    name: "privapp_whitelist_com.android.launcher3",
    system_ext_specific: true,
    sub_dir: "permissions",
    src: "com.android.launcher3.xml",
    filename_from_src: true,
}
prebuilt_etc {
    name: "privapp_whitelist_com.android.systemui",
    system_ext_specific: true,
    sub_dir: "permissions",
    src: "com.android.systemui.xml",
    filename_from_src: true,
}
```

在这里加过权限之后就可以正常启动机器了，但是还是不知道为什么放在system/etc/下为什么没有扫描到权限