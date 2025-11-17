## Android开机流程-ServiceManager



我们都知道ServiceManager是在init流程中在init.rc中被拉起的，所以从init.rc看起

```shell
on init
    # Start essential services.
    start servicemanager  #启动servicemanager进程
    start hwservicemanager
    start vndservicemanager
```



有关servicemanager进程启动的细节配置被放在了 frameworks\native\cmds\servicemanager\servicemanager.rc

```shell
#此脚本文件描述了启动servicemanager进程时的一些细节
#service用于通知init进程创建名为servicemanager的进程，这个进程执行程序的路径是/system/bin/servicemanager
service servicemanager /system/bin/servicemanager
    class core animation
    #表明此进程是以system身份运行的
    user system
    group system readproc
    #说明servicemanager是系统中的关键服务，关键服务是不会退出的，若退出系统则会重启，系统重启则会重启
    #以下onrestart修饰的进程，也可以说明这些进程是依赖于servicemanager进程的
    critical
    file /dev/kmsg w
    onrestart setprop servicemanager.ready false
    onrestart restart --only-if-running apexd
    onrestart restart audioserver
    onrestart restart gatekeeperd
    onrestart class_restart --only-enabled main
    onrestart class_restart --only-enabled hal
    onrestart class_restart --only-enabled early_hal
    task_profiles ServiceCapacityLow
    shutdown critical
```

当执行到 start servicemanager 这条命令，就会运行android设备中 /system/bin/servicemanager这个可执行文件，而这个可执行程序就是servicemanager进程，他由 frameworks\native\cmds\servicemanager\main.cpp 文件编译生成的。

```shell
...
# cc_binary表示编译成一个二进制文件
cc_binary {
    name: "servicemanager", #文件名
    defaults: ["servicemanager_defaults"],
    init_rc: ["servicemanager.rc"],  #配置详情
    srcs: ["main.cpp"],   #要编译的源文件
}
 
...
```

这样我们就知道运行servicemanager这个可执行文件就是运行到了frameworks\native\cmds\servicemanager\main.cpp这个文件了。

```c++
int main(int argc, char** argv) {
    android::base::InitLogging(argv, android::base::KernelLogger);

    if (argc > 2) {
        LOG(FATAL) << "usage: " << argv[0] << " [binder driver]";
    }
    //此时要使用的binder驱动为 "/dev/binder"，同样这个路径也是android设备上的路径
    const char* driver = argc == 2 ? argv[1] : "/dev/binder";

    LOG(INFO) << "Starting sm instance on " << driver;
    //打开binder驱动文件并将此进程与binder驱动进行内存映射，ProcessState是用来保存进程状态的一个类
    sp<ProcessState> ps = ProcessState::initWithDriver(driver);//注释1
    //设置最大线程数
    ps->setThreadPoolMaxThreadCount(0);
    ps->setCallRestriction(ProcessState::CallRestriction::FATAL_IF_NOT_ONEWAY);

    IPCThreadState::self()->disableBackgroundScheduling(true);
    //实例化ServiceManager
    sp<ServiceManager> manager = sp<ServiceManager>::make(std::make_unique<Access>());
    manager->setRequestingSid(true);
     //将自身作为服务添加
    if (!manager->addService("manager", manager, false /*allowIsolated*/, IServiceManager::DUMP_FLAG_PRIORITY_DEFAULT).isOk()) {
        LOG(ERROR) << "Could not self register servicemanager";
    }
    //创建服务端Bbinder对象
    IPCThreadState::self()->setTheContextObject(manager);//注释2
    //设置称为binder驱动的context manager，称为上下文的管理者 
    ps->becomeContextManager();
    //通过Looper epoll机制处理binder事务
    sp<Looper> looper = Looper::prepare(false /*allowNonCallbacks*/);
    //Binder驱动中数据变化的监听
    BinderCallback::setupTo(looper);//注释3
    ClientCallbackCallback::setupTo(looper, manager);

#ifndef VENDORSERVICEMANAGER
    if (!SetProperty("servicemanager.ready", "true")) {
        LOG(ERROR) << "Failed to set servicemanager ready property";
    }
#endif

    while(true) {
        looper->pollAll(-1);
    }

    // should not be reached
    return EXIT_FAILURE;
}
```



先看注释1--initWithDriver

```c++
sp<ProcessState> ProcessState::initWithDriver(const char* driver)
{
    return init(driver, true /*requireDefault*/);
}

sp<ProcessState> ProcessState::init(const char *driver, bool requireDefault)
{
#ifdef BINDER_IPC_32BIT
    LOG_ALWAYS_FATAL("32-bit binder IPC is not supported for new devices starting in Android P. If "
                     "you do need to use this mode, please see b/232423610 or file an issue with "
                     "AOSP upstream as otherwise this will be removed soon.");
#endif

    if (driver == nullptr) {
        std::lock_guard<std::mutex> l(gProcessMutex);
        if (gProcess) {
            verifyNotForked(gProcess->mForked);
        }
        return gProcess;
    }

    [[clang::no_destroy]] static std::once_flag gProcessOnce;
    std::call_once(gProcessOnce, [&](){
        if (access(driver, R_OK) == -1) {
            ALOGE("Binder driver %s is unavailable. Using /dev/binder instead.", driver);
            driver = "/dev/binder";
        }

        if (0 == strcmp(driver, "/dev/vndbinder") && !isVndservicemanagerEnabled()) {
            ALOGE("vndservicemanager is not started on this device, you can save resources/threads "
                  "by not initializing ProcessState with /dev/vndbinder.");
        }

        // we must install these before instantiating the gProcess object,
        // otherwise this would race with creating it, and there could be the
        // possibility of an invalid gProcess object forked by another thread
        // before these are installed
        int ret = pthread_atfork(ProcessState::onFork, ProcessState::parentPostFork,
                                 ProcessState::childPostFork);
        LOG_ALWAYS_FATAL_IF(ret != 0, "pthread_atfork error %s", strerror(ret));

        std::lock_guard<std::mutex> l(gProcessMutex);
        gProcess = sp<ProcessState>::make(driver);
    });

    if (requireDefault) {
        // Detect if we are trying to initialize with a different driver, and
        // consider that an error. ProcessState will only be initialized once above.
        LOG_ALWAYS_FATAL_IF(gProcess->getDriverName() != driver,
                            "ProcessState was already initialized with %s,"
                            " can't initialize with %s.",
                            gProcess->getDriverName().c_str(), driver);
    }

    verifyNotForked(gProcess->mForked);
    return gProcess;
}
```



再看注释2--setTheContextObject

```c++
//IPCThreadState是线程单例
IPCThreadState* IPCThreadState::self()
{
    //不是初次调用的情况，TLS的全称为Thread Local Storage
    if (gHaveTLS.load(std::memory_order_acquire)) {
restart:
        //初次调用，生成线程私有变量key后
	    //TLS 表示线程本地存储空间，和java中的ThreadLocal是一个意思
        const pthread_key_t k = gTLS;
        IPCThreadState* st = (IPCThreadState*)pthread_getspecific(k);
        if (st) return st;
        //没有的话就实例化一个
        return new IPCThreadState;
    }

    // Racey, heuristic test for simultaneous shutdown.
    // IPCThreadState shutdown后不能再获取
    if (gShutdown.load(std::memory_order_relaxed)) {
        ALOGW("Calling IPCThreadState::self() during shutdown is dangerous, expect a crash.\n");
        return nullptr;
    }
    // 首次获取时gHaveTLS为false，会先走这里
    pthread_mutex_lock(&gTLSMutex);
    if (!gHaveTLS.load(std::memory_order_relaxed)) {
        //创建一个key，作为存放线程本地变量的key
        int key_create_value = pthread_key_create(&gTLS, threadDestructor);
        if (key_create_value != 0) {
            pthread_mutex_unlock(&gTLSMutex);
            ALOGW("IPCThreadState::self() unable to create TLS key, expect a crash: %s\n",
                    strerror(key_create_value));
            return nullptr;
        }
        //创建完毕，gHaveTLS设置为true
        gHaveTLS.store(true, std::memory_order_release);
    }
    pthread_mutex_unlock(&gTLSMutex);
    // 回到gHaveTLS为true的case
    goto restart;
}

sp<BBinder> the_context_object;

void IPCThreadState::setTheContextObject(const sp<BBinder>& obj)
{
    //赋值给一个BBinder类型的成员变量，即传进来的这个manager就是服务端的BBinder
    the_context_object = obj;
}
```

为了更好的理解ServiceManager这个类，下面是一张它的继承关系图：

![image-20251106110728457](C:\Users\Y6809\AppData\Roaming\Typora\typora-user-images\image-20251106110728457.png)



下面来到注释3--setupTo

```c++
class BinderCallback : public LooperCallback {
public:
    static sp<BinderCallback> setupTo(const sp<Looper>& looper) {
        sp<BinderCallback> cb = sp<BinderCallback>::make();

        int binder_fd = -1;
        //向binder驱动发送BC_ENTER_LOOPER事务请求，并获得binder驱动的文件描述符
        IPCThreadState::self()->setupPolling(&binder_fd);
        LOG_ALWAYS_FATAL_IF(binder_fd < 0, "Failed to setupPolling: %d", binder_fd);
        // 监听binder文件描述符
        int ret = looper->addFd(binder_fd,
                                Looper::POLL_CALLBACK,
                                Looper::EVENT_INPUT,
                                cb,
                                nullptr /*data*/);
        LOG_ALWAYS_FATAL_IF(ret != 1, "Failed to add binder FD to Looper");

        return cb;
    }
    // 当binder驱动发来消息后，就可以通过此函数接收处理了
    int handleEvent(int /* fd */, int /* events */, void* /* data */) override {
        //处理消息
        IPCThreadState::self()->handlePolledCommands();
        return 1;  // Continue receiving callbacks.
    }
};
```

servicemanager进程启动过程中，主要做了以下四件事：

1）初始化binder驱动

2）将自身以“manager” 添加到servicemanager中的map集合中

3）注册成为binder驱动的上下问管理者

1. 给Looper设置callback,进入无限循环，处理client端发来的请求

总结：

1.ServiceManager是一个独立的进程，由init进程创建，且在创建zygote进程之前被创建。

2.IBinder是什么？它是实现了AIDL接口的实体类，它实现了接口中的所有方法。