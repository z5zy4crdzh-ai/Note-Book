### Zygote

Zygote是一个特殊的进程，它作为新应用程序进程的孵化器。当用户启动一个新的应用程序时，Zygote会被启动，并负责创建和孵化新的应用程序进程。

以下是Zygote启动的基本过程：

0.  **系统启动**：当安卓设备启动时，系统会加载Zygote的可执行文件到内存中，并将其作为一个系统服务启动。
0.  **初始化过程**：Zygote在启动后进行一系列的初始化操作，包括创建虚拟机（VM）实例、加载系统类和资源等。
0.  **等待新请求**：Zygote进入一个循环等待状态，监听来自系统和应用程序管理器的请求。
0.  **接收应用程序请求**：当用户启动一个新的应用程序时，应用程序管理器会向Zygote发送一个请求，请求创建一个新的应用程序进程。
0.  **复制自身**：在收到创建新应用程序进程的请求后，Zygote会使用fork()系统调用创建一个与自身相似的子进程。
0.  **应用程序进程孵化**：在子进程中，Zygote会执行一些必要的操作，如设置应用程序的环境变量、加载应用程序的代码和资源等。
0.  **应用程序启动**：一旦孵化过程完成，Zygote会通过调用应用程序的入口点来启动新的应用程序进程。

详细步骤：

1）创建Java虚拟机，为Java虚拟机注册native方法；

2）在com.android.internal.os.ZygoteInit中调用java类的主要方法；

3）加载ZygoteInit class；

4）注册zygote socket；

5）加载preload class；/system/etc/preloaded-classes

6）加载preload 资源文件；

7）调用Zygote::forkSystemServer，fork一个新的进程，调用SystemServer的main方法，从而进入到java层的system_server进程的初始化流程中；

通过这种方式，Zygote可以减少应用程序的启动时间，因为它预加载了常用的类和资源，并提供了一个干净的应用程序进程副本。这样，每次启动应用程序时，Zygote只需要复制自身并加载应用程序特定的部分，而不必重新创建整个进程。这种孵化机制有助于提高应用程序的响应速度和系统性能。

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/555ff8d46fe3410aa1d1ba39c05a3027~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=892&h=622&s=140809&e=png&b=fefefe)

Zygote启动后–>入口app_main.cpp的main方法： 入口函数调用AndroidRuntime的startVM()方法创建虚拟机; 在调用startReg()注册JNI函数通过JNI方式调用ZygoteInit.main()。 注册socket进行预加载，fork systemserver进程

#### init.zygote64.rc：

init.zygote64是一个初始化脚本，用于在启动过程中设置和启动Zygote进程的64位版本。具体来说，init.zygote64脚本的作用包括以下几个方面：

0.  **环境初始化**：init.zygote64脚本负责初始化Zygote进程的环境，包括设置环境变量、加载系统属性等操作。
0.  **启动Zygote进程**：该脚本会启动Zygote进程的64位版本，为后续应用程序的孵化做准备。
0.  **执行预启动操作**：init.zygote64可能会执行一些预启动的操作，例如预加载一些常用的类库和资源，以加速应用程序的启动。
0.  **设置权限和用户**：init.zygote64可能会设置Zygote进程的权限和所属用户，以确保进程能够正常运行并且有足够的权限。

总的来说，init.zygote64脚本在安卓系统启动过程中扮演着重要角色，它负责启动和初始化Zygote进程的64位版本，为后续应用程序的启动提供必要的环境和准备工作

\build\android\system\core\rootdir\init.zygote64.rc

```
service zygote /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server
    class main
    priority -20
    user root
    group root readproc reserved_disk
    socket zygote stream 660 root system
    socket usap_pool_primary stream 660 root system
    onrestart write /sys/android_power/request_state wake
    onrestart write /sys/power/state on
    onrestart restart audioserver
    onrestart restart cameraserver
    onrestart restart media
    onrestart restart netd
    onrestart restart wificond
    onrestart restart vendor.servicetracker-1-1
    writepid /dev/cpuset/foreground/tasks

```

#### AndroidRuntime.cpp：

\build\android\frameworks\base\core\jni\AndroidRuntime.cpp

启动java虚拟机

```
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

    const char* rootDir = getenv("ANDROID_ROOT");
    if (rootDir == NULL) {
        rootDir = "/system";
        if (!hasDir("/system")) {
            LOG_FATAL("No root directory specified, and /system does not exist.");
            return;
        }
        setenv("ANDROID_ROOT", rootDir, 1);
    }

    const char* runtimeRootDir = getenv("ANDROID_RUNTIME_ROOT");
    if (runtimeRootDir == NULL) {
        LOG_FATAL("No runtime directory specified with ANDROID_RUNTIME_ROOT environment variable.");
        return;
    }

    const char* tzdataRootDir = getenv("ANDROID_TZDATA_ROOT");
    if (tzdataRootDir == NULL) {
        LOG_FATAL("No tz data directory specified with ANDROID_TZDATA_ROOT environment variable.");
        return;
    }

    //const char* kernelHack = getenv("LD_ASSUME_KERNEL");
    //ALOGD("Found LD_ASSUME_KERNEL='%s'\n", kernelHack);

    /* start the virtual machine */             // 启动java虚拟机
    JniInvocation jni_invocation;
    jni_invocation.Init(NULL);
    JNIEnv* env;
    if (startVm(&mJavaVM, &env, zygote) != 0) {
        return;
    }
    onVmCreated(env);                         

    /*
     * Register android functions.             // 注册JNI方法
     */
    if (startReg(env) < 0) {
        ALOGE("Unable to register all android natives\n");
        return;
    }

    /*
     * We want to call main() with a String array with arguments in it.
     * At present we have two arguments, the class name and an option string.
     * Create an array to hold them.
     */
    jclass stringClass;                    // 有了java，这里就可以调用java方法
    jobjectArray strArray;
    jstring classNameStr;
    
    stringClass = env->FindClass("java/lang/String");
    assert(stringClass != NULL);
    strArray = env->NewObjectArray(options.size() + 1, stringClass, NULL);
    assert(strArray != NULL);
    classNameStr = env->NewStringUTF(className);
    assert(classNameStr != NULL);
    env->SetObjectArrayElement(strArray, 0, classNameStr);

    for (size_t i = 0; i < options.size(); ++i) {
        jstring optionsStr = env->NewStringUTF(options.itemAt(i).string());
        assert(optionsStr != NULL);
        env->SetObjectArrayElement(strArray, i + 1, optionsStr);
    }

    /*
     * Start VM.  This thread becomes the main thread of the VM, and will
     * not return until the VM exits.
     */
    char* slashClassName = toSlashClassName(className != NULL ? className : "");
    jclass startClass = env->FindClass(slashClassName);
    if (startClass == NULL) {
        ALOGE("JavaVM unable to locate class '%s'\n", slashClassName);
        /* keep going */
    } else {
        jmethodID startMeth = env->GetStaticMethodID(startClass, "main",
            "([Ljava/lang/String;)V");
        if (startMeth == NULL) {
            ALOGE("JavaVM unable to find main() in '%s'\n", className);
            /* keep going */
        } else {
            env->CallStaticVoidMethod(startClass, startMeth, strArray);

#if 0
            if (env->ExceptionCheck())
                threadExitUncaughtException(env);
#endif
        }
    }
    free(slashClassName);

    ALOGD("Shutting down VM\n");
    if (mJavaVM->DetachCurrentThread() != JNI_OK)
        ALOGW("Warning: unable to detach main thread\n");
    if (mJavaVM->DestroyJavaVM() != 0)
        ALOGW("Warning: VM did not shut down cleanly\n");
}
```

#### app_main.cpp：

\build\android\frameworks\base\cmds\app_process\app_main.cpp

```
int main(int argc, char* const argv[])
{
    std::string bootmode = GetProperty("ro.bootmode", "");

    if ((strncmp(bootmode.c_str(), "ffbm-00", 7) == 0)
            || (strncmp(bootmode.c_str(), "ffbm-01", 7) == 0)) {
            return 0;
    }

    if (!LOG_NDEBUG) {
      String8 argv_String;
      for (int i = 0; i < argc; ++i) {
        argv_String.append(""");
        argv_String.append(argv[i]);
        argv_String.append("" ");
      }
      ALOGV("app_process main with argv: %s", argv_String.string());
    }

    AppRuntime runtime(argv[0], computeArgBlockSize(argc, argv));
    // Process command line arguments
    // ignore argv[0]
    argc--;
    argv++;

    // Everything up to '--' or first non '-' arg goes to the vm.
    //
    // The first argument after the VM args is the "parent dir", which
    // is currently unused.
    //
    // After the parent dir, we expect one or more the following internal
    // arguments :
    //
    // --zygote : Start in zygote mode
    // --start-system-server : Start the system server.
    // --application : Start in application (stand alone, non zygote) mode.
    // --nice-name : The nice name for this process.
    //
    // For non zygote starts, these arguments will be followed by
    // the main class name. All remaining arguments are passed to
    // the main method of this class.
    //
    // For zygote starts, all remaining arguments are passed to the zygote.
    // main function.
    //
    // Note that we must copy argument string values since we will rewrite the
    // entire argument block when we apply the nice name to argv0.
    //
    // As an exception to the above rule, anything in "spaced commands"
    // goes to the vm even though it has a space in it.
    const char* spaced_commands[] = { "-cp", "-classpath" };
    // Allow "spaced commands" to be succeeded by exactly 1 argument (regardless of -s).
    bool known_command = false;

    int i;
    for (i = 0; i < argc; i++) {
        if (known_command == true) {
          runtime.addOption(strdup(argv[i]));
          // The static analyzer gets upset that we don't ever free the above
          // string. Since the allocation is from main, leaking it doesn't seem
          // problematic. NOLINTNEXTLINE
          ALOGV("app_process main add known option '%s'", argv[i]);
          known_command = false;
          continue;
        }

        for (int j = 0;
             j < static_cast<int>(sizeof(spaced_commands) / sizeof(spaced_commands[0]));
             ++j) {
          if (strcmp(argv[i], spaced_commands[j]) == 0) {
            known_command = true;
            ALOGV("app_process main found known command '%s'", argv[i]);
          }
        }

        if (argv[i][0] != '-') {
            break;
        }
        if (argv[i][1] == '-' && argv[i][2] == 0) {
            ++i; // Skip --.
            break;
        }

        runtime.addOption(strdup(argv[i]));
        // The static analyzer gets upset that we don't ever free the above
        // string. Since the allocation is from main, leaking it doesn't seem
        // problematic. NOLINTNEXTLINE
        ALOGV("app_process main add option '%s'", argv[i]);
    }

    // Parse runtime arguments.  Stop at first unrecognized option.
    bool zygote = false;
    bool startSystemServer = false;
    bool application = false;
    String8 niceName;
    String8 className;

    ++i;  // Skip unused "parent dir" argument.
    while (i < argc) {
        const char* arg = argv[i++];
        if (strcmp(arg, "--zygote") == 0) {
            zygote = true;
            niceName = ZYGOTE_NICE_NAME;
        } else if (strcmp(arg, "--start-system-server") == 0) {
            startSystemServer = true;
        } else if (strcmp(arg, "--application") == 0) {
            application = true;
        } else if (strncmp(arg, "--nice-name=", 12) == 0) {
            niceName.setTo(arg + 12);
        } else if (strncmp(arg, "--", 2) != 0) {
            className.setTo(arg);
            break;
        } else {
            --i;
            break;
        }
    }

    Vector<String8> args;
    if (!className.isEmpty()) {
        // We're not in zygote mode, the only argument we need to pass
        // to RuntimeInit is the application argument.
        //
        // The Remainder of args get passed to startup class main(). Make
        // copies of them before we overwrite them with the process name.
        args.add(application ? String8("application") : String8("tool"));
        runtime.setClassNameAndArgs(className, argc - i, argv + i);

        if (!LOG_NDEBUG) {
          String8 restOfArgs;
          char* const* argv_new = argv + i;
          int argc_new = argc - i;
          for (int k = 0; k < argc_new; ++k) {
            restOfArgs.append(""");
            restOfArgs.append(argv_new[k]);
            restOfArgs.append("" ");
          }
          ALOGV("Class name = %s, args = %s", className.string(), restOfArgs.string());
        }
    } else {
        // We're in zygote mode.
        maybeCreateDalvikCache();

        if (startSystemServer) {
            args.add(String8("start-system-server"));
        }

        char prop[PROP_VALUE_MAX];
        if (property_get(ABI_LIST_PROPERTY, prop, NULL) == 0) {
            LOG_ALWAYS_FATAL("app_process: Unable to determine ABI list from property %s.",
                ABI_LIST_PROPERTY);
            return 11;
        }

        String8 abiFlag("--abi-list=");
        abiFlag.append(prop);
        args.add(abiFlag);

        // In zygote mode, pass all remaining arguments to the zygote
        // main() method.
        for (; i < argc; ++i) {
            args.add(String8(argv[i]));
        }
    }

    if (!niceName.isEmpty()) {
        runtime.setArgv0(niceName.string(), true /* setProcName */);
    }

    if (zygote) {            // 根据上面的执行，zygote会赋值为true，会进入这个if
        runtime.start("com.android.internal.os.ZygoteInit", args, zygote);
    } else if (className) {
        runtime.start("com.android.internal.os.RuntimeInit", args, zygote);
    } else {
        fprintf(stderr, "Error: no class name or --zygote supplied.\n");
        app_usage();
        LOG_ALWAYS_FATAL("app_process: no class name or --zygote supplied.");
    }
}
```

#### ZygoteInit.java：

\build\android\frameworks\base\core\java\com\android\internal\os\ZygoteInit.java

1.调用preload()来预加载类和资源 2.调用ZygoteServer()创建两个Server端的Socket用来等待ActivityManagerService来请求Zygote来创建新的应用程序进程。 3.调用forkSystemServer来启动SystemServer进程 4.最后调用runSelectLoop 函数来等待客户端请求Zygote进程，通过fork()函数，最终孵化出system_server的进程，通过反射的方法启动

Zygote本身是一个Native的应用程序，刚开始的进程名称为“app_process”，运行过程中,通过调用setArgv0将名字改为zygote或者 zygote64(根据操作系统而来)，最后通过runtime的start()方法来加载虚拟机并进入JAVA程序

预加载，加快app启动：

```
static void preload(TimingsTraceLog bootTimingsTraceLog) {
        Log.d(TAG, "begin preload");
        bootTimingsTraceLog.traceBegin("BeginPreload");
        beginPreload();
        bootTimingsTraceLog.traceEnd(); // BeginPreload
        bootTimingsTraceLog.traceBegin("PreloadClasses");
        preloadClasses();
        bootTimingsTraceLog.traceEnd(); // PreloadClasses
        bootTimingsTraceLog.traceBegin("CacheNonBootClasspathClassLoaders");
        cacheNonBootClasspathClassLoaders();
        bootTimingsTraceLog.traceEnd(); // CacheNonBootClasspathClassLoaders
        bootTimingsTraceLog.traceBegin("PreloadResources");
        preloadResources();
        bootTimingsTraceLog.traceEnd(); // PreloadResources
        Trace.traceBegin(Trace.TRACE_TAG_DALVIK, "PreloadAppProcessHALs");
        nativePreloadAppProcessHALs();
        Trace.traceEnd(Trace.TRACE_TAG_DALVIK);
        Trace.traceBegin(Trace.TRACE_TAG_DALVIK, "PreloadGraphicsDriver");
        maybePreloadGraphicsDriver();
        Trace.traceEnd(Trace.TRACE_TAG_DALVIK);
        preloadSharedLibraries();
        preloadTextResources();
        // Ask the WebViewFactory to do any initialization that must run in the zygote process,
        // for memory sharing purposes.
        WebViewFactory.prepareWebViewInZygote();
        endPreload();
        warmUpJcaProviders();
        Log.d(TAG, "end preload");

        sPreloadComplete = true;
    }
```

#### main()：

1.调用preload()来预加载类和资源 2.调用ZygoteServer()创建两个Server端的Socket用来等待ActivityManagerService来请求Zygote来创建新的应用程序进程。 3.调用forkSystemServer来启动SystemServer进程 4.最后调用runSelectLoop 函数来等待客户端请求Zygote进程，通过fork()函数，最终孵化出system_server的进程，通过反射的方法启动

```
public static void main(String argv[]) {
        ZygoteServer zygoteServer = null;

        // Mark zygote start. This ensures that thread creation will throw
        // an error.
        ZygoteHooks.startZygoteNoThreadCreation();

        // Zygote goes into its own process group.
        try {
            Os.setpgid(0, 0);
        } catch (ErrnoException ex) {
            throw new RuntimeException("Failed to setpgid(0,0)", ex);
        }

        Runnable caller;
        try {
            // Report Zygote start time to tron unless it is a runtime restart
            if (!"1".equals(SystemProperties.get("sys.boot_completed"))) {
                MetricsLogger.histogram(null, "boot_zygote_init",
                        (int) SystemClock.elapsedRealtime());
            }

            String bootTimeTag = Process.is64Bit() ? "Zygote64Timing" : "Zygote32Timing";
            TimingsTraceLog bootTimingsTraceLog = new TimingsTraceLog(bootTimeTag,
                    Trace.TRACE_TAG_DALVIK);
            bootTimingsTraceLog.traceBegin("ZygoteInit");
            RuntimeInit.enableDdms();

            boolean startSystemServer = false;
            String zygoteSocketName = "zygote";
            String abiList = null;
            boolean enableLazyPreload = false;
            for (int i = 1; i < argv.length; i++) {
                if ("start-system-server".equals(argv[i])) {
                    startSystemServer = true;
                } else if ("--enable-lazy-preload".equals(argv[i])) {
                    enableLazyPreload = true;
                } else if (argv[i].startsWith(ABI_LIST_ARG)) {
                    abiList = argv[i].substring(ABI_LIST_ARG.length());
                } else if (argv[i].startsWith(SOCKET_NAME_ARG)) {
                    zygoteSocketName = argv[i].substring(SOCKET_NAME_ARG.length());
                } else {
                    throw new RuntimeException("Unknown command line argument: " + argv[i]);
                }
            }

            final boolean isPrimaryZygote = zygoteSocketName.equals(Zygote.PRIMARY_SOCKET_NAME);

            if (abiList == null) {
                throw new RuntimeException("No ABI list supplied.");
            }

            // In some configurations, we avoid preloading resources and classes eagerly.
            // In such cases, we will preload things prior to our first fork.
            if (!enableLazyPreload) {
                bootTimingsTraceLog.traceBegin("ZygotePreload");
                EventLog.writeEvent(LOG_BOOT_PROGRESS_PRELOAD_START,
                        SystemClock.uptimeMillis());
                preload(bootTimingsTraceLog);
                EventLog.writeEvent(LOG_BOOT_PROGRESS_PRELOAD_END,
                        SystemClock.uptimeMillis());
                bootTimingsTraceLog.traceEnd(); // ZygotePreload
            } else {
                Zygote.resetNicePriority();
            }

            // Do an initial gc to clean up after startup
            bootTimingsTraceLog.traceBegin("PostZygoteInitGC");
            gcAndFinalize();
            bootTimingsTraceLog.traceEnd(); // PostZygoteInitGC

            bootTimingsTraceLog.traceEnd(); // ZygoteInit
            // Disable tracing so that forked processes do not inherit stale tracing tags from
            // Zygote.
            Trace.setTracingEnabled(false, 0);


            Zygote.initNativeState(isPrimaryZygote);

            ZygoteHooks.stopZygoteNoThreadCreation();

            zygoteServer = new ZygoteServer(isPrimaryZygote);

            if (startSystemServer) {
                Runnable r = forkSystemServer(abiList, zygoteSocketName, zygoteServer);

                // {@code r == null} in the parent (zygote) process, and {@code r != null} in the
                // child (system_server) process.
                if (r != null) {
                    r.run();
                    return;
                }
            }

            Log.i(TAG, "Accepting command socket connections");

            // The select loop returns early in the child process after a fork and
            // loops forever in the zygote.
            caller = zygoteServer.runSelectLoop(abiList);
        } catch (Throwable ex) {
            Log.e(TAG, "System zygote died with exception", ex);
            throw ex;
        } finally {
            if (zygoteServer != null) {
                zygoteServer.closeServerSocket();
            }
        }
```

Zygote孵化应用进程

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/a5eb00c006b946abbc73857c00d87dcd~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=554&h=219&s=54264&e=png&b=fdfdfd)

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/ff4e2fa322314c0492140d9dda407dc4~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=856&h=336&s=128462&e=png&b=fffefe)