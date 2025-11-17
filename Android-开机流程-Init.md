### Init

init是 Android 启动的第一个用户空间进程，它的地位非常重要，它fork产生系统的一些关键进程(如zygote，surfaceflinger进程)，而zygote进一步fork产生system\_server和其他应用进程，通过这套逻辑构建了Android的进程层次结构体系。init进程的功能包含但不限于以下：

*   挂载系统分区和加载一些内核模块
*   加载sepolicy 及使能 selinux
*   支持属性服务
*   启动脚本rc文件解析
*   执行事件触发器和属性改变的事件
*   子进程死亡监听，回收僵尸进程
*   非oneshot服务保活

通过[ps命令](https://so.csdn.net/so/search?q=ps%E5%91%BD%E4%BB%A4\&spm=1001.2101.3001.7020)看看init进程信息


```shell
# ps -A|grep init                                                                                                           
root             1     0 10847128  4020 do_epoll_wait       0 S init  # 这个是 init 进程
root           166     1 10817360  1916 do_sys_poll         0 S init  # 这个是 subcontext 进程
```

1.环境变量设置

2.挂载部分文件系统并创建目录，创建设备节点

3.初始化日志输出等

4.启用SELinux安全策略

5.开启第二阶段流程

第二个阶段主要完成：

1.初始化属性区

2.执行SELinux第二阶段

3.新建epoll并初始化子进程终止信号处理函数

4.解析系统属性文件，并开启属性服务

5.拉起subcontext

6.加载rc脚本，开其脚本解析，执行对应流程

![image-20231114110745359转存失败，建议直接上传图片文件](<转存失败，建议直接上传图片文件 >)

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/8450862d178c41d0aa0e977d4a93ff98~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=581\&h=854\&s=104011\&e=png\&b=fefefe)

#### main()：

build\sa6125-car-r600\android\system\core\init\main.cpp

    using namespace android::init;
    
    int main(int argc, char** argv) {
    #if __has_feature(address_sanitizer)
        __asan_set_error_report_callback(AsanReportCallback);
    #endif
    
        if (!strcmp(basename(argv[0]), "ueventd")) {        // ueventd跳转
            return ueventd_main(argc, argv);
        }
    
        if (argc > 1) {
            if (!strcmp(argv[1], "subcontext")) {          // 拉起subcontext
                android::base::InitLogging(argv, &android::base::KernelLogger);
                const BuiltinFunctionMap function_map;
    
                return SubcontextMain(argc, argv, &function_map);
            }
    
            if (!strcmp(argv[1], "selinux_setup")) {       // SELinux服务初始化阶段
                return SetupSelinux(argv);
            }
    
            if (!strcmp(argv[1], "second_stage")) {        // 启动Init进程第二阶段，启动熟悉服务，加载进程 
                return SecondStageMain(argc, argv);
            }
        }
    
        return FirstStageMain(argc, argv);
    }

#### ueventd\_main()：

build\android\system\core\init\ueventd.cpp

负责节点创建，Android中的ueventd是一个守护进程，它通过netlink scoket监听内核生成的uevent消息，当ueventd收到这样的消息时，它通过采取适当的行动来处理它，通常是在/dev中创建设备节点，设置文件权限，设置selinux标签等。ueventd的启动和之前的selinux、subcontext不一样。ueventd时在init.rc中定义service，被second\_stage\_init创建出来的

**ueventd通过两种方式创建设备节点文件分别是冷启动和热启动:** 1.冷启动:通俗讲就是已经设定好的,比如 cpu频率，统一创建好的文件节点。 2.执启动:诵俗讲就是动态创建的比加 ush插拔等节占

    int ueventd_main(int argc, char** argv) {
        /*
         * init sets the umask to 077 for forked processes. We need to
         * create files with exact permissions, without modification by
         * the umask.
         */
        umask(000);        // 清除系统默认权限，保证新建目录的访问权限由mkdir
    
        android::base::InitLogging(argv, &android::base::KernelLogger);
    
        LOG(INFO) << "ueventd started!";
    
        SelinuxSetupKernelLogging();
        SelabelInitialize();
    
        std::vector<std::unique_ptr<UeventHandler>> uevent_handlers;
    
        // Keep the current product name base configuration so we remain backwards compatible and
        // allow it to override everything.
        // TODO: cleanup platform ueventd.rc to remove vendor specific device node entries (b/34968103)
        auto hardware = android::base::GetProperty("ro.hardware", "");
    
        auto ueventd_configuration = ParseConfig({"/ueventd.rc", "/vendor/ueventd.rc",
                                                  "/odm/ueventd.rc", "/ueventd." + hardware + ".rc"});
    
        uevent_handlers.emplace_back(std::make_unique<DeviceHandler>(
                std::move(ueventd_configuration.dev_permissions),
                std::move(ueventd_configuration.sysfs_permissions),
                std::move(ueventd_configuration.subsystems), android::fs_mgr::GetBootDevices(), true));
        uevent_handlers.emplace_back(std::make_unique<FirmwareHandler>(
                std::move(ueventd_configuration.firmware_directories)));
    
        if (ueventd_configuration.enable_modalias_handling) {
            uevent_handlers.emplace_back(std::make_unique<ModaliasHandler>());
        }
        UeventListener uevent_listener(ueventd_configuration.uevent_socket_rcvbuf_size);
    
        if (access(COLDBOOT_DONE, F_OK) != 0) {
            ColdBoot cold_boot(uevent_listener, uevent_handlers);
            cold_boot.Run();
        }
    
        for (auto& uevent_handler : uevent_handlers) {
            uevent_handler->ColdbootDone();
        }
    
        // We use waitpid() in ColdBoot, so we can't ignore SIGCHLD until now.
        signal(SIGCHLD, SIG_IGN);
        // Reap and pending children that exited between the last call to waitpid() and setting SIG_IGN
        // for SIGCHLD above.
        while (waitpid(-1, nullptr, WNOHANG) > 0) {
        }
    
        uevent_listener.Poll([&uevent_handlers](const Uevent& uevent) {
            for (auto& uevent_handler : uevent_handlers) {
                uevent_handler->HandleUevent(uevent);
            }
            return ListenerAction::kContinue;
        });
    
        return 0;
    }

#### FirstStageMain()：

build\android\system\core\init\first\_stage\_main.cpp

umask(0)：清除系统默认权限，保证新建目录的访问权限由mkdir设置。 使用mkdir/mount/chmod指令来创建基本文件系统目录并挂载相关的文件系统。Android系统挂载了tmpfs、devpts、proc、sysfs这四类文件系统。其中，/dev是设备目录，所有外部设备和虚拟设备都在该目录下；/proc是存储当前系统内核运行信息的文件目录，/sys存储了硬件设备在内核上的映射。 SetStdioToDevNull()：关闭/stdin/stdout/stderr的fd，重定向到/dev/null。 InitKernelLogging()：初始化kernel日志，输出到/dev/kmsg。 load内核各模块。 第一阶段做完后，再次调用main()进入SetupSelinux阶段

    int FirstStageMain(int argc, char** argv) {
        if (REBOOT_BOOTLOADER_ON_PANIC) {
            InstallRebootSignalHandlers();
        }
    
        boot_clock::time_point start_time = boot_clock::now();
    
        std::vector<std::pair<std::string, int>> errors;
    #define CHECKCALL(x) \
        if (x != 0) errors.emplace_back(#x " failed", errno);
    
        // Clear the umask.
        umask(0);            // 清除系统默认权限，保证新建目录的访问权限由mkdir设置
    
        CHECKCALL(clearenv());     // 虚拟文件挂载
        CHECKCALL(setenv("PATH", _PATH_DEFPATH, 1));
        // Get the basic filesystem setup we need put together in the initramdisk
        // on / and then we'll let the rc file figure out the rest.
        CHECKCALL(mount("tmpfs", "/dev", "tmpfs", MS_NOSUID, "mode=0755"));    // dev是设备目录，所有外部设备和虚拟设备都在该目录下，挂载一些基础文件系统
        CHECKCALL(mkdir("/dev/pts", 0755));
        CHECKCALL(mkdir("/dev/socket", 0755));
        CHECKCALL(mount("devpts", "/dev/pts", "devpts", 0, NULL));
    #define MAKE_STR(x) __STRING(x)
        CHECKCALL(mount("proc", "/proc", "proc", 0, "hidepid=2,gid=" MAKE_STR(AID_READPROC)));   // proc是存储当前系统内核运行信息的文件目录
    #undef MAKE_STR
        // Don't expose the raw commandline to unprivileged processes.
        CHECKCALL(chmod("/proc/cmdline", 0440));
        gid_t groups[] = {AID_READPROC};
        CHECKCALL(setgroups(arraysize(groups), groups));
        CHECKCALL(mount("sysfs", "/sys", "sysfs", 0, NULL));                 // sys存储了硬件设备在内核上的映射
        CHECKCALL(mount("selinuxfs", "/sys/fs/selinux", "selinuxfs", 0, NULL));
    
        CHECKCALL(mknod("/dev/kmsg", S_IFCHR | 0600, makedev(1, 11)));
    
        if constexpr (WORLD_WRITABLE_KMSG) {
            CHECKCALL(mknod("/dev/kmsg_debug", S_IFCHR | 0622, makedev(1, 11)));
        }
    
        CHECKCALL(mknod("/dev/random", S_IFCHR | 0666, makedev(1, 8)));
        CHECKCALL(mknod("/dev/urandom", S_IFCHR | 0666, makedev(1, 9)));
    
        // This is needed for log wrapper, which gets called before ueventd runs.
        CHECKCALL(mknod("/dev/ptmx", S_IFCHR | 0666, makedev(5, 2)));
        CHECKCALL(mknod("/dev/null", S_IFCHR | 0666, makedev(1, 3)));
    
        // These below mounts are done in first stage init so that first stage mount can mount
        // subdirectories of /mnt/{vendor,product}/.  Other mounts, not required by first stage mount,
        // should be done in rc files.
        // Mount staging areas for devices managed by vold
        // See storage config details at http://source.android.com/devices/storage/
        CHECKCALL(mount("tmpfs", "/mnt", "tmpfs", MS_NOEXEC | MS_NOSUID | MS_NODEV,
                        "mode=0755,uid=0,gid=1000"));
        // /mnt/vendor is used to mount vendor-specific partitions that can not be
        // part of the vendor partition, e.g. because they are mounted read-write.
        CHECKCALL(mkdir("/mnt/vendor", 0755));
        // /mnt/product is used to mount product-specific partitions that can not be
        // part of the product partition, e.g. because they are mounted read-write.
        CHECKCALL(mkdir("/mnt/product", 0755));
    
        // /apex is used to mount APEXes
        CHECKCALL(mount("tmpfs", "/apex", "tmpfs", MS_NOEXEC | MS_NOSUID | MS_NODEV,
                        "mode=0755,uid=0,gid=0"));
    
        // /debug_ramdisk is used to preserve additional files from the debug ramdisk
        CHECKCALL(mount("tmpfs", "/debug_ramdisk", "tmpfs", MS_NOEXEC | MS_NOSUID | MS_NODEV,
                        "mode=0755,uid=0,gid=0"));
    #undef CHECKCALL
    
        SetStdioToDevNull(argv);              // 关闭/stdin/stdout/stderr的fd，重定向到/dev/null
        // Now that tmpfs is mounted on /dev and we have /dev/kmsg, we can actually
        // talk to the outside world...
        InitKernelLogging(argv);            // 初始化kernel日志，输出到/dev/kmsg
    
        if (!errors.empty()) {
            for (const auto& [error_string, error_errno] : errors) {
                LOG(ERROR) << error_string << " " << strerror(error_errno);
            }
            LOG(FATAL) << "Init encountered errors starting first stage, aborting";
        }
    
        LOG(INFO) << "init first stage started!";
    
        auto old_root_dir = std::unique_ptr<DIR, decltype(&closedir)>{opendir("/"), closedir};
        if (!old_root_dir) {
            PLOG(ERROR) << "Could not opendir("/"), not freeing ramdisk";
        }
    
        struct stat old_root_info;
        if (stat("/", &old_root_info) != 0) {
            PLOG(ERROR) << "Could not stat("/"), not freeing ramdisk";
            old_root_dir.reset();
        }
    
        if (ForceNormalBoot()) {
            mkdir("/first_stage_ramdisk", 0755);
            // SwitchRoot() must be called with a mount point as the target, so we bind mount the
            // target directory to itself here.
            if (mount("/first_stage_ramdisk", "/first_stage_ramdisk", nullptr, MS_BIND, nullptr) != 0) {
                LOG(FATAL) << "Could not bind mount /first_stage_ramdisk to itself";
            }
            SwitchRoot("/first_stage_ramdisk");
        }
    
        // If this file is present, the second-stage init will use a userdebug sepolicy
        // and load adb_debug.prop to allow adb root, if the device is unlocked.
        if (access("/force_debuggable", F_OK) == 0) {
            std::error_code ec;  // to invoke the overloaded copy_file() that won't throw.
            if (!fs::copy_file("/adb_debug.prop", kDebugRamdiskProp, ec) ||
                !fs::copy_file("/userdebug_plat_sepolicy.cil", kDebugRamdiskSEPolicy, ec)) {
                LOG(ERROR) << "Failed to setup debug ramdisk";
            } else {
                // setenv for second-stage init to read above kDebugRamdisk* files.
                setenv("INIT_FORCE_DEBUGGABLE", "true", 1);
            }
        }
    
        if (!DoFirstStageMount()) {       // 获取system，vendor等重要分区信息并挂载
            LOG(FATAL) << "Failed to mount required partitions early ...";
        }
    
        struct stat new_root_info;
        if (stat("/", &new_root_info) != 0) {
            PLOG(ERROR) << "Could not stat("/"), not freeing ramdisk";
            old_root_dir.reset();
        }
    
        if (old_root_dir && old_root_info.st_dev != new_root_info.st_dev) {
            FreeRamdisk(old_root_dir.get(), old_root_info.st_dev);
        }
    
        SetInitAvbVersionInRecovery();
    
        static constexpr uint32_t kNanosecondsPerMillisecond = 1e6;
        uint64_t start_ms = start_time.time_since_epoch().count() / kNanosecondsPerMillisecond;
        setenv("INIT_STARTED_AT", std::to_string(start_ms).c_str(), 1);
    
        const char* path = "/system/bin/init";     //再次执行init，此处传入了selinux setup参数命令，进入selinux初始化阶段
        const char* args[] = {path, "selinux_setup", nullptr};
        execv(path, const_cast<char**>(args));
    
        // execv() only returns if an error happened, in which case we
        // panic and never fall through this conditional.
        PLOG(FATAL) << "execv("" << path << "") failed";
    
        return 1;
        }

#### SetupSelinux() ：

build\android\system\core\init\selinux.cpp

初始化selinux，加载SELinux规则;

(2)、配置SELinux相关log输出；

(3)、启动init第二阶段主流程

Selinux启动完后会再次携带参数调用main()进入SecondStageMain阶段

<img width="444" height="878" alt="image" src="https://github.com/user-attachments/assets/68a5c8b5-9490-4290-9427-b4e955f13730" />


    void SelinuxInitialize() {
        Timer t;
    
        LOG(INFO) << "Loading SELinux policy";
        if (!LoadPolicy()) {
            LOG(FATAL) << "Unable to load SELinux policy";
        }
    
        bool kernel_enforcing = (security_getenforce() == 1);
        bool is_enforcing = IsEnforcing();
        if (kernel_enforcing != is_enforcing) {
            if (security_setenforce(is_enforcing)) {
                PLOG(FATAL) << "security_setenforce(%s) failed" << (is_enforcing ? "true" : "false");
            }
        }
    
        if (auto result = WriteFile("/sys/fs/selinux/checkreqprot", "0"); !result) {
            LOG(FATAL) << "Unable to write to /sys/fs/selinux/checkreqprot: " << result.error();
        }
    
        // init's first stage can't set properties, so pass the time to the second stage.
        setenv("INIT_SELINUX_TOOK", std::to_string(t.duration().count()).c_str(), 1);
    }

<!---->

    int SetupSelinux(char** argv) {
        InitKernelLogging(argv);
    
        if (REBOOT_BOOTLOADER_ON_PANIC) {
            InstallRebootSignalHandlers();
        }
    
        // Set up SELinux, loading the SELinux policy.
        SelinuxSetupKernelLogging();
        SelinuxInitialize();
    
        // We're in the kernel domain and want to transition to the init domain.  File systems that
        // store SELabels in their xattrs, such as ext4 do not need an explicit restorecon here,
        // but other file systems do.  In particular, this is needed for ramdisks such as the
        // recovery image for A/B devices.
        if (selinux_android_restorecon("/system/bin/init", 0) == -1) {
            PLOG(FATAL) << "restorecon failed of /system/bin/init failed";
        }
    
        const char* path = "/system/bin/init";
        const char* args[] = {path, "second_stage", nullptr};
        execv(path, const_cast<char**>(args));
    
        // execv() only returns if an error happened, in which case we
        // panic and never return from this function.
        PLOG(FATAL) << "execv("" << path << "") failed";
    
        return 1;
    }
    
    // selinux_android_file_context_handle() takes on the order of 10+ms to run, so we want to cache
    // its value.  selinux_android_restorecon() also needs an sehandle for file context look up.  It
    // will create and store its own copy, but selinux_android_set_sehandle() can be used to provide
    // one, thus eliminating an extra call to selinux_android_file_context_handle().
    void SelabelInitialize() {
        sehandle = selinux_android_file_context_handle();
        selinux_android_set_sehandle(sehandle);
    }
    
    // A C++ wrapper around selabel_lookup() using the cached sehandle.
    // If sehandle is null, this returns success with an empty context.
    bool SelabelLookupFileContext(const std::string& key, int type, std::string* result) {
        result->clear();
    
        if (!sehandle) return true;
    
        char* context;
        if (selabel_lookup(sehandle, &context, key.c_str(), type) != 0) {
            return false;
        }
        *result = context;
        free(context);
        return true;
    }
    
    // A C++ wrapper around selabel_lookup_best_match() using the cached sehandle.
    // If sehandle is null, this returns success with an empty context.
    bool SelabelLookupFileContextBestMatch(const std::string& key,
                                           const std::vector<std::string>& aliases, int type,
                                           std::string* result) {
        result->clear();
    
        if (!sehandle) return true;
    
        std::vector<const char*> c_aliases;
        for (const auto& alias : aliases) {
            c_aliases.emplace_back(alias.c_str());
        }
        c_aliases.emplace_back(nullptr);
    
        char* context;
        if (selabel_lookup_best_match(sehandle, &context, key.c_str(), &c_aliases[0], type) != 0) {
            return false;
        }
        *result = context;
        free(context);
        return true;
    }

#### SecondStageMain()：

1.系统熟悉模块初始化

property\_init();//属性共享内存区域初始化

property\_load\_boot\_defaults(load\_debug\_prop);//加载系统属性配置文件

StartPropertyService(\&epoll);//启动属性服务

2.解析内核信息

process\_kernel\_dt();//解析DT

process\_kernel\_cmdline();//解析cmeline

export\_kernel\_boot\_props();//设置内核boot属性

3.Subcontext是Android9.0才出现的，用来进一步隔离vendor与system权限而引入的。下面代码是subcontext的初始化函数入口 ：

subcontexts = InitializeSubcontexts();

4.设置init进程和其fork()的子进程的oom\_adj。oom\_adj主要用在lowmemorykiller机制中，每一类别的进程会有其oom\_adj的范围，oom\_adj值越大表示进程越不重要，当lowmemory时，会优先kill oom\_adj高的进程

5.最后解析init.rc脚本，建立rc文件中定义的action 、service，按照脚本执行动作，进入无限循环，进行子进程实时监控

<img width="917" height="864" alt="image" src="https://github.com/user-attachments/assets/ff693467-e456-4e86-9748-83d937400c96" />


SecondStageMain()：

    int SecondStageMain(int argc, char** argv) {
        if (REBOOT_BOOTLOADER_ON_PANIC) {
            InstallRebootSignalHandlers();//设置Signal处理器
        }
    
        SetStdioToDevNull(argv);
        InitKernelLogging(argv);
        LOG(INFO) << "init second stage started!";
    
        if (DeferOverlayfsMount()) {
            Fstab fstab;
            if (ReadDefaultFstab(&fstab)) {
                fstab.erase(std::remove_if(fstab.begin(), fstab.end(),
                                           [](const auto& entry) {
                                               return !entry.fs_mgr_flags.first_stage_mount;
                                           }),
                            fstab.end());
                LOG(INFO) << "Running deferred mounting of overlayfs";
                fs_mgr_overlayfs_mount_all(&fstab);
            }
    
        }
    
        // Set init and its forked children's oom_adj.
        if (auto result = WriteFile("/proc/1/oom_score_adj", "-1000"); !result) {
            LOG(ERROR) << "Unable to write -1000 to /proc/1/oom_score_adj: " << result.error();
        }
    
        // Enable seccomp if global boot option was passed (otherwise it is enabled in zygote).
        GlobalSeccomp();
    
        // Set up a session keyring that all processes will have access to. It
        // will hold things like FBE encryption keys. No process should override
        // its session keyring.
        keyctl_get_keyring_ID(KEY_SPEC_SESSION_KEYRING, 1);
    
        // Indicate that booting is in progress to background fw loaders, etc.
        close(open("/dev/.booting", O_WRONLY | O_CREAT | O_CLOEXEC, 0000));
    
        property_init();    // 属性共享内存区域初始化
    
        // If arguments are passed both on the command line and in DT,
        // properties set in DT always have priority over the command-line ones.
        process_kernel_dt();          // 解析内核信息，解析DT 
        process_kernel_cmdline();     // 解析cmeline
    
        // Propagate the kernel variables to internal variables
        // used by init as well as the current required properties.
        export_kernel_boot_props();     // 设置内核boot属性
    
        // Make the time that init started available for bootstat to log.
        property_set("ro.boottime.init", getenv("INIT_STARTED_AT"));
        property_set("ro.boottime.init.selinux", getenv("INIT_SELINUX_TOOK"));
    
        // Set libavb version for Framework-only OTA match in Treble build.
        const char* avb_version = getenv("INIT_AVB_VERSION");
        if (avb_version) property_set("ro.boot.avb_version", avb_version);
    
        // See if need to load debug props to allow adb root, when the device is unlocked.
        const char* force_debuggable_env = getenv("INIT_FORCE_DEBUGGABLE");
        if (force_debuggable_env && AvbHandle::IsDeviceUnlocked()) {
            load_debug_prop = "true"s == force_debuggable_env;
        }
    
        // Set memcg property based on kernel cmdline argument
        bool memcg_enabled = android::base::GetBoolProperty("ro.boot.memcg",false);
        if (memcg_enabled) {
           // root memory control cgroup
           mkdir("/dev/memcg", 0755);
           chown("/dev/memcg",AID_SYSTEM,AID_SYSTEM);
           mount("none", "/dev/memcg", "cgroup", 0, "memory");
           // app mem cgroups, used by activity manager, lmkd and zygote
           mkdir("/dev/memcg/apps/",0755);
           chown("/dev/memcg/apps/",AID_SYSTEM,AID_SYSTEM);
           mkdir("/dev/memcg/system",0550);
           chown("/dev/memcg/system",AID_SYSTEM,AID_SYSTEM);
           if (auto result = WriteFile("/dev/memcg/memory.swappiness", "100"); !result) {
               LOG(ERROR) << "Unable to write 100 to /dev/memcg/memory.swappiness" << result.error();
           }
           if (auto result = WriteFile("/dev/memcg/apps/memory.swappiness", "100"); !result) {
               LOG(ERROR) << "Unable to write 100 to /dev/memcg/memory.swappiness" << result.error();
           }
           if (auto result = WriteFile("/dev/memcg/system/memory.swappiness", "100"); !result) {
               LOG(ERROR) << "Unable to write 100 to /dev/memcg/memory.swappiness" << result.error();
           }
    
        }
    
        // Clean up our environment.
        unsetenv("INIT_STARTED_AT");
        unsetenv("INIT_SELINUX_TOOK");
        unsetenv("INIT_AVB_VERSION");
        unsetenv("INIT_FORCE_DEBUGGABLE");
    
        // Now set up SELinux for second stage.
        SelinuxSetupKernelLogging();
        SelabelInitialize();
        SelinuxRestoreContext();
    
        Epoll epoll;//创建Epoll
        if (auto result = epoll.Open(); !result) {
            PLOG(FATAL) << result.error();
        }
    
        InstallSignalFdHandler(&epoll);
    
        property_load_boot_defaults(load_debug_prop);   // 加载系统属性配置文件
        UmountDebugRamdisk();
        fs_mgr_vendor_overlay_mount_all();
        export_oem_lock_status();
        StartPropertyService(&epoll);                 // 启动属性服务
        MountHandler mount_handler(&epoll);
        set_usb_controller();
    
        const BuiltinFunctionMap function_map;
        Action::set_function_map(&function_map);
    
        if (!SetupMountNamespaces()) {
            PLOG(FATAL) << "SetupMountNamespaces failed";
        }
    
        subcontexts = InitializeSubcontexts();   // sub初始化函数入口，用来进一步隔离vendor和system权限而引入的
    
        ActionManager& am = ActionManager::GetInstance();    // 解析rc脚本，建立文件中定义的action，service，按照脚本执行动作 
        ServiceList& sm = ServiceList::GetInstance();    // 获取ActionManager实例和ServiceList实例
    
        LoadBootScripts(am, sm);
    
        // Turning this on and letting the INFO logging be discarded adds 0.2s to
        // Nexus 9 boot time, so it's disabled by default.
        if (false) DumpState();
    
        // Make the GSI status available before scripts start running.
        if (android::gsi::IsGsiRunning()) {
            property_set("ro.gsid.image_running", "1");
        } else {
            property_set("ro.gsid.image_running", "0");
        }
    
        am.QueueBuiltinAction(SetupCgroupsAction, "SetupCgroups");
    
       am.QueueBuiltinAction(SetKptrRestrictAction, "SetKptrRestrict");
       am.QueueEventTrigger("early-init");
    
        // Queue an action that waits for coldboot done so we know ueventd has set up all of /dev...
        am.QueueBuiltinAction(wait_for_coldboot_done_action, "wait_for_coldboot_done");
        // ... so that we can start queuing up actions that require stuff from /dev.
        am.QueueBuiltinAction(MixHwrngIntoLinuxRngAction, "MixHwrngIntoLinuxRng");
        am.QueueBuiltinAction(SetMmapRndBitsAction, "SetMmapRndBits");
        Keychords keychords;
        am.QueueBuiltinAction(
            [&epoll, &keychords](const BuiltinArguments& args) -> Result<Success> {
                for (const auto& svc : ServiceList::GetInstance()) {
                    keychords.Register(svc->keycodes());
                }
                keychords.Start(&epoll, HandleKeychord);
                return Success();
            },
            "KeychordInit");
        am.QueueBuiltinAction(console_init_action, "console_init");
    
        // Trigger all the boot actions to get us started.
        am.QueueEventTrigger("init");
    
        // Starting the BoringSSL self test, for NIAP certification compliance.
        am.QueueBuiltinAction(StartBoringSslSelfTest, "StartBoringSslSelfTest");
    
        // Repeat mix_hwrng_into_linux_rng in case /dev/hw_random or /dev/random
        // wasn't ready immediately after wait_for_coldboot_done
        am.QueueBuiltinAction(MixHwrngIntoLinuxRngAction, "MixHwrngIntoLinuxRng");
    
        // Initialize binder before bringing up other system services
        am.QueueBuiltinAction(InitBinder, "InitBinder");
    
        // Don't mount filesystems or start core system services in charger mode.
        std::string bootmode = GetProperty("ro.bootmode", "");
        if (bootmode == "charger") {
            am.QueueEventTrigger("charger");
        } else {
            am.QueueEventTrigger("late-init");
        }
    
        // Run all property triggers based on current state of the properties.
        am.QueueBuiltinAction(queue_property_triggers_action, "queue_property_triggers");
    
        while (true) {
            // By default, sleep until something happens.
            auto epoll_timeout = std::optional<std::chrono::milliseconds>{};
    
            if (do_shutdown && !shutting_down) {
                do_shutdown = false;
                if (HandlePowerctlMessage(shutdown_command)) {
                    shutting_down = true;
                }
            }
    
            if (!(waiting_for_prop || Service::is_exec_service_running())) {
                am.ExecuteOneCommand();
            }
            if (!(waiting_for_prop || Service::is_exec_service_running())) {
                if (!shutting_down) {
                    auto next_process_action_time = HandleProcessActions();
    
                    // If there's a process that needs restarting, wake up in time for that.
                    if (next_process_action_time) {
                        epoll_timeout = std::chrono::ceil<std::chrono::milliseconds>(
                                *next_process_action_time - boot_clock::now());
                        if (*epoll_timeout < 0ms) epoll_timeout = 0ms;
                    }
                }
    
                // If there's more work to do, wake up again immediately.
                if (am.HasMoreCommands()) epoll_timeout = 0ms;
            }
    
            if (auto result = epoll.Wait(epoll_timeout); !result) {
                LOG(ERROR) << result.error();
            }
        }
    
        return 0;
    }

#### init.rc：

    on init
        sysclktz 0 //将时区设置为0
        ...
        # Start logd before any other services run to ensure we capture all of their logs.
        start logd
        # Start essential services.
        start servicemanager          // 开启服务管理
        start hwservicemanager
        start vndservicemanager

触发 late-init，会启动各种fs，Zygote、early-boot、boot等。**所以servicemanager进程比zygote启动更早。**

    # Mount filesystems and start core system services.
    on late-ini
        trigger early-fs
        trigger fs
        trigger post-fs.
        trigger late-fs
        trigger post-fs-data
        trigger load_persist_props_action
        trigger load_bpf_programs
        #触发启动zygote                   // 触发启动zygote
        trigger zygote-start
        trigger firmware_mounts_complete
        trigger early-boot
        trigger boot


​     
    on early-fs
        # Once metadata has been mounted, we'll need vold to deal with userdata checkpointing
        start vold
     
    on post-fs
        exec - system system -- /system/bin/vdc checkpoint markBootAttempt
        mount rootfs rootfs / remount bind ro nodev
     
        # Mount default storage into root namespace
        mount none /mnt/user/0 /storage bind rec
        mount none none /storage slave rec
     
        chown system cache /cache
        chmod 0770 /cache
        restorecon_recursive /cache
        mkdir /cache/recovery 0770 system cache
     
        chown root system /proc/kmsg
        chmod 0440 /proc/kmsg
     
    # It is recommended to put unnecessary data/ initialization from post-fs-data
    # to start-zygote in device's init.rc to unblock zygote start.
    on zygote-start && property:ro.crypto.state=unencrypted
        wait_for_prop odsign.verification.done 1
        # A/B update verifier that marks a successful boot.
        exec_start update_verifier_nonencrypted
        start statsd
        start netd
        start zygote
        start zygote_secondary



init是kernel启动的第一个用户空间进程(pid为1)，它在经历FirstStage、selinux_setup和SecondStage后，进入loop循环等待事件发生，比如属性事件或者子进程死亡处理。流程大致如下(正常开机模式)：

-   FirstStage 挂载一些基础文件系统和加载内核模块等

-   selinux_setup 执行selinux的初始化

-   SecondStage 挂载其他文件系统，启动属性服务，执行boot流程等，主要逻辑都在这里实现

    -   PropertyInit - StartPropertyService 初始化和启动属性服务

    -   LoadBootScripts 解析开机脚本 rc文件

    -   early-init 早期init阶段,执行启动 ueventd

    -   init init阶段，在此阶段会启动logd、servicemanager、hwservicemanager、vndservicemanager

    -   late-init 末期init

        -   early-fs 启动 vold
        -   fs 使用mount_all挂载 init.{$device}.rc 中的fstab相关分区，使用 --early 参数
        -   post-fs 创建和挂载一些目录 如 /mnt/user/0 -> /storage
        -   late-fs 使用mount_all挂载 init.{$device}.rc 中的fstab相关分区，使用 --late 参数
        -   post-fs-data 创建/data一些主要目录
        -   load_bpf_programs
        -   zygote-start 触发启动zygote 框架
        -   firmware_mounts_complete
        -   early-boot 在boot之前的一个事件
        -   boot 启动核心native服务，如 surfaceflinger、audioserver

    -   queue_property_triggers 添加property_triggers，早于early-fs 晚于late-init

        -   enable_property_trigger 晚于boot trigger添加，在其之后执行。触发使能init处理属性事件
        -   QueueAllPropertyActions 将所有属性匹配的action添加到队列

    -   进入loop循环等待事件发生并处理(主要以下几种)

        -   处理build-in action，在执行结束后被移除(oneshot)
        -   处理唤醒事件
        -   处理属性事件

        -   处理子进程死亡事件
