## Android-CarService启动流程



### CarService启动流程

Android作为车载主流娱乐操作系统之一，CarService是系统中除了AMS、PMS、WMS等核心服务之外最为重要的服务了，汽车相关属性控制都是通过这个服务来操控的。既然CarService和其他Android核心服务同属一个级别，那么FW层面的流程我们就直接从SystemServer开始梳理了，分析前我们先看一下CarService启动的时序，窥探一下全貌。

![carservice.png](https://p3-xtjj-sign.byteimg.com/tos-cn-i-73owjymdk6/5b35f898048543c7ad5303319218a4ac~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg6L2m6L295bqU55So54y_:q75.awebp?rk3s=f64ab15b&x-expires=1760693301&x-signature=mkWTQGP21XhFw3ZBAnAKOvEq2sk%3D) 

到这里SystemServer启动CarService服务，最终拿到vhal层IVehicle2.0对象，大致流程基本清晰了,接下来我们结合代码一起看下细节部分，从SystemServer入手：

心驰平台：android14\frameworks\base\services\java\com\android\server\SystemServer.java

```java
// com.android.server.SystemServer
private void startOtherServices(@NonNull TimingsTraceAndSlog t) {
    // ...
    // 还是先判断是否具有automotiove特性,是否具备某个硬件特性定义在文件 
    // frameworks/native/data/etc/car_core_hardware.xml中，
    //<permissions>
    // <feature name="android.hardware.type.automotive" />
    // ...
    boolean isAutomotive = mPackageManager
                .hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE);
        if (isAutomotive) {
            t.traceBegin("StartCarServiceHelperService");
            final SystemService cshs = mSystemServiceManager
                    .startService(CAR_SERVICE_HELPER_SERVICE_CLASS);
            if (cshs instanceof Dumpable) {
                mDumper.addDumpable((Dumpable) cshs);
            }
            if (cshs instanceof DevicePolicySafetyChecker) {
                dpms.setDevicePolicySafetyChecker((DevicePolicySafetyChecker) cshs);
            }
            t.traceEnd();
        }
    //...
 }
```

// com.android.internal.car.CarServiceHelperService 
// 这个类是，车辆服务的系统服务端配套服务。我们可以把他理解成一个管家，
// 用他来启动汽车相关服务并为汽车服务提供必要的API。
// 具体实现在 CarServiceHelperServiceUpdatableImpl中

```java
//android14\frameworks\opt\car\services\updatableServices\src\com\android\internal\car\updatable\CarServiceHelperServiceUpdatableImpl.java   
@Override
    public void onStart() {
        // 启动Carservice
        // CAR_SERVICE_PACKAGE = "android.car.ICar"
        // CAR_SERVICE_PACKAGE = "com.android.car"
        // 这里绑定了包名为com.android.car,action 为com.android.car的服务
        Intent intent = new Intent(CAR_SERVICE_INTERFACE).setPackage(CAR_SERVICE_PACKAGE);
        Context userContext = mContext.createContextAsUser(UserHandle.SYSTEM, /* flags= */ 0);
        if (!userContext.bindService(intent, Context.BIND_AUTO_CREATE, this,
                mCarServiceConnection)) {
            Slogf.wtf(TAG, "cannot start car service");
        }
    }
```



对应的服务配置的xml文件在/packages/services/Car/service-builtin/AndroidManifest.xml中，可见启动的这服务就是CarService,bp文件

```shell
//android14\packages\services\Car\service-builtin
android_app {
    name: "CarService",

    srcs: car_service_sources,

    resource_dirs: ["res"],

    platform_apis: true,

    // Each update should be signed by OEMs
    certificate: "platform",
    privileged: true,

    optimize: {
        proguard_flags_files: ["proguard.flags"],
        enabled: false,
    },

    jni_libs: [
        "libcarservicejni",
    ],

    libs: [
        "android.car",
        "android.car.builtin"
    ],
```

AndroidManifest.xml文件

```xml
<!-- Do not add any new service without addressing mainline issues -->
        <service android:name=".CarService"
             android:singleUser="true"
             android:exported="true">
            <intent-filter>
                <action android:name="android.car.ICar"/>
            </intent-filter>
        </service>
```



启动CarService后，我们可以看到，这里使用了一个服务代理取启动真正的服务实现者，这部分代码涉及到一个Service构造方法什么时候调用的概念，因为在CarService构造方法中，把真正需要启动的服务传递给代理服务做启动

```java
//android14\packages\services\Car\service-builtin\src\com\android\car\CarService.java
public class CarService extends ServiceProxy {

    // Binder threads are set to 31. system_server is also using 31.
    // check sMaxBinderThreads in SystemServer.java
    private  static final int MAX_BINDER_THREADS = 31;

    public CarService() {
        super(UpdatablePackageDependency.CAR_SERVICE_IMPL_CLASS);
        // Increase the number of binder threads in car service
        BinderInternal.setMaxThreads(MAX_BINDER_THREADS);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // keep it alive.
        return START_STICKY;
    }
}
```

由于平时我们继承Service时，很少写构造方法，一般都是在OnCreate()中初始化，顾这里我们这里稍微展开下Service构造函数调用时机：

```java
当调用 Context.startService() 后，最终系统会通过反射调用 Service 类的无参构造方法来创建 Service 实例,大致流程为：
1. 经过 ContextImpl.startService() → ActivityManagerService（AMS） → 进程间 Binder 调用 → 最终到 SystemServer 里的AMS.handleStartService()。
2. AMS 里会根据 ServiceRecord 记录管理所有 Service，决定是否要创建新进程或复用现有进程。AMS 发现你的 Service 所属进程已在运行（比如是同个 app 进程），就调用 ApplicationThread.scheduleCreateService()，通知目标进程的主线程去创建 Service 实例。
具体代码如下：
// android.app.ActivityThread.java
private void handleCreateService(CreateServiceData data) {
    // 1. 拿到 Service 的 ComponentName 和 className
    LoadedApk packageInfo = getPackageInfoNoCheck(data.info.applicationInfo, data.compatInfo);

    // 2. 通过 AppComponentFactory 反射创建 Service 实例
    Service service = null;
    try {
        java.lang.ClassLoader cl = packageInfo.getClassLoader();
        // 关键：调用 AppComponentFactory.instantiateService
        service = packageInfo.getAppFactory().instantiateService(cl, data.info.name, data.intent);
    }
}
// ..后续调用onCreate()
    service.attach(context, this, data.info.name, data.token, app,ActivityManager.getService());
    service.onCreate();
}

// android.app.AppComponentFactory.java
public @NonNull Service instantiateService(@NonNull ClassLoader cl,
@NonNull String className, @Nullable Intent intent) {
    // 看到了我们熟悉的newInstance了吧，这里就调用了无参的构造函数了，
    return (Service) cl.loadClass(className).newInstance();
}

```

好，在了解清楚构造方法调用时机后，我们接着看父类ServiceProxy的代码实现：

```java
 @Override
public void onCreate() {
    // 负责完成mRealService的初始化
    init();
    mRealService.onCreate();
}

private void init() {
        mUpdatablePackageContext = UpdatablePackageContext.create(this);
        try {
            // 使用ClassLoader加载器加载 CarServiceImpl类
            mRealServiceClass = mUpdatablePackageContext.getClassLoader().loadClass(
                    mRealServiceClassName);
            // Use default constructor always
            Constructor constructor = mRealServiceClass.getConstructor();
            // 初始化对象 这里把对象转换成ProxiedService，CarServiceImpl是ProxiedService的子类 汽车服务的
            mRealService = (ProxiedService) constructor.newInstance();
            mRealService.doAttachBaseContext(mUpdatablePackageContext);
            mRealService.setBuiltinPackageContext(this);
        } catch (Exception e) {
            throw new RuntimeException("Cannot load class:" + mRealServiceClassName, e);
        }
    }
```



这里我们应该思考一个问题：为什么Google在初始化服务的时候，需要走Proxy服务，而不是直接启动对应的服务？我觉得有以下考量：

1. **解耦合**：使用服务代理可以将服务的实现与其使用者解耦。这样，当服务的实现方式发生变化时，调用者不需要进行大量修改，只需通过代理进行交互即可。比如上面的两个代理服务都有一个别的实现。CarPerUserServiceImpl extends ProxiedService {}和public class CarPerUserService extends ServiceProxy {} 这样的用户切换时候只需要切换代理服务中的mRealService 变量就行了，实际实现不需要关注。
2. **灵活性**： 通过代理模式，可以在运行时动态地替换服务的实现，这为测试、调试和扩展提供了灵活性。例如，可以在开发阶段使用模拟服务，而在生产环境中使用真实服务。比如：模拟器车控服务和真实车控服务。

接下来，我们看下CarServiceImpl这个真正的CarServie服务中做了些什么事情：

```java
//android14\packages\services\Car\service\src\com\android\car\CarServiceImpl.java
@Override
    public void onCreate() {
        LimitedTimingsTraceLog initTiming = new LimitedTimingsTraceLog(CAR_SERVICE_INIT_TIMING_TAG,
                TraceHelper.TRACE_TAG_CAR_SERVICE, CAR_SERVICE_INIT_TIMING_MIN_DURATION_MS);
        initTiming.traceBegin("CarService.onCreate");

        initTiming.traceBegin("getVehicle");
        // 初始化vhal对象，获取vhal层客户端对象IVehicle，后续应用层调用get/set方法时就使用此对象和vhal层交互
        mVehicle = VehicleStub.newVehicleStub();
        initTiming.traceEnd(); // "getVehicle"

        EventLogHelper.writeCarServiceCreate(/* hasVhal= */ mVehicle.isValid());

        mVehicleInterfaceName = mVehicle.getInterfaceDescriptor();

        Slogf.i(CarLog.TAG_SERVICE, "Connected to " + mVehicleInterfaceName);
        EventLogHelper.writeCarServiceConnected(mVehicleInterfaceName);

        mICarImpl = new ICarImpl(this,
                getBuiltinPackageContext(),
                mVehicle,
                SystemInterface.Builder.defaultSystemInterface(this).build(),
                mVehicleInterfaceName);
        // ICarImpl里面做了很多车控服务的初始化        
        mICarImpl.init();
        // aidl 死亡监听
        mVehicle.linkToDeath(mVehicleDeathRecipient);
       // 到这里，尘埃落定，看到了熟悉的addService了，后续应用层获取Car对象就是通过这个"car_service" 枚举和获取AMS、PMS等一个流程了
        ServiceManagerHelper.addService("car_service", mICarImpl);
        SystemPropertiesHelper.set("boot.car_service_created", "1");

        super.onCreate();

        initTiming.traceEnd(); // "CarService.onCreate"
    }

// com.android.car.CarPropertyService
@Override
public void init() {
    synchronized (mLock) {
        // 本地变量读取PropertyId对应的权限配置，便于后续应用层请求时时候，判断PropertyId合法性和权限问题
        mPropertyIdToCarPropertyConfig = mPropertyHalService.getPropertyList();
        mPropToPermission = mPropertyHalService.getPermissionsForAllProperties();
    }
}
```



```java
//\android14\packages\services\Car\service\src\com\android\car\ICarImpl.java
// ICarImpl的构造方法
ICarImpl(...) {  
    // ...
    // 初始化各种车辆控制服务，我们窥一斑，知全貌吧，主要看下CarPropertyService的初始化
    mCarPropertyService = constructWithTrace(
            t, CarPropertyService.class,
            () -> new CarPropertyService(serviceContext, mHal.getPropertyHal()), allServices);
   // ...
  // 创建VehicleHal对象 在VehicleHal类中，我们初始化了很多和hal层打交道的服务，且提供了对应服务的propertyID和权限的定义，后面我们接着分析下
  mHal = constructWithTrace(t, VehicleHal.class,
            () -> new VehicleHal(serviceContext, vehicle), allServices);
}
```

```java
//\android14\packages\services\Car\service\src\com\android\car\CarPropertyService.java
@Override
    public void init() {
        synchronized (mLock) {
            // Cache the configs list and permissions to avoid subsequent binder calls
            // 本地变量读取PropertyId对应的权限配置，便于后续应用层请求时时候，判断PropertyId合法性和权限问题
            mPropertyIdToCarPropertyConfig = mPropertyHalService.getPropertyList();
            mPropToPermission = mPropertyHalService.getPermissionsForAllProperties();
            if (DBG) {
                Slogf.d(TAG, "cache CarPropertyConfigs " + mPropertyIdToCarPropertyConfig.size());
            }
        }
        mPropertyHalService.setPropertyHalListener(this);
    }
```



VehicleStub里主要初始化hal层服务IVehicle对象，具体代码如下：

```java
//\android14\packages\services\Car\service\src\com\android\car\VehicleStub.java
public static VehicleStub newVehicleStub() throws IllegalStateException {
    // 从这里可以看出，Android14中Google建议使用AIDL来和hal层建立通信了
    // 后续我们分别看下这两个接口的获取流程
        VehicleStub stub = new AidlVehicleStub();
        if (stub.isValid()) {
            if ((BuildHelper.isUserDebugBuild() || BuildHelper.isEngBuild())
                    && FakeVehicleStub.doesEnableFileExist()) {
                try {
                    return new FakeVehicleStub(stub);
                } catch (Exception e) {
                    Slogf.e(CarLog.TAG_SERVICE, e, "Failed to create FakeVehicleStub. "
                            + "Fallback to using real VehicleStub.");
                }
            }
            return stub;
        }

        Slogf.i(CarLog.TAG_SERVICE, "No AIDL vehicle HAL found, fall back to HIDL version");
 // 但是同样保留了HIDL的代码，也就是说，供应商还可以继续使用Hidl提供与硬件交互的接口
        stub = new HidlVehicleStub();

        if (!stub.isValid()) {
            throw new IllegalStateException("Vehicle HAL service is not available.");
        }

        return stub;
    }
```

hal层AIDL接口获取流程如下：

```java
//android14\packages\services\Car\service\src\com\android\car\AidlVehicleStub.java
AidlVehicleStub() {
    this(getAidlVehicle());
}

@Nullable
    private static IVehicle getAidlVehicle() {
        //private static final String AIDL_VHAL_SERVICE =
    //      "android.hardware.automotive.vehicle.IVehicle/default";
        try {
            // 通过我们熟知的 ServiceManager 获取对应的服务，相关服务在系统启动时，由init.rc文件申明启动，并注册在 ServiceManager中。
            return IVehicle.Stub.asInterface(
                    ServiceManagerHelper.waitForDeclaredService(AIDL_VHAL_SERVICE));
        } catch (RuntimeException e) {
            Slogf.w(TAG, "Failed to get \"" + AIDL_VHAL_SERVICE + "\" service", e);
        }
        return null;
    }
```

hal层HIDL接口获取流程如下：

```java
// android14\packages\services\Car\service\src\com\android\car\AidlVehicleStub.java\HidlVehicleStub.java
HidlVehicleStub() {
    // 在构造方法中，初始化hal层服务
    this(getHidlVehicle());
}

@Nullable
    private static IVehicle getHidlVehicle() {
        String instanceName = SystemProperties.get("ro.vehicle.hal", "default");

        try {
            return IVehicle.getService(instanceName);
        } catch (RemoteException e) {
            Slogf.e(TAG, e, "Failed to get IVehicle/" + instanceName + " service");
        } catch (NoSuchElementException e) {
            Slogf.e(TAG, "IVehicle/" + instanceName + " service not registered yet");
        }
        return null;
    }

@Deprecated
public static IVehicle getService(String serviceName) throws android.os.RemoteException {
    return IVehicle.asInterface(android.os.HwBinder.getService("android.hardware.automotive.vehicle@2.0::IVehicle", serviceName));
}
```



我们单独看下VehicleHal创建之后做了哪些事情，有助于后面我们set流程的理解：

```java
//\android14\packages\services\Car\service\src\com\android\car\hal\VehicleHal.java
VehicleHal(Context context,
            PowerHalService powerHal,
            PropertyHalService propertyHal,
            InputHalService inputHal,
            VmsHalService vmsHal,
            UserHalService userHal,
            DiagnosticHalService diagnosticHal,
            ClusterHalService clusterHalService,
            TimeHalService timeHalService,
            HandlerThread handlerThread,
            VehicleStub vehicle) {
        // Must be initialized before HalService so that HalService could use this.
      // ...     
      // 其他的我们暂不看了，窥一斑，这里我们初始化了PropertyHalService 
        mPropertyHal = propertyHal != null ? propertyHal : new PropertyHalService(this);
      // ...
}


public class PropertyHalService extends HalServiceBase {
    // 类初始化时候，我们可以看到PropertyHalServiceIds初始化了一个对应的变量PropertyHalServiceIds
    private final PropertyHalServiceIds mPropertyHalServiceIds = new PropertyHalServiceIds();
}
public class PropertyHalServiceIds {
  public PropertyHalServiceIds() {
        // Add propertyId and read/write permissions
        // Cabin Properties
        // 这里定义了相关propertyID和对应的get/set权限 在后续的get/set流程中会设计到权限的校验。
        mHalPropIdToPermissions.put(VehicleProperty.DOOR_POS, new Pair<>(
                Car.PERMISSION_CONTROL_CAR_DOORS,
                Car.PERMISSION_CONTROL_CAR_DOORS));
        mHalPropIdToPermissions.put(VehicleProperty.DOOR_MOVE, new Pair<>(
                Car.PERMISSION_CONTROL_CAR_DOORS,
                Car.PERMISSION_CONTROL_CAR_DOORS));
        // ... 
    }
}
```



### HAL Vehicle服务启动流程

系统启动相关的服务时，一般是从init进程启动开始的，init进程扫描各个服务对应的rc文件，获取rc文件对应的配置服务来启动对应的服务，那么对于hal层的Vehicle服务来说，我们先看下对应的rc文件:

```java
// android14/hardware/interfaces/automotive/vehicle/aidl/impl/vhal/vhal-default-service.rc
// 启动一个名字为：vendor.vehicle-hal-default 的服务
// 可执行文件路径为： /vendor/bin/hw/android.hardware.automotive.vehicle@V1-default-service

service vendor.vehicle-hal-default /vendor/bin/hw/android.hardware.automotive.vehicle@V1-default-service
    class early_hal
    user vehicle_network  
    group system inet

// class：指定服务所属的类别。
// 会在系统启动的较早阶段被初始化，先于普通 HAL 服务（如hal类）。这类服务通常对系统启动流程至关重要。
// user vehicle_network：指定服务运行的用户身份为vehicle_network。这是一个特殊用户，通常具有访问车辆网络（如 CAN 总线）的权限。
// group system inet：指定服务所属的用户组为system和inet,主要和权限相关。
// system组：允许访问系统级资源和 API。
// inet组：允许进行网络通信（如 socket 操作）。

```

接下来我们得找到 android.hardware.automotive.vehicle@V1-default-service 这个可执行文件是由谁编译出来的，才能找到VehicleService的主入口

```shell
// 路径： android14/hardware/interfaces/automotive/vehicle/aidl/impl/vhal/Android.bp
// ...
cc_binary {
    name: "android.hardware.automotive.vehicle@V1-default-service",
    vendor: true,
    // ... 
    init_rc: ["vhal-default-service.rc"],  // 建立关联的init.rc关系
    relative_install_path: "hw",   // 路径
    srcs: ["src/VehicleService.cpp"], // 源文件
    // ... 
}
```

这样的我们就跟踪到对应源文件了，看下VehicleService.cpp里面的main做了些什么：

```c++
// android14/hardware/interfaces/automotive/vehicle/aidl/impl/vhal/src/VehicleService.cpp
// 程序主入口
int main(int /* argc */, char* /* argv */[]) {
    // 创建一个最多4个线程的线程池，后续处理应用层binder请求
    ALOGI("Starting thread pool...");
    if (!ABinderProcess_setThreadPoolMaxThreadCount(4)) {
        ALOGE("%s", "failed to set thread pool max thread count");
        return 1;
    }
    // 启动线程池
    ABinderProcess_startThreadPool();
    
    // 初始化 FakeVehicleHardware 模拟车辆硬件的实现类，
    // 在真实的环境中，需要替换为真实的通信环境 CAN，以太网、LIN等
    std::unique_ptr<FakeVehicleHardware> hardware = std::make_unique<FakeVehicleHardware>();
    // VehicleHal 默认的服务实现端  
    // 这里的DefaultVehicleHal类定义了和上层应用交互的一套范式接口，
    // 模拟器或者厂商正常情况下都把它作为和上层通信的桥接接口
    std::shared_ptr<DefaultVehicleHal> vhal =
            ::ndk::SharedRefBase::make<DefaultVehicleHal>(std::move(hardware));
    
    // 添加服务到ServiceManager中，上层通过这个服务明获取对应的Vehicle服务 的Binder对象
    ALOGI("Registering as service...");
    binder_exception_t err = AServiceManager_addService(
            vhal->asBinder().get(), "android.hardware.automotive.vehicle.IVehicle/default");
    if (err != EX_NONE) {
        ALOGE("failed to register android.hardware.automotive.vehicle service, exception: %d", err);
        return 1;
    }

    ALOGI("Vehicle Service Ready");

    ABinderProcess_joinThreadPool();

    ALOGI("Vehicle Service Exiting");
    return 0;
}
```

到此，把服务添加到ServiceManager后,就和FW的代码就呼应上了，FW层获取的车控服务的名称就是：android.hardware.automotive.vehicle.IVehicle/default ，拿到服务后，我们接下来就看下设置车控属性的流程，当上层应用调用set车控属性方法时，对应到的服务端就是VehicleService，具体的set方法内容如下：

```java
StatusCode DefaultVehicleHal::set(const VehiclePropValue& propValue) {
    // .. 省去一些校验的判断代码
    // 实现一般分为:谷歌模拟器或者根据实车开发了
    // Send the value to the vehicle server, the server will talk to the (real or emulated) car
    return mVehicleClient->setProperty(propValue, /*updateStatus=*/false);
}
```

流程到这里，相关的服务启动和set就算是完成了，剩下的就是OEM厂商根据自己的硬件功能去定义相关的IVehicleClient实现。





### 车辆属性set流程

应用层想要set一个车辆属性，首先需要获取Car对象，所以，我们就从获取Car对象向下分析整个流程，由于get和set流程差不多，我们以set流程为例：

```java
//android.car.Car
public static Car createCar(@NonNull Context context,
            @Nullable Handler handler, long waitTimeoutMs,
            @NonNull CarServiceLifecycleListener statusChangeListener) {
        // 根据上面CarService启动的流程时机，它的启动实际是晚于系统的一些其他服务的，如果在系统的其他服务中过早获取车控信息，那么其实服务未启动，所以这里得循环重试获取
        // ...省略相关代码
        while (true) {
            // 如果调用处早于CarService的启动时机，这里获取不到服务
            service = ServiceManagerHelper.getService(CAR_SERVICE_BINDER_SERVICE_NAME);
            if (car == null) {
                     // 创建Car对象客户端： 实际服务端为ICarImpl
                car = new Car(context, ICar.Stub.asInterface(service), null, statusChangeListener,
                        handler);
            }
            if (service != null) {
                if (!started) {
                   // 这里bind一下服务端，获取服务端对象记录在客户端本地变量中，然后返回给上层应用和后续方便获取对应的CarxxxService服务
                    car.startCarService();
                    return car;
                }
                // service available after starting.
                break;
            }
            //如果在CarService还未启动，这里再次主动启动一下，进入到下次循环后，上面的service获取就不为空了
            if (!started) {
                car.startCarService();
                started = true;
            }
         // ...省略相关代码
        }
        return car;
    }
```

到这里应用层就能获取到Car对象了，由于CarService里面注册了很多车载类相关服务，例如：CABIN_SERVICE、HVAC_SERVICE等，但是这些服务在14（可能更早的版本就过期了，感兴趣的可以往前面的版本看下）中已经标识过期了，google做了一个归类，使用PROPERTY_SERVICE一个服务就行，顾我们想要设置某个车辆属性，先获取到对应服务的客户端，以PROPERTY_SERVICE服务为例：

```java
 // 获取PropertyManager 服务
 val propertyManager = car.getCarManager(Car.PROPERTY_SERVICE)
 public Object getCarManager(String serviceName) {
        CarManagerBase manager;
        synchronized (mLock) {
            // ...取本地map缓存
            manager = mServiceMap.get(serviceName);
            if (manager == null) {
                try {
                  // 获取CarService启动时注册的服务，如果没有在系统注册，返回null
                    IBinder binder = mService.getCarService(serviceName);
                    if (binder == null) {
                        Log.w(TAG_CAR, "getCarManager could not get binder for service:"
                                + serviceName);
                        return null;
                    }
                    // 记录在本地map中
                    manager = createCarManagerLocked(serviceName, binder);
                    //...
                    mServiceMap.put(serviceName, manager);
                } catch (RemoteException e) {
                    handleRemoteExceptionFromCarService(e);
                }
            }
        }
        return manager;
}
```

得到客户端PropertyManager后调用manager.setProperty()设置车辆属性，相关系统支持的propertyId定义在VehiclePropertyIds类中，当然Vender厂商也可以自定义

```java
//android.car.hardware.property.CarPropertyManager
public <E> void setProperty(@NonNull Class<E> clazz, int propertyId, int areaId,
            @NonNull E val) {
         // 校验ID是否定义：系统或者厂商
        assertPropertyIdIsSupported(propertyId);
        try {
            runSyncOperation(() -> {
            　　//  调用服务端CarPropertyService.setProperty()
                mService.setProperty(new CarPropertyValue<>(propertyId, areaId, val),
                        mCarPropertyEventToService);
                return null;
            });
     } 
}
    
// com.android.car.CarPropertyService
public void setProperty(CarPropertyValue carPropertyValue, ICarPropertyEventListener iCarPropertyEventListener)  {
    // 这里做了一个同时调用限制，最大为16，如果超过，会抛出异常ServiceSpecificException
    // 验证请求参数合法性，包括权限等问题
    validateSetParameters(carPropertyValue);
    this.runSyncOperationCheckLimit(() -> {
        this.mPropertyHalService.setProperty(carPropertyValue);
        return null;
});

private void validateSetParameters(CarPropertyValue<?> carPropertyValue) {
    requireNonNull(carPropertyValue);
    // 在上面的初始化流程中我们分析了mPropertyHalService会加载相关propertyId对应的权限，这里有用到对应的权限检测。
    String writePermission = mPropertyHalService.getWritePermission(propertyId);
    if (writePermission == null) {
    throw new SecurityException(
            "Platform does not have permission to write value for property ID: "
                    + VehiclePropertyIds.toString(propertyId));
    }
}
```

在权限校验通过后，我们继续看下接下来的流程：

```java
// com.android.car.hal.PropertyHalService
// 调用 PropertyHalService.setProperty()
public void setProperty(CarPropertyValue carPropertyValue)
            throws IllegalArgumentException, ServiceSpecificException {
       
       synchronized (mLock) {
            valueToSet = carPropertyValueToHalPropValueLocked(carPropertyValue);
       }
        // 调用 VehicleHal.set  而我们的VehicleHal  持有mVehicleStub对象
        mVehicleHal.set(valueToSet);
}
        
// com.android.car.hal.VehicleHal
// 调用set函数
public void set(HalPropValue propValue) throws IllegalArgumentException, ServiceSpecificException {
        setValueWithRetry(propValue);
}
    
private void setValueWithRetry(HalPropValue value)  {
      // 这里调用了mVehicleStub的set方法
      mVehicleStub.set(requestValue);
}

// com.android.car.HidlVehicleStub 
// HidlVehicleStub是VehicleStub的子类，还记得我们上面分析的启动流程吧，HidlVehicleStub 持有的服务端对象为vhal层android.hardware.automotive.vehicle@2.0::IVehicle 的服务
@Override
public void set(HalPropValue propValue) throws RemoteException {
    // 把传递过来的请求数据封装成 hal层数据结构，调用 Hal层接口把数据传递给hal层
    VehiclePropValue hidlPropValue = (VehiclePropValue) propValue.toVehiclePropValue();
     // 到这里FW的整个set流程就梳理完了，后面我们在梳理vhal层set流程          int status = mHidlVehicle.set(hidlPropValue);
     // ...
 }
```

get的获取流程和set差不多，这里就不做过多梳理了，参考上面set的调用关系即可,到这里我们就基本了解了CarService的启动流程和车控属性的set流程及其相关权限校验流程

