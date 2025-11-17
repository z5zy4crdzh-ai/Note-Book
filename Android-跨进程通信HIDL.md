## Android-跨进程通信HIDL

概述

![image-20251024161803530](C:\Users\Y6809\AppData\Roaming\Typora\typora-user-images\image-20251024161803530.png)

1. broadcastradio hal2 的 Android 源码位于 hardware/interfaces/broadcastradio 目录下
2. hal 进程作为服务端，调用 open/mmap/ioctol 系统接口使用 Binder IPC ，向 HIDL Service Manager 注册服务，frameworks 会在应用软件调用相关接口时去 HIDL 的 ServiceManager 找 hal 层的服务，如果找到，则顺利调用到 hal 层，否则，报错。
3. hal 层进程注册到 hwbinder 过程很复杂，这里只去除了如何向 Hwbinder 注册，以及 Binder IPC 通信过程，只专注于 hal 层和 frameworks 之间接口调用，后续会继续追踪 hal 层的服务句柄到底是怎么传递到 HIDL 服务手里的。

一、拉起 hal 进程

1. init 进程负责拉起 hal 进程

```c++
// system/core/init/init.cpp
static void LoadBootScripts(ActionManager& action_manager, ServiceList& service_list) {
    Parser parser = CreateParser(action_manager, service_list);

    std::string bootscript = GetProperty("ro.boot.init_rc", "");
    if (bootscript.empty()) {
        parser.ParseConfig("/init.rc");
        if (!parser.ParseConfig("/system/etc/init")) {
            late_import_paths.emplace_back("/system/etc/init");
        }
        ...

        // 会将 /vendor/etc/init 文件夹所有 rc 文件都拉来
        if (!parser.ParseConfig("/vendor/etc/init")) {
            late_import_paths.emplace_back("/vendor/etc/init");
        }
    } else {
        parser.ParseConfig(bootscript);
    }
}
```

2.broadcastradiohal 的 rc 文件

```xml
// hardware/interfaces/broadcastradio/2.0/default/android.hardware.broadcastradio@2.0-service.rc
// 该文件会在编译后拷贝到 /vendor/etc/init/ 目录下
service broadcastradio-hal2 /vendor/bin/hw/android.hardware.broadcastradio@2.0-service
    class hal
    user audioserver
    group audio
```



二、hal 进程启动

1. hal 注册服务

```c++
// hardware/interfaces/broadcastradio/2.0/default/service.cpp
int main(int /* argc */, char** /* argv */) {

    BroadcastRadio broadcastRadio(gAmFmRadio);

    // 向 HidlService 注册 broadcastRadio 的服务
    auto status = broadcastRadio.registerAsService();
    CHECK_EQ(status, android::OK) << "Failed to register Broadcast Radio HAL implementation";

    return 1;  // joinRpcThreadpool shouldn't exit
}
```

2.注册接口的配置文件

```xml
// manifest.xml 注册配置文件
<hal format="hidl">
    <name>android.hardware.broadcastradio</name>
    <transport>hwbinder</transport>
    <version>2.0</version>
    <interface>
        <name>IBroadcastRadio</name>
        <instance>default</instance>
    </interface>
</hal>
```



- 该文件可以在 device 目录下和其他 hal 层接口一起设置，也可以在 hal 源码目录下单独设置，如果是后者，则需要在 Android.bp 文件中指明注册的配置文件。
- 注册的服务名为 `android.hardware.broadcastradio@2.0::IBroadcastRadio`

1. hal 层服务器创建
   在 Android hal 中，hardware/interfaces/broadcastradio/2.0/default/ 目录下都是接口，虽然说具体开发确实也是实现这个文件夹下的文件，但是实际上，会被 Android 使用 hidl-gen 工具生成最终的 hal 层服务器和客户端，比如在 `auto status = broadcastRadio.registerAsService();` 注册服务代码就在生成的 HIDL 服务器代码中

```c++
// out/soong/.intermediates/hardware/interfaces/broadcastradio/2.0/android.hardware.broadcastradio@2.0_genc++/gen/android/hardware/broadcastradio/2.0/BroadcastRadioAll.cpp
::android::status_t IBroadcastRadio::registerAsService(const std::string &serviceName) {
    ::android::hardware::details::onRegistration("android.hardware.broadcastradio@2.0", "IBroadcastRadio", serviceName);

    const ::android::sp<::android::hidl::manager::V1_0::IServiceManager> sm
            = ::android::hardware::defaultServiceManager();
    if (sm == nullptr) {
        return ::android::INVALID_OPERATION;
    }
    ::android::hardware::Return<bool> ret = sm->add(serviceName.c_str(), this);
    return ret.isOk() && ret ? ::android::OK : ::android::UNKNOWN_ERROR;
}
```

1. HIDL broadcastradio 服务进程向 HIDL ServiceManager 注册服务

   ```c++
   // 该 broadcastradio 的引用和唯一标识名保存位置
   // system/hwservicemanager/ServiceManager.h
   struct ServiceManager : public IServiceManager, hidl_death_recipient {
       ...
       Return<bool> add(const hidl_string& name,
                        const sp<IBase>& service) override;
       std::map<
           std::string, // package::interface e.x. "android.hidl.manager@1.0::IServiceManager"
           PackageInterfaceMap
       > mServiceMap; 
   }
   // ServiceManager.cpp
   Return<bool> ServiceManager::add(const hidl_string& name, const sp<IBase>& service) {
       ...
       const HidlService *hidlService = ifaceMap.lookup(name);
       if (hidlService == nullptr) {
           ifaceMap.insertService(
               std::make_unique<HidlService>(fqName, name, service, callingContext.pid));
       } else {
           hidlService->setService(service, callingContext.pid);
       }
   }
   ```

   

三、frameworks 层调用 hal 层服务

1. 查看 HIDL 服务器是否有 hal 层进程接口

```java
// frameworks/base/services/core/java/com/android/server/broadcastradio/hal2/BroadcastRadioService.java
    private static @NonNull List<String> listByInterface(@NonNull String fqName) {
        try {
            IServiceManager manager = IServiceManager.getService();
            ..
            List<String> list = manager.listByInterface(fqName);
            return list;
        } catch (RemoteException ex) {
            ...
        }
    }
```

2.RadioModule 模块加载 hal 层服务接口，即获取 hal 进程对应的 broadcastradio hal 服务的引用

```java
private RadioModule(@NonNull IBroadcastRadio service,
        @NonNull RadioManager.ModuleProperties properties) {
    mProperties = Objects.requireNonNull(properties);
    mService = Objects.requireNonNull(service);
}
public static @Nullable RadioModule tryLoadingModule(int idx, @NonNull String fqName) {
    ...
    return new RadioModule(service, prop);
}
```

3.frameworks 打开与 hal 层的会话

```java
public @NonNull TunerSession openSession(@NonNull android.hardware.radio.ITunerCallback userCb) throws RemoteException {
    ...
    synchronized (mService) {
        mService.openSession(cb, (result, session) -> {
            hwSession.value = session;
            halResult.value = result;
        });
    }
    ...
}
```


