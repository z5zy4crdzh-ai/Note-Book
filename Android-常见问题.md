

## Android-常见问题



### Android跨进程通信方式



**Android跨进程通信HandlerMessenger**：通过消息队列实现单向通信，适合轻量级或不需要并发的场景（如发送指令或事件）

**Android跨进程通信AIDL服务**：通过定义接口实现多进程通信，支持并发请求和复杂数据交互，常用于需要高性能的场景（如后台服务通信）。

**Android跨进程通信Broadcast广播**：通过全局广播（有序或无序）传递消息，其他应用可注册监听，适用于通知类通信（需注意安全性）。

**Android跨进程通信Content Provider**：提供结构化数据访问接口（如数据库、文件），供其他应用安全读写数据，底层通过Binder实现。

**Android跨进程通信文件共享/SharedPreferences**：通过读写文件或键值对共享数据，但需处理并发和同步问题，适合对实时性要求不高的场景。

**Android跨进程Socket**：通过TCP/IP或本地Socket传输数据，适用网络通信或特定进程间传输（如Client-Server模型）。

**Android跨进程共享内存**：基于匿名共享内存传输大数据（如图片、音频），避免Binder事务缓冲区限制，常用于高效数据共享。









### Android-从Java层到驱动层结构

在 Android 中，从 Java 应用到设备驱动的调用链主要包括以下步骤：

1. **应用层 & Java Framework**：应用通过 Android SDK 提供的 Manager/Service API 发起调用（如 `CameraManager`、`SensorManager` 等）。
2. **AIDL 接口**：若跨进程或跨分区，需要先通过 AIDL 定义接口，并由编译工具生成 Java Stub/Proxy、C++ Stub/Proxy 代码。
3. **Binder IPC**：Java 代码调用 Stub→Binder 驱动→目标进程的 Proxy，进行数据序列化与传输。
4. **System Service & JNI**：在 System Server（如 media.server）中，Java Stub 调用本地 JNI 接口，进入 C/C++ 代码空间。
5. **HAL（硬件抽象层）**：JNI 调用封装好的 HAL 接口（HIDL 或 AIDL HAL），隔离具体硬件，实现跨供应商模块化。
6. **内核驱动**：HAL 库通过标准文件操作（`open`/`read`/`write`）或 `ioctl` 与内核中的驱动模块通信，最终控制硬件。

7. Java Framework 与 AIDL



1.1 应用层调用 Framework API

- 应用调用如 `CameraManager.openCamera()`、`SensorManager.registerListener()` 等高层 API，这些 API 封装在 `android.hardware.camera2` 或 `android.hardware` 包下，用于与系统服务通信。

1.2 AIDL 接口定义与生成

- 当服务需要跨进程（如不同应用或 framework→vendor）时，使用 AIDL 定义接口；AIDL 工具会生成 Java Stub/Proxy，用于 Binder IPC（method ID、参数打包到 `Parcel`）
- Android 11 以后，HAL 也可直接使用 AIDL 定义并生成稳定的 HAL 接口，统一多处 IPC 机制，提高版本管理和性能



2. Binder IPC 机制

2.1 Java Proxy → C++ Proxy → Kernel Driver → C++ Native → Java Native

- 当 Java Stub 调用远端服务方法时，数据先在 Java 侧序列化到 `Parcel`，转为本地 C++ `BpBinder` 对象，再通过 ioctl 进入 Binder 驱动，驱动将数据传输至目标进程的 Binder 驱动上下文，最后在目标进程由 `BBinder` 解析并调用本地接口
- Binder 驱动自 Android 8 引入多上下文（context）隔离机制，并通过 scatter-gather 优化减少内存拷贝次数，提升 IPC 性能

2.2 Binder 驱动细节

- Binder 驱动作为内核模块，使用 `ioctl(fd, BINDER_WRITE_READ, &cmd)` 等接口实现数据收发与进程间消息队列管理。
- 驱动内部维护句柄与进程映射，保证消息安全隔离，并对大数据采用零拷贝优化。



3. System Service 与 JNI

3.1 System Server 中的 Java 服务

- 系统服务（如 `CameraService`、`SensorService`）运行在 System Server 进程中，通过 Java Stub 接收 IPC 调用，并调用对应的本地方法。

3.2 JNI 层桥接

- Java 服务通过 `native` 修饰的方法进入 JNI 接口，在 `frameworks/base/` 中的 JNI 注册函数中找到对应 C/C++ 实现，如 `CameraService.cpp` 中的 `native_startPreview` 等
- JNI 层负责参数转换（如 Java String ↔ `const char*`），并调用底层 HAL 接口。



4. 硬件抽象层（HAL）

4.1 HIDL 与 AIDL HAL

- 旧版 Android（Oreo 及以前）使用 HIDL 定义 HAL 接口，生成 C++ Stub/Proxy，运行时加载 `/vendor/lib/hw/*.so` 实现。
- Android 11 起，支持使用 AIDL 定义 HAL （`stable AIDL`），统一与 framework 层的 IPC 机制，简化版本管理；HAL 接口在 `vintf/` 定义并注册到 VINTF 清单中

4.2 HAL 运行模式

- **Binderized HAL**：HAL 实现以独立进程运行，通过 Binder IPC 与 framework 通信，为安全隔离提供保障。

- **Passthrough HAL**：HAL 实现作为共享库加载到 framework 进程中，省去 IPC 开销，适用于延迟敏感场景。

  

5. 内核驱动层交互

5.1 文件操作与 ioctl

- HAL 库打开设备节点（如 `/dev/video0`、`/dev/snd/pcmC0D0p`），并通过 `ioctl(fd, CMD, &arg)` 发起控制命令，例如相机 HAL 调用 V4L2 接口或摄像头驱动实现的自定义 ioctl
- 对于音视频、图形等子系统，也可能使用 DMA-BUF、ION 等内核机制，通过 mmap、共享内存对象与驱动交换大块数据。

5.2 驱动实现

- 最底层驱动为 Linux 内核模块，负责硬件寄存器配置、中断处理、DMA 控制等。HAL 通过统一接口与驱动通信，屏蔽了不同 SoC 或厂商间的差异。

------

以上即 Android 从 Java 应用层走到设备驱动的完整流程，包括 AIDL 接口生成、Binder IPC、JNI 本地调用、HAL 抽象以及最终驱动交互的关键细节。每一环节都有成熟的框架和代码生成工具保证效率、灵活性与安全隔离。



### Android-dex odex oat vdex art区别

1.dex

java程序编译成class后，dx工具将所有class文件合成一个dex文件，dex文件是jar文件大小的50%左右.

2.odex（Android5.0之前）全称：Optimized DEX;即优化过的DEX.

Android5.0之前APP在安装时会进行验证和优化，为了校验代码合法性及优化代码执行速度，验证和优化后，会产生ODEX文件，运行Apk的时候，直接加载ODEX，避免重复验证和优化，加快了Apk的响应时间. 注意：优化会根据不同设备上Dalvik虚拟机版本、Framework库的不同等因素而不同，在一台设备上被优化过的ODEX文件，拷贝到另一台设备上不一定能够运行。

3.oat（Android5.0之后）

oat是ART虚拟机运行的文件,是ELF格式二进制文件,包含DEX和编译的本地机器指令,oat文件包含DEX文件，因此比ODEX文件占用空间更大。 Android5.0以后在编译的时候(此处指系统预制app，如果通过adb install或者商店安装，在安装时dex2oat把dex编译为odex的ELF格式文件)dex2oat默认会把classes.dex翻译成本地机器指令，生成ELF格式的OAT文件，ART加载OAT文件后不需要经过处理就可以直接运行，它在编译时就从字节码装换成机器码了，因此运行速度更快。不过android5.0之后oat文件还是以.odex后缀结尾,但是已经不是android5.0之前的文件格式，而是ELF格式封装的本地机器码. 可以认为oat在dex上加了一层壳，可以从oat里提取出dex.

4.vdex

Android8.0以后加入的,包含APK的未压缩DEX代码，另外还有一些旨在加快验证速度的元数据。

5.art (optional)

包含APK中列出的某些字符串和类的ART内部表示，用于加快应用启动速度。

注意：Android5.0以后在／data/dalvik-cache目录下的.dex文件已经不是android5.0之前的dex文件，它是ELF文件,可以使用file命令查看如下：

```ruby
# file system@app@Camera2@Camera2.apk@classes.dex
```









### Android-系统签名生成

生成keystore文件主要是给外部apk开发签名使用的；
以常用的platform签名为例：

\android14\device\semidrive\common\security

```shell
//如果之前没有生成platform.pem文件，现在可以执行以下命令生成
openssl pkcs8 -inform DER -nocrypt -in platform.pk8 -out platform.pem

//生成platform.p12文件，设置对应的密码和alias名（app签名使用到）
openssl pkcs12 -export -in platform.x509.pem -out platform.p12 -inkey platform.pem -password pass:密码 -name 名称

//生成platform.jks（app使用的签名文件），启动
keytool -importkeystore -deststorepass 密码 -destkeystore ./platform.keystore -srckeystore ./platform.p12 -srcstoretype PKCS12 -srcstorepass 密码

//剩下的就是将platform.jks拷贝到app工程目录下设置alias名和密码即可
```



在app中gradle中添加即可

```java
buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            signingConfig signingConfigs.release
        }

        debug {
            signingConfig signingConfigs.debug
        }
    }



signingConfigs {
        release {
            File strFile = new File("./keystore/platform.keystore")
            storeFile file(strFile)
            keyAlias 'platform'
            keyPassword 'android'
            storePassword 'android'
        }
        debug {
            File strFile = new File("./keystore/platform.keystore")
            storeFile file(strFile)
            keyAlias 'platform'
            keyPassword 'android'
            storePassword 'android'
        }
    }
```



Android-log打印调用栈

```java
Log.i("----", Log.getStackTraceString(new Throwable()));
```



### Android-内置apk使用uses-library编译报错

1）安装或编译出现的错误

Google关于这方面在Android S的改动有文档输出，可以参考如下：Dexpreopt 和 uses-library 检查。

此项报错主要是构建系统在Android.bp或Android.mk文件中的信息与Manifest清单之间进行构建时一致性检查，要求声明请求使用的libraries跟AndroidManifest.xml中声明的一致，否则将报错。

接下来查看编译报错：

```shell
error: mismatch in the <uses-library> tags between the build system and the manifest:
    - required libraries in build system: []
                     vs. in the manifest: [org.apache.http.legacy]
    - optional libraries in build system: []
                     vs. in the manifest: [com.x.y.z]
    - tags in the manifest (.../X_intermediates/manifest/AndroidManifest.xml):
        <uses-library android:name="com.x.y.z"/>
        <uses-library android:name="org.apache.http.legacy"/>

note: the following options are available:
    - to temporarily disable the check on command line, rebuild with RELAX_USES_LIBRARY_CHECK=true (this will set compiler filter "verify" and disable AOT-compilation in dexpreopt)
    - to temporarily disable the check for the whole product, set PRODUCT_BROKEN_VERIFY_USES_LIBRARIES := true in the product makefiles
    - to fix the check, make build system properties coherent with the manifest
    - see build/make/Changes.md for details
```


根据提示可以做如下三种尝试修改：

（A）产品范围的临时修复：在MK当中配置PRODUCT_BROKEN_VERIFY_USES_LIBRARIES := true；

此项仍然会执行构建时一致性检查，但检查失败并不意味着构建失败。相反，检查失败会使构建系统降级 dex2oat 编译器过滤器以在 dexpreopt 中进行verify ，从而完全禁用此模块的 AOT 编译。

（B）快速进行全局命令行修复：请使用环境变量RELAX_USES_LIBRARY_CHECK=true；

它与PRODUCT_BROKEN_VERIFY_USES_LIBRARIES具有相同的效果，但旨在用于命令行。环境变量覆盖产品变量。

（C）根本原因修复：请让构建系统了解清单中的标记；

检查AndroidManifest.xml或APK内的清单，可以使用aapt dump badging $APK | grep uses-library来检查，然后在MK文件中进行如下配置：

```shell
//LOCAL_USES_LIBRARIES := <library-module-name>
//LOCAL_OPTIONAL_USES_LIBRARIES := <library-module-name>

LOCAL_OPTIONAL_USES_LIBRARIES := org.apache.http.legacy    androidx.window.extensions     androidx.window.sidecar
```

（2）一劳永逸之法

```shell
//Android.bp

enforce_uses_libs: false,
dex_preopt: {
    enabled: false,
},

//Android.mk

LOCAL_ENFORCE_USES_LIBRARIES := false
LOCAL_DEX_PREOPT := false
```







### Android-手动添加Binder接口编译报错

```shell
错误：error: static_assert failed due to requirement 'internal::allowedManualInterface("android.test.Icallback")' "b/64223827: Manually written binder interfaces are considered error prone and frequently have bugs. The preferred way to add interfaces is to define an .aidl file to auto-generate the interface. If an interface must be manually written, add its name to the whitelist."
        IMPLEMENT_META_INTERFACE(callback, "android.test.Icallback");
```

我在开发android系统私有服务 版本28之前都是使用Andorid.mk，编译都没大问题
现在Android11后，变成Andorid.bp，编译规则特别严格
之前的CS结构，进程间接口都是我自己手写的，最新编译
IMPLEMENT_META_INTERFACE 直接static_assert报错，看提示需要加入一个白名单；

```shell
#define IMPLEMENT_META_INTERFACE(INTERFACE, NAME)                       \
    static_assert(internal::allowedManualInterface(NAME),               \
                  "b/64223827: Manually written binder interfaces are " \
                  "considered error prone and frequently have bugs. "   \
                  "The preferred way to add interfaces is to define "   \
                  "an .aidl file to auto-generate the interface. If "   \
                  "an interface must be manually written, add its "     \
                  "name to the whitelist.");                            \
    DO_NOT_DIRECTLY_USE_ME_IMPLEMENT_META_INTERFACE(INTERFACE, NAME)    \
```

1、我最后在IInterface.h中找打白名单，加入我的就行frameworks\native\libs\binder\include\binder\IInterface.h

kManualInterfaces是白名单

2、暂时的粗暴规避

```shell
#ifndef DO_NOT_CHECK_MANUAL_BINDER_INTERFACES
#define DO_NOT_CHECK_MANUAL_BINDER_INTERFACES 1
#endif
```









### Android-bp文件和mk文件关系

> 1. **ninja**是一个编译框架，会根据相应的ninja格式的配置文件进行编译，但是ninja文件一般不会手动修改，而是通过将 Android.bp文件转换成ninja格文件来编译
> 2. **Android.bp**是纯粹的配置，没有分支、循环等流程控制，不能做算数逻辑运算。如果需要控制逻辑，那么只能通过Go语言编写
> 3. **Soong**类似于之前的Makefile编译系统的核心，负责提供Android.bp语义解析，并将之转换成Ninja文件。Soong还会编译生成一个androidmk命令，用于将Android.mk文件转换为Android.bp文件
> 4. **Blueprint**是生成、解析Android.bp的工具，是Soong的一部分。Soong负责Android编译而设计的工具，而Blueprint只是解析文件格式，Soong解析内容的具体含义。Blueprint和Soong都是由Golang写的项目，从Android 7.0，prebuilts/go/目录下新增Golang所需的运行环境，在编译时使用
> 5. **kati**是专为Android开发的一个基于Golang和C++的工具，主要功能是把Android中的Android.mk文件转换成Ninja文件。代码路径是build/kati/，编译后的产物是ckati

Android.mk -> Android.bp

> Android.mk 转换为 Android.bp,Google提供了官方工具androidmk，只针对简单的mk文件转换，涉及分支，循环等控制转换并不准确
> androidmk使用 ：androidmk android.mk > android.bp

Android.bp使用

```bash
java_library {
    name: "services",

    dex_preopt: {
        app_image: true,
        profile: "art-profile",
    },

    srcs: [
        "java/**/*.java",
    ],

    static_libs: [
        "services.core",
        "services.accessibility",
        "services.appwidget",
        "services.autofill",
        "services.backup",
        "services.companion",
        "services.coverage",
        "services.devicepolicy",
        "services.midi",
        "services.net",
        "services.print",
        "services.restrictions",
        "services.usage",
        "services.usb",
        "services.voiceinteraction",
        "android.hidl.base-V1.0-java",
    ],

    libs: [
        "android.hidl.manager-V1.0-java",
        "miuisdk",
        "miuisystemsdk"
    ],

}

cc_library_shared {
    name: "libandroid_servers",
    defaults: ["libservices.core-libs"],
    whole_static_libs: ["libservices.core"],
}
```

Android.bp与Android.mk的对应关系

> Android.mk 和 Android.bp的对应关系参照
> androidmk源码 ：build/soong/androidmk/cmd/androidmk/android.go

```shell
func init() {
 	addStandardProperties(bpparser.StringType,
		map[string]string{
			"LOCAL_MODULE":                  "name",
			"LOCAL_CXX_STL":                 "stl",
			"LOCAL_MULTILIB":                "compile_multilib",
			"LOCAL_ARM_MODE_HACK":           "instruction_set",
			"LOCAL_SDK_VERSION":             "sdk_version",
			"LOCAL_MIN_SDK_VERSION":         "min_sdk_version",
			"LOCAL_NDK_STL_VARIANT":         "stl",
 			"LOCAL_JAR_MANIFEST":            "manifest",
 			"LOCAL_CERTIFICATE":             "certificate",
 			"LOCAL_PACKAGE_NAME":            "name",
 			"LOCAL_MODULE_RELATIVE_PATH":    "relative_install_path",
 			"LOCAL_PROTOC_OPTIMIZE_TYPE":    "proto.type",
 			"LOCAL_MODULE_OWNER":            "owner",
 			"LOCAL_RENDERSCRIPT_TARGET_API": "renderscript.target_api",
 			"LOCAL_NOTICE_FILE":             "notice",
 			"LOCAL_JAVA_LANGUAGE_VERSION":   "java_version",
 			"LOCAL_INSTRUMENTATION_FOR":     "instrumentation_for",
 			"LOCAL_MANIFEST_FILE":           "manifest",
 
 			"LOCAL_DEX_PREOPT_PROFILE_CLASS_LISTING": "dex_preopt.profile",
 			"LOCAL_TEST_CONFIG":                      "test_config",
 		})
 	addStandardProperties(bpparser.ListType,
 		map[string]string{
 			"LOCAL_SRC_FILES":                     "srcs",
 			"LOCAL_SRC_FILES_EXCLUDE":             "exclude_srcs",
 			"LOCAL_HEADER_LIBRARIES":              "header_libs",
 			"LOCAL_SHARED_LIBRARIES":              "shared_libs",
 			"LOCAL_STATIC_LIBRARIES":              "static_libs",
 			"LOCAL_WHOLE_STATIC_LIBRARIES":        "whole_static_libs",
 			"LOCAL_SYSTEM_SHARED_LIBRARIES":       "system_shared_libs",
 			"LOCAL_ASFLAGS":                       "asflags",
 			"LOCAL_CLANG_ASFLAGS":                 "clang_asflags",
 			"LOCAL_CONLYFLAGS":                    "conlyflags",
 			"LOCAL_CPPFLAGS":                      "cppflags",
 			"LOCAL_REQUIRED_MODULES":              "required",
 			"LOCAL_OVERRIDES_MODULES":             "overrides",
 			"LOCAL_LDLIBS":                        "host_ldlibs",
 			"LOCAL_CLANG_CFLAGS":                  "clang_cflags",
 			"LOCAL_YACCFLAGS":                     "yaccflags",
 			"LOCAL_SANITIZE_RECOVER":              "sanitize.recover",
 			"LOCAL_LOGTAGS_FILES":                 "logtags",
 			"LOCAL_EXPORT_HEADER_LIBRARY_HEADERS": "export_header_lib_headers",
 			"LOCAL_EXPORT_SHARED_LIBRARY_HEADERS": "export_shared_lib_headers",
 			"LOCAL_EXPORT_STATIC_LIBRARY_HEADERS": "export_static_lib_headers",
 			"LOCAL_INIT_RC":                       "init_rc",
 			"LOCAL_VINTF_FRAGMENTS":               "vintf_fragments",
 			"LOCAL_TIDY_FLAGS":                    "tidy_flags",
 			// TODO: This is comma-separated, not space-separated
 			"LOCAL_TIDY_CHECKS":           "tidy_checks",
 			"LOCAL_RENDERSCRIPT_INCLUDES": "renderscript.include_dirs",
 			"LOCAL_RENDERSCRIPT_FLAGS":    "renderscript.flags",
 
 			"LOCAL_JAVA_RESOURCE_DIRS":    "java_resource_dirs",
 			"LOCAL_JAVACFLAGS":            "javacflags",
 			"LOCAL_ERROR_PRONE_FLAGS":     "errorprone.javacflags",
 			"LOCAL_DX_FLAGS":              "dxflags",
 			"LOCAL_JAVA_LIBRARIES":        "libs",
 			"LOCAL_STATIC_JAVA_LIBRARIES": "static_libs",
 			"LOCAL_JNI_SHARED_LIBRARIES":  "jni_libs",
 			"LOCAL_AAPT_FLAGS":            "aaptflags",
 			"LOCAL_PACKAGE_SPLITS":        "package_splits",
 			"LOCAL_COMPATIBILITY_SUITE":   "test_suites",
 			"LOCAL_OVERRIDES_PACKAGES":    "overrides",
 
 			"LOCAL_ANNOTATION_PROCESSORS": "plugins",
 
 			"LOCAL_PROGUARD_FLAGS":      "optimize.proguard_flags",
 			"LOCAL_PROGUARD_FLAG_FILES": "optimize.proguard_flags_files",
 
 			// These will be rewritten to libs/static_libs by bpfix, after their presence is used to convert
 			// java_library_static to android_library.
 			"LOCAL_SHARED_ANDROID_LIBRARIES": "android_libs",
 			"LOCAL_STATIC_ANDROID_LIBRARIES": "android_static_libs",
 			"LOCAL_ADDITIONAL_CERTIFICATES":  "additional_certificates",
 
 			// Jacoco filters:
 			"LOCAL_JACK_COVERAGE_INCLUDE_FILTER": "jacoco.include_filter",
 			"LOCAL_JACK_COVERAGE_EXCLUDE_FILTER": "jacoco.exclude_filter",
 		})
 
 	addStandardProperties(bpparser.BoolType,
 		map[string]string{
 			// Bool properties
 			"LOCAL_IS_HOST_MODULE":             "host",
 			"LOCAL_CLANG":                      "clang",
 			"LOCAL_FORCE_STATIC_EXECUTABLE":    "static_executable",
 			"LOCAL_NATIVE_COVERAGE":            "native_coverage",
 			"LOCAL_NO_CRT":                     "nocrt",
 			"LOCAL_ALLOW_UNDEFINED_SYMBOLS":    "allow_undefined_symbols",
 			"LOCAL_RTTI_FLAG":                  "rtti",
 			"LOCAL_NO_STANDARD_LIBRARIES":      "no_standard_libs",
 			"LOCAL_PACK_MODULE_RELOCATIONS":    "pack_relocations",
 			"LOCAL_TIDY":                       "tidy",
 			"LOCAL_USE_CLANG_LLD":              "use_clang_lld",
 			"LOCAL_PROPRIETARY_MODULE":         "proprietary",
 			"LOCAL_VENDOR_MODULE":              "vendor",
 			"LOCAL_ODM_MODULE":                 "device_specific",
 			"LOCAL_PRODUCT_MODULE":             "product_specific",
 			"LOCAL_PRODUCT_SERVICES_MODULE":    "product_services_specific",
 			"LOCAL_EXPORT_PACKAGE_RESOURCES":   "export_package_resources",
 			"LOCAL_PRIVILEGED_MODULE":          "privileged",
 			"LOCAL_AAPT_INCLUDE_ALL_RESOURCES": "aapt_include_all_resources",
 			"LOCAL_USE_EMBEDDED_NATIVE_LIBS":   "use_embedded_native_libs",
 			"LOCAL_USE_EMBEDDED_DEX":           "use_embedded_dex",
 
 			"LOCAL_DEX_PREOPT":                  "dex_preopt.enabled",
 			"LOCAL_DEX_PREOPT_APP_IMAGE":        "dex_preopt.app_image",
 			"LOCAL_DEX_PREOPT_GENERATE_PROFILE": "dex_preopt.profile_guided",
 
 			"LOCAL_PRIVATE_PLATFORM_APIS": "platform_apis",
 			"LOCAL_JETIFIER_ENABLED":      "jetifier",
 		})
	}
	
	var moduleTypes = map[string]string{
		"BUILD_SHARED_LIBRARY":        "cc_library_shared",
		"BUILD_STATIC_LIBRARY":        "cc_library_static",
		"BUILD_HOST_SHARED_LIBRARY":   "cc_library_host_shared",
		"BUILD_HOST_STATIC_LIBRARY":   "cc_library_host_static",
		"BUILD_HEADER_LIBRARY":        "cc_library_headers",
		"BUILD_EXECUTABLE":            "cc_binary",
		"BUILD_HOST_EXECUTABLE":       "cc_binary_host",
		"BUILD_NATIVE_TEST":           "cc_test",
		"BUILD_HOST_NATIVE_TEST":      "cc_test_host",
		"BUILD_NATIVE_BENCHMARK":      "cc_benchmark",
		"BUILD_HOST_NATIVE_BENCHMARK": "cc_benchmark_host",
	
		"BUILD_JAVA_LIBRARY":             "java_library_installable", // will be rewritten to java_library by bpfix
		"BUILD_STATIC_JAVA_LIBRARY":      "java_library",
		"BUILD_HOST_JAVA_LIBRARY":        "java_library_host",
		"BUILD_HOST_DALVIK_JAVA_LIBRARY": "java_library_host_dalvik",
		"BUILD_PACKAGE":                  "android_app",
	
		"BUILD_CTS_EXECUTABLE":          "cc_binary",               // will be further massaged by bpfix depending on the output path
		"BUILD_CTS_SUPPORT_PACKAGE":     "cts_support_package",     // will be rewritten to android_test by bpfix
		"BUILD_CTS_PACKAGE":             "cts_package",             // will be rewritten to android_test by bpfix
		"BUILD_CTS_TARGET_JAVA_LIBRARY": "cts_target_java_library", // will be rewritten to java_library by bpfix
		"BUILD_CTS_HOST_JAVA_LIBRARY":   "cts_host_java_library",   // will be rewritten to java_library_host by bpfix
	}
	
	var prebuiltTypes = map[string]string{
		"SHARED_LIBRARIES": "cc_prebuilt_library_shared",
		"STATIC_LIBRARIES": "cc_prebuilt_library_static",
		"EXECUTABLES":      "cc_prebuilt_binary",
		"JAVA_LIBRARIES":   "java_import",
		"ETC":              "prebuilt_etc",
	}
```

#### 构建预编译动态库

```makefile
cc_prebuilt_library_shared {
        name: "libprebuilt_test",
        target: {
            android_arm: {
                srcs: ["lib32/libprebuilt_test.so"],
            },
            android_arm64: {
                srcs: ["lib64/libprebuilt_test.so"],
            },
        },
        strip: {
            none:true,
        },
        shared_libs: ["libx", "libxx", "libxxx", "libxxxx"],
        check_elf_files: false,
        compile_multilib: "both"//32位和64位都预编译
    }
```

或者

```makefile
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libprebuilt_test
LOCAL_MODULE_SUFFIX := .so 
LOCAL_MODULE_CLASS := SHARED_LIBRARIES                                                                                                                                                       
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES_arm := lib32/libprebuilt_test.so
LOCAL_SRC_FILES_arm64 := lib64/libprebuilt_test.so

LOCAL_SHARED_LIBRARIES := libx  libxx  libxxx libxxxx
LOCAL_MULTILIB := both
include $(BUILD_PREBUILT)
```

#### 预编译静态库

```makefile
cc_prebuilt_library_static {
        name: "libprebuilt_static",
        target: {
            android_arm: {
                srcs: ["lib32/libprebuilt_static.a"],
            },
            android_arm64: {
                srcs: ["lib64/libprebuilt_static.a"],
            },
        },
        strip: {
            none:true,
        },
        check_elf_files: false,
        compile_multilib: "both"
}
```

或者

```makefile
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libprebuilt_static
LOCAL_MODULE_SUFFIX := .a
LOCAL_MODULE_CLASS := STATIC_LIBRARIES                                                                                              
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES_arm := arm32/libprebuilt.a
LOCAL_SRC_FILES_arm64 := arm64/libprebuilt.a
LOCAL_CHECK_ELF_FILES := false
LOCAL_MULTILIB := both

include $(BUILD_PREBUILT)
```











### Android-app中执行命令函数

值得注意的是 ，需要已这种方式执行process = Runtime.getRuntime().exec(new String[]{"/bin/sh", "-c", command});

```java
public static String execCommand(String command, int linenum) {
        StringBuilder output = new StringBuilder();
        Process process = null;
        String res = "null";
        try {
            // 执行命令
            process = Runtime.getRuntime().exec(new String[]{"/bin/sh", "-c", command});

            // 读取正常输出流
            InputStream inputStream = process.getInputStream();
            BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream));
            String line;
            int lineNumber = 0;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                //LogUtils.i("wkkk--outputall: " + line);
                if(lineNumber == linenum){
                    LogUtils.i("wkkk--output: " + line);
                    res = line;
                }
              //  output.append(line).append("\n");
            }
           // LogUtils.i("wkk--outputall" + output.toString());
            InputStream errorStream = process.getErrorStream();
            BufferedReader errorReader = new BufferedReader(new InputStreamReader(errorStream));
            while ((line = errorReader.readLine()) != null) {
                //output.append("[ERROR] ").append(line).append("\n");
                res =  "error";
            }

            // 等待命令执行完成
            process.destroy();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
        return res;
    }
```

```java
public static synchronized String executeCommand(String cmd) {

        String result = "";
        Process process = null;
        DataOutputStream os = null;
        try {
            process = Runtime.getRuntime().exec("sh");
            os = new DataOutputStream(process.getOutputStream());
            os.writeBytes(cmd + "\n");
            os.writeBytes("exit\n");
            os.flush();

            char[] buff = new char[1024];
            int ch = 0;
            BufferedReader bfsd = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuffer sbs = new StringBuffer();
            while((ch = bfsd.read(buff)) != -1){
                  sbs.append(buff,0,ch);
            }
            bfsd.close();
            //命令执行失败，接受错误信息
            BufferedReader ero = new BufferedReader(new InputStreamReader(process.getErrorStream()));
            StringBuffer era = new StringBuffer();
            while((ch = ero.read(buff)) != -1){
                   era.append(buff,0,ch);
            }
            ero.close();
            os.close();
            process.destroy();

            if(sbs.length() != 0){
                result = String.valueOf(sbs);
            }else{
                result = String.valueOf(era);
            }

        } catch (IOException e) {
            throw new RuntimeException(e);
        }
        return result;
    }
```





### Android-更新系统api需要更新current.txt

修改framework/base下面的api要注意更新api/current.txt文件

更新android系统接口后，只是提交java文件会导致其他人编译不通过，需要提交/framework/base/api下面更新的三个问文件：

![img](https://img2018.cnblogs.com/blog/1550451/201908/1550451-20190802100958406-122352038.png)

 

如果修改了Android原有API的 ，需要update frameworks/base/api/current.txt。否则编译被中断并出现编译错误提示。

否则，编译时会报以下错误：

```shell
frameworks/base/services/java/com/android/server/SystemServer.java:592: cannot find symbol
symbol  : variable PPPOE_SERVICE
location: class android.content.Context

可以通过运行 make update-api 后，自动更新此文件，检查确认正确后，跟代码一起提交即可。

切记：不能手动更改api/current.txt文件去更新。
```

 

当我们对framework/base/下新增aidl，也就是新增向上api的时候，编译容易出现以下的错误：

```shell
frameworks/base/api/system-current.txt:25031: error 8: Removed public class android.os.IXxxService
frameworks/base/api/system-current.txt:25036: error 8: Removed public class android.os.IXxxService.Stub
out/target/common/obj/PACKAGING/system-api.txt:25035: error 3: Added class IXxxService to package android.os
out/target/common/obj/PACKAGING/system-api.txt:25040: error 3: Added class IXxxService.Stub to package android.os
```

这是因为新增或者修改的api没有及时同步到/frameworks/base/api/system-current.txt文件中，这个时候编译会失败。还有有以下的提示：

```shell
****************************
You have tried to change the API from what has been previously approved.

To make these errors go away, you have two choices:
  \1) You can add "@hide" javadoc comments to the methods, etc. listed in the
   errors above.

  \2) You can update current.txt by executing the following command:
     make update-api

   To submit the revised current.txt to the main Android repository,
   you will need approval.
****************************
```

这个时候我们就需要先执行：

\# make update-api

进行同步，再对代码进行编译便可解决上面的问题。

何时需要执行make update-api命令

添加系统API或者修改@hide的API后，需要执行
make update-api，然后再make
修改公共api后，需要
make update-api

1、在修改完系统Api或部分公共Api后（常见于修改Intent.java、KeyEvent.java等等），执行源码编译时会有如下提示

```shell
see build/core/apicheck_msg_current.txt
******************************
You have tried to change the API from what has been previously approved.

To make these errors go away, you have two choices:
\1) You can add "@hide" javadoc comments to the methods, etc. listed in the
errors above.

\2) You can update current.txt by executing the following command:
make update-api

To submit the revised current.txt to the main Android repository,
you will need approval.
****************************
```

2、错误信息表明是由于API错误导致
谷歌对于所有的类和API，分为开放和非开放两种：而开放的类和API，可以通过“Javadoc标签”与源码同步生成“程序的开发文档”；当我们修改或者添加一个新的API时，我们有两种方案可以避免出现上述错误.

一是将该接口加上 非公开的标签：/*{@hide}/；
二可以在修改后执行：make update-api(公开)，将修改内容与API的doc文件更新到一致。
3、解决办法：
执行： make update -api ;
修改后相应API文件后，在base库下面会产生“.current.txt”文件的差异，提交时将该差异一并提交审核即可。

一、核心作用

1. **API 版本快照**
   - `current.txt` 记录了当前编译环境中 **已批准的 API 版本号**（如 Android 13 对应 API 33）。
   - 在编译过程中，系统会通过此文件验证代码中使用的 API 是否与当前版本一致，防止引入未发布的 API 或回退已废弃的接口
2. **编译时 API 检查**
   - 当代码中调用了某个 API，但当前编译环境的 `current.txt` 中未包含该 API 的声明时，编译器会报错，提示需要更新 API 版本或添加 `@hide` 注解（隐藏 API）。
   - 例如：若在 Android 13（API 33）中调用 Android 14 的 API，编译时会提示 `API 未批准` 错误
3. **跨模块 API 一致性**
   - 在复杂系统（如车载 Android 或定制 ROM）中，不同模块（如 Framework、Services）需共享同一套 API 定义。`current.txt` 确保所有模块基于相同的 API 版本编译，避免接口冲突

------

二、文件内容与结构

- **典型内容示例**：

  `# Android 13 (API 33) platform_api=33`

- **作用说明**：

  - `platform_api` 字段明确当前系统 API 的版本号。
  - 文件通常位于 `frameworks/base/core/api/` 目录下，与 `api/` 目录中的其他 API 定义文件（如 `current.xml`）配合使用

------

三、典型使用场景

1. **新增或修改系统 API**

   - 开发者新增一个公共 API（如 `Context.newFeature()`）后，需执行 `make update-api` 命令，自动更新 `current.txt` 中的版本号，并生成对应的 API 文档。

   - 若未更新 `current.txt`，编译时会报错：

     *You have tried to change the API from what has been previously approved.*

2. **系统镜像兼容性验证**

   - 在设备厂商定制 ROM 时，需确保 `current.txt` 中声明的 API 版本与设备硬件驱动、HAL 层接口兼容。例如，车载系统调用 `UnisocPowerManager` 时，需验证其 API 版本是否支持当前功能

3. **第三方 SDK 集成**

   - 若 Android 系统预装第三方 SDK（如地图服务），需检查 SDK 的 API 版本是否与 `current.txt` 声明一致，避免因版本不匹配导致运行时崩溃

------

四、与其他文件的关联

1. **`api/` 目录下的其他文件**
   - `current.xml`：定义 API 的具体接口（如类、方法、字段）。
   - `removed.txt`：记录已废弃的 API，用于编译时警告开发者。
   - `current.txt` 通过版本号关联这些文件，形成完整的 API 管理体系
2. **构建系统依赖**
   - 在 `Android.mk` 或 `Android.bp` 中，通过 `LOCAL_SDK_VERSION` 指定模块依赖的 API 版本，构建系统会基于 `current.txt` 校验依赖关系

------

五、操作命令示例

1. **更新 API 版本**

   `make update-api # 自动生成或更新 current.txt`

2. **检查 API 变更**

   `make api-stubs-docs-update-current-api # 高版本 Android 的专用命令`

3. **手动修改（不推荐）**

   - 直接编辑 `current.txt` 可能导致版本号与实际代码不一致，需通过构建系统自动维护

------

六、常见问题与解决

- **编译错误：API 版本不匹配**
  ​**​解决​**​：执行 `make update-api` 后重新提交 `current.txt` 的变更，提交前需通过代码审核（如 Gerrit）
- **隐藏 API 暴露**
  ​**​解决​**​：若需临时使用未公开 API，可在代码中添加 `@hide` 注解，但需后续通过 `update-api` 同步到官方 API 列表

------

总结

`current.txt` 是 Android 系统 API 版本管理的核心文件，通过强制版本校验确保系统各模块的兼容性和稳定性。开发者需严格遵循其更新流程，避免因 API 版本冲突导致编译或运行时问题。





### Android-so，bin预制vendor system目录



在Android14上使用vendor：true，生成物只会在vendor目录，使用vendor_available: true,则只会在system目录底下，最近就遇到hal层服务想要预制到vendor和system目录中，但是只能预制到一个目录，后面经过查找资料

```xml
cc_prebuilt_library_shared {
    name: "android.hardware.wkk@1.0-impl",
    relative_install_path: "hw",
    srcs: [
        "android.hardware.wkk@1.0-impl.so",
    ],
    vendor_available: true,
	defaults: ["hidl_defaults"], 
	compile_multilib:"first",
	//allow_undefined_symbols: true,
    shared_libs: [
    ],

	static_libs: [
    ],
}

cc_prebuilt_binary {
    relative_install_path: "hw",
    defaults: ["hidl_defaults"],
    vendor_available: true,
    name: "android.hardware.wkk@1.0-service",
    init_rc: ["android.hardware.wkk@1.0-service.rc"],
    srcs: ["android.hardware.wkk@1.0-service"],
	compile_multilib:"first"
}
```

![img](file:///C:/Users/Y6809/Documents/WXWork/1688856074714433/Cache/Image/2025-10/dac84031-1cb5-445b-a7e3-b48f30794185.png)

发现需要在编译时加入PRODUCT_PACKAGES +=   android.hardware.wkk@1.0-impl.vendor,这样就可以编译到两个目录都有了

顺便提一下，Android高版本加入了这个，这样就可以不用手动在其他目录底下加，以下是官网解释

在 Android 10 及更高版本中，您可以在构建系统中将清单条目与 HAL 模块相关联。这有助于在构建系统中有条件地包含 HAL 模块。

示例

在 `Android.bp` 或 `Android.mk` 文件中，将 `vintf_fragments` 添加到设备上明确安装的任何模块（例如 `cc_binary` 或 `rust_binary`）。 例如，您可以修改实现了 HAL 的模块 (`my.package.foo@1.0-service-bar`)。

```
... {
    ...
    vintf_fragments: ["manifest_foo.xml"],
    ...
}
LOCAL_MODULE := ...
LOCAL_VINTF_FRAGMENTS := manifest_foo.xml
```

在名为 `manifest_foo.xml` 的文件中，为此模块创建清单。在构建时，此清单会添加到设备中。在此处添加条目与在设备的主清单中添加条目相同。这样，客户端就可以使用该接口，并允许 VTS 识别设备上的 HAL 实现。此清单会执行常规清单执行的任何操作。

下面的示例实现了安装到 `vendor` 或 `odm` 分区的 `android.hardware.foo@1.0::IFoo/default`。如果安装到 `system`、`product` 或 `system_ext` 分区，则改为使用 `framework` 类型，而不是 `device` 类型。

```
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>android.hardware.foo</name>
        <transport>hwbinder</transport>
        <fqname>@1.0::IFoo/default</fqname>
    </hal>
</manifest>
```

如果 HAL 模块已打包到[供应商 APEX](https://source.android.google.cn/docs/core/ota/vendor-apex?hl=zh-cn) 中，请使用 `prebuilt_etc` 将其关联的 VINTF fragment 打包到同一 APEX 中，如 [VINTF fragment](https://source.android.google.cn/docs/core/ota/vendor-apex?hl=zh-cn#vintf_fragments) 中所述。





### Android-加载so库报错

在加载so库的时候报错，先来看下报错

```java
2025-10-31 11:38:10.588 3853-3853/com.wkk.app.avmdemo E/AndroidRuntime: FATAL EXCEPTION: main
    Process: com.adayo.app.avmdemo, PID: 3853
    java.lang.UnsatisfiedLinkError: dlopen failed: library "/system/lib64/libevsserviceproxy_jni.so" needed or dlopened by "/apex/com.android.art/lib64/libnativeloader.so" is not accessible for the namespace "clns-7"
        at java.lang.Runtime.loadLibrary0(Runtime.java:1082)
        at java.lang.Runtime.loadLibrary0(Runtime.java:1003)
        at java.lang.System.loadLibrary(System.java:1661)
        at com.adayo.proxy.adas.evs.EvsCameraMng.<clinit>(EvsCameraMng.java:12)
        at com.adayo.app.avmdemo.MainActivity.onCreate(MainActivity.java:33)
        at android.app.Activity.performCreate(Activity.java:8621)
        at android.app.Activity.performCreate(Activity.java:8599)
        at android.app.Instrumentation.callActivityOnCreate(Instrumentation.java:1456)
        at android.app.ActivityThread.performLaunchActivity(ActivityThread.java:3804)
        at android.app.ActivityThread.handleLaunchActivity(ActivityThread.java:3963)
        at android.app.servertransaction.LaunchActivityItem.execute(LaunchActivityItem.java:103)
        at android.app.servertransaction.TransactionExecutor.executeCallbacks(TransactionExecutor.java:139)
        at android.app.servertransaction.TransactionExecutor.execute(TransactionExecutor.java:96)
        at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2468)
        at android.os.Handler.dispatchMessage(Handler.java:106)
        at android.os.Looper.loopOnce(Looper.java:205)
        at android.os.Looper.loop(Looper.java:294)
        at android.app.ActivityThread.main(ActivityThread.java:8248)
        at java.lang.reflect.Method.invoke(Native Method)
        at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:552)
        at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:993)
```

首先，主要原因是google在新版本上对.so库的加载进行了限制，限制了so库指从部分指定的路径进行加载，不在这个路径的so提示 
java.lang.UnsatisfiedLinkError: dlopen failed: library “xxx.so” not found 或 
java.lang.UnsatisfiedLinkError: dlopen failed: library “/vendor/lib64/xxx.so” needed or dlopened by “/system/lib64/libnativeloader.so” is not accessible for the namespace “classloader-namespace” 或 其他异常错误提示。

N上对so库加载的搜索路径方式为ld_library_path, runtime path, permit path，不在这个搜索路径下则加载失败。

从代码层面看，主要是类加载器ClassLoader的相关处理， 
code1: (loadedApk.java getClassLoader()) check sdk version 
// DO NOT SHIP: this is a workaround for apps loading native libraries 
// provided by 3rd party apps using absolute path instead of corresponding 
// classloader; see http://b/26954419 for example. 
if (mApplicationInfo.targetSdkVersion <= 23) { 
libraryPermittedPath += File.pathSeparator + “/data/app”; 
}

Code2: (loadedApk.java getClassLoader()) N add a new PermittedPath 
String libraryPermittedPath = mDataDir;

Code3: (native_loader.cpp) use the new namespace rule with search path: ld_library_path, runtime path, permit path.

在明白原因之后， 
解决办法则是将自己的so加入到允许路径的白名单里面，具体操作为，如果不改代码实现，则导出设备的/vendor/etc/public.libraries.txt 或/etc/public.libraries.txt文件，将so名字添加进去，在push到设备，重启即可

Android 新版本有个新feature，就是普通应用不能直接引用系统的一些so库了，只能直接引用public.libraries.txt文件中过滤的so库

应用可以调用/vendor/etc/public.libraries.txt和/system/etc/public.libraries.txt里面的所有so库，所以往这个文件写入libhaha_utils.so，这个库就变成共用的了，任意应用就可以找到这个so库了，终于可以欢快地使用install apk的方式调试啦！！再也不用重启了！！

在这个源码里面用到这个txt文件
/[system](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2F)/[core](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2F)/[libnativeloader](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2Flibnativeloader%2F)/[native_loader.cpp](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2Flibnativeloader%2Fnative_loader.cpp)
在LibraryNamespaces类的Initialize()会读取这个文件，将so库设置为公共so库，所谓公共so库，就是这个so库谁都能用啦。

```c++
static constexpr const char* kPublicNativeLibrariesSystemConfigPathFromRoot = "/etc/public.libraries.txt";
static constexpr const char* kPublicNativeLibrariesVendorConfig = "/vendor/etc/public.libraries.txt";
  void Initialize() {
    ..................
    std::vector<std::string> sonames;
    ReadConfig(public_native_libraries_system_config, &sonames, &error_msg),
    ReadConfig(kPublicNativeLibrariesVendorConfig, &sonames);
    public_libraries_ = base::Join(sonames, ':');
    .............
  }
```

这个方法时什么时候调用的呢？大概过下流程罗。
首先在创建一个虚拟机的时候，初始化NativeLoader，这个NativeLoader，顾名思义，就是用来装载so库的。
/[art](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fart%2F)/[runtime](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fart%2Fruntime%2F)/ [java_vm_ext.cc](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fart%2Fruntime%2Fjava_vm_ext.cc)

```c++
extern "C" jint JNI_CreateJavaVM(JavaVM** p_vm, JNIEnv** p_env, void* vm_args) {
  ................
  // Initialize native loader. This step makes sure we have
  // everything set up before we start using JNI.
  android::InitializeNativeLoader();
  ..............
}
```

然后进入native_loader，进行初始化
/[system](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2F)/[core](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2F)/[libnativeloader](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2Flibnativeloader%2F)/[native_loader.cpp](https://link.juejin.im/?target=http%3A%2F%2Fandroidxref.com%2F7.1.1_r6%2Fxref%2Fsystem%2Fcore%2Flibnativeloader%2Fnative_loader.cpp)

```c++
static LibraryNamespaces* g_namespaces = new LibraryNamespaces;

 void InitializeNativeLoader() {
  g_namespaces->Initialize();
 }

```

初始化是调用LibraryNamespaces类的Initialize完成公共so库的赋值，哈哈哈，搞定！！

```c++
void Initialize() {
    ..................
    std::vector<std::string> sonames;
    ReadConfig(public_native_libraries_system_config, &sonames, &error_msg),
    ReadConfig(kPublicNativeLibrariesVendorConfig, &sonames);
    public_libraries_ = base::Join(sonames, ':');
    .............
  }
```

总结：
1.Android N 不能直接调用系统的一些私有库了，公用的库都定义在public.libraries.txt里面。