## Android-系统属性

init 进程在启动会去加载后缀为 .prop 的属性文件， 将属性文件中的属性加载到共享内存中， 这样系统就有了默认的一些属性。

属性文件都在哪里呢？

属性文件的后缀绝大部分都是 prop，我们可以在 Android 设备下搜索：

```sh
find . -name "*.prop"

/default.prop
/data/local.prop
/system/build.prop
/system/product/build.prop
/vendor/build.prop
/vendor/odm/etc/build.prop
/vendor/default.prop
```



属性的分类：

- 一般属性：普通的 key-value 对，没有其他功能，系统启动后，如果修改了某个属性值(仅修改了内存中的值，未写入到文件)，再重启系统，修改的值不会被保存下来，读取到的仍是修改前的值
- 特殊属性
  - 属性名称以 `ro` 开头，那么这个属性被视为只读属性。一旦设置，属性值不能改变。
  - `net` 开头的属性，顾名思义，就是与网络相关的属性，`net` 属性中有一个特殊的属性：`net.change`，它记录了每一次最新设置和更新的 `net` 属性，也就是每次设置和更新 `net`,属性时则会自动的更新 `net.change` 属性，`net.change` 属性的 value 就是这个被设置或者更新的 `net` 属性的 name。例如我们更新了属性 `net.bt.name` 的值，由于 `net` 有属性发生了变化，那么属性服务就会自动更新 `net.change`，将其值设置为 `net.bt.name`。
  - 以 `persist` 为开头的属性值，当在系统中通过 setprop 命令设置这个属性时，就会在 `/data/property/` 目录下会保存一个副本。这样在系统重启后，按照加载流程这些 `persist` 属性的值就不会消失了。
  - 属性 `ctrl.start` 和 `ctrl.stop` 是用来启动和停止服务。这里的服务是指定义在 rc 后缀文件中的服务。当我们向 `ctrl.start` 属性写入一个值时，属性服务将使用该属性值作为服务名找到该服务，启动该服务。这项服务的启动结果将会放入 `init.svc.<服务名>` 属性中，可以通过查询这个属性值，以确定服务是否已经启动。



系统属性架构设计：

![在这里插入图片描述](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/955dbf795eb747b19e9b6dfd0a7f5792~tplv-k3u1fbpfcp-jj-mark:3024:0:0:0:q75.awebp#?w=519&h=298&s=16174&e=png&a=1&b=81c783)



### Set prop流程

SystemProperties提供了setprop和多种返回数据类型的getprop，采用键值对(key-value)的数据格式进行操作，具体如下：

```java
\android14\frameworks\base\core\java\android\os\SystemProperties.java
public class SystemProperties { 
...
   @UnsupportedAppUsage
   public static final int PROP_NAME_MAX = Integer.MAX_VALUE;//自android 8开始，取消对属性名长度限制
   public static final int PROP_VALUE_MAX = 91;
   ...
   public static String get(@NonNull String key)
   public static String get(@NonNull String key, @Nullable String def)
   public static int getInt(@NonNull String key, int def)
   public static long getLong(@NonNull String key, long def)
   public static boolean getBoolean(@NonNull String key, boolean def)
   public static void set(@NonNull String key, @Nullable String val)
   public static void addChangeCallback(@NonNull Runnable callback) 
...
  //获取属性key的值，如果没有该属性则返回默认值def
   public static String get(@NonNull String key, @Nullable String def) {
       if (TRACK_KEY_ACCESS) onKeyAccess(key);
       return native_get(key, def);
   }
...
   //设置属性key的值为val，其不可为空、不能是"ro."开头的只读属性
   //长度不能超过PROP_VALUE_MAX(91)
   public static void set(@NonNull String key, @Nullable String val) {
       if (val != null && !val.startsWith("ro.") && val.length() > PROP_VALUE_MAX) {
           throw new IllegalArgumentException("value of system property '" + key
                   + "' is longer than " + PROP_VALUE_MAX + " characters: " + val);
       }
       if (TRACK_KEY_ACCESS) onKeyAccess(key);
       native_set(key, val);
   }
}
```



通过JNI上述 native_set()和native_get()走到android_os_SystemProperties.cpp

```c++
\android14\frameworks\base\core\jni\android_os_SystemProperties.cpp
void SystemProperties_set(JNIEnv *env, jobject clazz, jstring keyJ,
                          jstring valJ)
{
    ScopedUtfChars key(env, keyJ);
    if (!key.c_str()) {
        return;
    }
    std::optional<ScopedUtfChars> value;
    if (valJ != nullptr) {
        value.emplace(env, valJ);
        if (!value->c_str()) {
            return;
        }
    }
    bool success;
#if defined(__BIONIC__)
    success = !__system_property_set(key.c_str(), value ? value->c_str() : "");
#else
    success = android::base::SetProperty(key.c_str(), value ? value->c_str() : "");
#endif
    if (!success) {
        jniThrowException(env, "java/lang/RuntimeException",
                          "failed to set system property (check logcat for reason)");
    }
}
```





android::base::SetProperty 跟着调用关系，接着进入properties.cpp：

```c++
\android14\system\libbase\properties.cpp
std::string GetProperty(const std::string& key, const std::string& default_value) {
  std::string property_value;
#if defined(__BIONIC__)
  const prop_info* pi = __system_property_find(key.c_str());
  if (pi == nullptr) return default_value;

  __system_property_read_callback(pi,
                                  [](void* cookie, const char*, const char* value, unsigned) {
                                    auto property_value = reinterpret_cast<std::string*>(cookie);
                                    *property_value = value;
                                  },
                                  &property_value);
#else
  // TODO: implement host __system_property_find()/__system_property_read_callback()?
  auto it = g_properties.find(key);
  if (it == g_properties.end()) return default_value;
  property_value = it->second;
#endif
  // If the property exists but is empty, also return the default value.
  // Since we can't remove system properties, "empty" is traditionally
  // the same as "missing" (this was true for cutils' property_get).
  return property_value.empty() ? default_value : property_value;
}

bool SetProperty(const std::string& key, const std::string& value) {
  return (__system_property_set(key.c_str(), value.c_str()) == 0);
}
```



_system_properties.h头文件定义PROP_SERVICE_NAME
sys_system_properties.h

```c++
\android14\bionic\libc\include\sys\_system_properties.h
ifndef _INCLUDE_SYS__SYSTEM_PROPERTIES_H
#define _INCLUDE_SYS__SYSTEM_PROPERTIES_H

#include <sys/cdefs.h>
#include <stdint.h>

#ifndef _REALLY_INCLUDE_SYS__SYSTEM_PROPERTIES_H_
#error you should #include <sys/system_properties.h> instead
#endif

#include <sys/system_properties.h>

__BEGIN_DECLS

#define PROP_SERVICE_NAME "property_service"
#define PROP_FILENAME "/dev/__properties__"

#define PROP_MSG_SETPROP 1
#define PROP_MSG_SETPROP2 0x00020001

#define PROP_SUCCESS 0
#define PROP_ERROR_READ_CMD 0x0004
#define PROP_ERROR_READ_DATA 0x0008
#define PROP_ERROR_READ_ONLY_PROPERTY 0x000B
#define PROP_ERROR_INVALID_NAME 0x0010
#define PROP_ERROR_INVALID_VALUE 0x0014
#define PROP_ERROR_PERMISSION_DENIED 0x0018
#define PROP_ERROR_INVALID_CMD 0x001B
#define PROP_ERROR_HANDLE_CONTROL_MESSAGE 0x0020
#define PROP_ERROR_SET_FAILED 0x0024

int __system_property_set_filename(const char* __filename);

int __system_property_area_init(void);

uint32_t __system_property_area_serial(void);

int __system_property_add(const char* __name, unsigned int __name_length, const char* __value, unsigned int __value_length);

int __system_property_update(prop_info* __pi, const char* __value, unsigned int __value_length);

uint32_t __system_property_serial(const prop_info* __pi);


int __system_properties_init(void)
/* Deprecated: use __system_property_wait instead. */
uint32_t __system_property_wait_any(uint32_t __old_serial);

__END_DECLS

#endif
```



bionic\libc\bionic\system_property_set.cpp

```c++
\android14\bionic\libc\bionic\system_property_set.cpp
static const char property_service_socket[] = "/dev/socket/" PROP_SERVICE_NAME;
static const char* kServiceVersionPropertyName = "ro.property_service.version";

class PropertyServiceConnection {
 public:
  PropertyServiceConnection() : last_error_(0) {
    socket_.reset(::socket(AF_LOCAL, SOCK_STREAM | SOCK_CLOEXEC, 0));
    if (socket_.get() == -1) {
      last_error_ = errno;
      return;
    }

    const size_t namelen = strlen(property_service_socket);
    sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    strlcpy(addr.sun_path, property_service_socket, sizeof(addr.sun_path));
    addr.sun_family = AF_LOCAL;
    socklen_t alen = namelen + offsetof(sockaddr_un, sun_path) + 1;

    if (TEMP_FAILURE_RETRY(connect(socket_.get(),
                                   reinterpret_cast<sockaddr*>(&addr), alen)) == -1) {
      last_error_ = errno;
      socket_.reset();
    }
  }

  bool IsValid() {
    return socket_.get() != -1;
  }

  int GetLastError() {
    return last_error_;
  }

  bool RecvInt32(int32_t* value) {
    int result = TEMP_FAILURE_RETRY(recv(socket_.get(), value, sizeof(*value), MSG_WAITALL));
    return CheckSendRecvResult(result, sizeof(*value));
  }

  int socket() {
    return socket_.get();
  }

 private:
  bool CheckSendRecvResult(int result, int expected_len) {
    if (result == -1) {
      last_error_ = errno;
    } else if (result != expected_len) {
      last_error_ = -1;
    } else {
      last_error_ = 0;
    }

    return last_error_ == 0;
  }

  ScopedFd socket_;
  int last_error_;

  friend class SocketWriter;
};

class SocketWriter {
 public:
  explicit SocketWriter(PropertyServiceConnection* connection)
      : connection_(connection), iov_index_(0), uint_buf_index_(0) {
  }

  SocketWriter& WriteUint32(uint32_t value) {
    CHECK(uint_buf_index_ < kUintBufSize);
    CHECK(iov_index_ < kIovSize);
    uint32_t* ptr = uint_buf_ + uint_buf_index_;
    uint_buf_[uint_buf_index_++] = value;
    iov_[iov_index_].iov_base = ptr;
    iov_[iov_index_].iov_len = sizeof(*ptr);
    ++iov_index_;
    return *this;
  }

  SocketWriter& WriteString(const char* value) {
    uint32_t valuelen = strlen(value);
    WriteUint32(valuelen);
    if (valuelen == 0) {
      return *this;
    }

    CHECK(iov_index_ < kIovSize);
    iov_[iov_index_].iov_base = const_cast<char*>(value);
    iov_[iov_index_].iov_len = valuelen;
    ++iov_index_;

    return *this;
  }

  bool Send() {
    if (!connection_->IsValid()) {
      return false;
    }

    if (writev(connection_->socket(), iov_, iov_index_) == -1) {
      connection_->last_error_ = errno;
      return false;
    }

    iov_index_ = uint_buf_index_ = 0;
    return true;
  }

 private:
  static constexpr size_t kUintBufSize = 8;
  static constexpr size_t kIovSize = 8;

  PropertyServiceConnection* connection_;
  iovec iov_[kIovSize];
  size_t iov_index_;
  uint32_t uint_buf_[kUintBufSize];
  size_t uint_buf_index_;

  BIONIC_DISALLOW_IMPLICIT_CONSTRUCTORS(SocketWriter);
};

struct prop_msg {
  unsigned cmd;
  char name[PROP_NAME_MAX];
  char value[PROP_VALUE_MAX];
};

static int send_prop_msg(const prop_msg* msg) {
  PropertyServiceConnection connection;
  if (!connection.IsValid()) {
    return connection.GetLastError();
  }

  int result = -1;
  int s = connection.socket();

  const int num_bytes = TEMP_FAILURE_RETRY(send(s, msg, sizeof(prop_msg), 0));
  if (num_bytes == sizeof(prop_msg)) {
    // We successfully wrote to the property server but now we
    // wait for the property server to finish its work.  It
    // acknowledges its completion by closing the socket so we
    // poll here (on nothing), waiting for the socket to close.
    // If you 'adb shell setprop foo bar' you'll see the POLLHUP
    // once the socket closes.  Out of paranoia we cap our poll
    // at 250 ms.
    pollfd pollfds[1];
    pollfds[0].fd = s;
    pollfds[0].events = 0;
    const int poll_result = TEMP_FAILURE_RETRY(poll(pollfds, 1, 250 /* ms */));
    if (poll_result == 1 && (pollfds[0].revents & POLLHUP) != 0) {
      result = 0;
    } else {
      // Ignore the timeout and treat it like a success anyway.
      // The init process is single-threaded and its property
      // service is sometimes slow to respond (perhaps it's off
      // starting a child process or something) and thus this
      // times out and the caller thinks it failed, even though
      // it's still getting around to it.  So we fake it here,
      // mostly for ctl.* properties, but we do try and wait 250
      // ms so callers who do read-after-write can reliably see
      // what they've written.  Most of the time.
      async_safe_format_log(ANDROID_LOG_WARN, "libc",
                            "Property service has timed out while trying to set \"%s\" to \"%s\"",
                            msg->name, msg->value);
      result = 0;
    }
  }

  return result;
}

static constexpr uint32_t kProtocolVersion1 = 1;
static constexpr uint32_t kProtocolVersion2 = 2;  // current

static atomic_uint_least32_t g_propservice_protocol_version = 0;

static void detect_protocol_version() {
   //从ro.property_service.version中获取协议版本，可在平台终端getprop ro.property_service.version
  //在后续中可找到设置该属性的位置
  char value[PROP_VALUE_MAX];
  if (__system_property_get(kServiceVersionPropertyName, value) == 0) {
    g_propservice_protocol_version = kProtocolVersion1;
    async_safe_format_log(ANDROID_LOG_WARN, "libc",
                          "Using old property service protocol (\"%s\" is not set)",
                          kServiceVersionPropertyName);
  } else {
    uint32_t version = static_cast<uint32_t>(atoll(value));
    if (version >= kProtocolVersion2) {
      g_propservice_protocol_version = kProtocolVersion2;
    } else {
      async_safe_format_log(ANDROID_LOG_WARN, "libc",
                            "Using old property service protocol (\"%s\"=\"%s\")",
                            kServiceVersionPropertyName, value);
      g_propservice_protocol_version = kProtocolVersion1;
    }
  }
}

__BIONIC_WEAK_FOR_NATIVE_BRIDGE
int __system_property_set(const char* key, const char* value) {
  if (key == nullptr) return -1;
  if (value == nullptr) value = "";

  if (g_propservice_protocol_version == 0) {
    detect_protocol_version();//获取属性服务协议版本
  }

  if (g_propservice_protocol_version == kProtocolVersion1) {
    // Old protocol does not support long names or values
    //旧协议版本限定prop name最大长度为PROP_NAME_MAX，prop val最大长度为PROP_VALUE_MAX
    if (strlen(key) >= PROP_NAME_MAX) return -1;
    if (strlen(value) >= PROP_VALUE_MAX) return -1;

    prop_msg msg;
    memset(&msg, 0, sizeof msg);
    msg.cmd = PROP_MSG_SETPROP;
    strlcpy(msg.name, key, sizeof msg.name);
    strlcpy(msg.value, value, sizeof msg.value);

    return send_prop_msg(&msg);
  } else {
    // New protocol only allows long values for ro. properties only.
    //进入新版本协议，仅对prop val长度有要求，不超过92，且属性不为只读属性
    if (strlen(value) >= PROP_VALUE_MAX && strncmp(key, "ro.", 3) != 0) return -1;
    // Use proper protocol
    PropertyServiceConnection connection;
    if (!connection.IsValid()) {
      errno = connection.GetLastError();
      async_safe_format_log(
          ANDROID_LOG_WARN, "libc",
          "Unable to set property \"%s\" to \"%s\": connection failed; errno=%d (%s)", key, value,
          errno, strerror(errno));
      return -1;
    }

    SocketWriter writer(&connection);//通过Socket与property_service进行通信
    if (!writer.WriteUint32(PROP_MSG_SETPROP2).WriteString(key).WriteString(value).Send()) {
      errno = connection.GetLastError();
      async_safe_format_log(ANDROID_LOG_WARN, "libc",
                            "Unable to set property \"%s\" to \"%s\": write failed; errno=%d (%s)",
                            key, value, errno, strerror(errno));
      return -1;
    }

    int result = -1;
    if (!connection.RecvInt32(&result)) {
      errno = connection.GetLastError();
      async_safe_format_log(ANDROID_LOG_WARN, "libc",
                            "Unable to set property \"%s\" to \"%s\": recv failed; errno=%d (%s)",
                            key, value, errno, strerror(errno));
      return -1;
    }

    if (result != PROP_SUCCESS) {
      async_safe_format_log(ANDROID_LOG_WARN, "libc",
                            "Unable to set property \"%s\" to \"%s\": error code: 0x%x", key, value,
                            result);
      return -1;
    }

    return 0;
  }
}
```



### property_service流程

流程到了这里会发现，最终需要通过Socket与property_service来通信进行设置属性值，那么问题来了：

- property_service是谁创建的？
- property_service是怎么启动的？
- property_service是如何setprop的？
  熟悉Android开机流程的同学会马上联想到init进程，property_service正是init进程来初始化和启动的。



```java
system\core\init\init.cpp
int SecondStageMain(int argc, char** argv) {
    ...
    PropertyInit();//属性初始化
    ...
    //property_load_boot_defaults(load_debug_prop);//加载开机默认属性配置,android14放在PropertyInit()函数
    StartPropertyService(&property_fd);//启动属性服务
    ...
}
```



属性初始化property_init

```java
\android14\system\core\init\property_service.cpp
void PropertyInit() {
    selinux_callback cb;
    cb.func_audit = PropertyAuditCallback;
    selinux_set_callback(SELINUX_CB_AUDIT, cb);

    mkdir("/dev/__properties__", S_IRWXU | S_IXGRP | S_IXOTH);
    CreateSerializedPropertyInfo();//创建属性信息property_info
    if (__system_property_area_init()) {//创建共享内存
        LOG(FATAL) << "Failed to initialize property area";
    }
    if (!property_info_area.LoadDefaultPath()) {
        LOG(FATAL) << "Failed to load serialized property info file";
    }

    // If arguments are passed both on the command line and in DT,
    // properties set in DT always have priority over the command-line ones.
    ProcessKernelDt();
    ProcessKernelCmdline();
    ProcessBootconfig();

    // Propagate the kernel variables to internal variables
    // used by init as well as the current required properties.
    ExportKernelBootProps();

    PropertyLoadBootDefaults();//加载开机默认属性配置
}

//读取selinux模块中的property相关文件，解析并加载到property_info中
void CreateSerializedPropertyInfo() {
    auto property_infos = std::vector<PropertyInfoEntry>();
    if (access("/system/etc/selinux/plat_property_contexts", R_OK) != -1) {
        if (!LoadPropertyInfoFromFile("/system/etc/selinux/plat_property_contexts",
                                      &property_infos)) {
            return;
        }
        // Don't check for failure here, since we don't always have all of these partitions.
        // E.g. In case of recovery, the vendor partition will not have mounted and we
        // still need the system / platform properties to function.
        if (access("/dev/selinux/apex_property_contexts", R_OK) != -1) {
            LoadPropertyInfoFromFile("/dev/selinux/apex_property_contexts", &property_infos);
        }
        if (access("/system_ext/etc/selinux/system_ext_property_contexts", R_OK) != -1) {
            LoadPropertyInfoFromFile("/system_ext/etc/selinux/system_ext_property_contexts",
                                     &property_infos);
        }
        if (access("/vendor/etc/selinux/vendor_property_contexts", R_OK) != -1) {
            LoadPropertyInfoFromFile("/vendor/etc/selinux/vendor_property_contexts",
                                     &property_infos);
        }
        if (access("/product/etc/selinux/product_property_contexts", R_OK) != -1) {
            LoadPropertyInfoFromFile("/product/etc/selinux/product_property_contexts",
                                     &property_infos);
        }
        if (access("/odm/etc/selinux/odm_property_contexts", R_OK) != -1) {
            LoadPropertyInfoFromFile("/odm/etc/selinux/odm_property_contexts", &property_infos);
        }
    } else {
        if (!LoadPropertyInfoFromFile("/plat_property_contexts", &property_infos)) {
            return;
        }
        LoadPropertyInfoFromFile("/system_ext_property_contexts", &property_infos);
        LoadPropertyInfoFromFile("/vendor_property_contexts", &property_infos);
        LoadPropertyInfoFromFile("/product_property_contexts", &property_infos);
        LoadPropertyInfoFromFile("/odm_property_contexts", &property_infos);
        LoadPropertyInfoFromFile("/dev/selinux/apex_property_contexts", &property_infos);
    }

    auto serialized_contexts = std::string();
    auto error = std::string();
    if (!BuildTrie(property_infos, "u:object_r:default_prop:s0", "string", &serialized_contexts,
                   &error)) {
        LOG(ERROR) << "Unable to serialize property contexts: " << error;
        return;
    }

    constexpr static const char kPropertyInfosPath[] = "/dev/__properties__/property_info";
    if (!WriteStringToFile(serialized_contexts, kPropertyInfosPath, 0444, 0, 0, false)) {
        PLOG(ERROR) << "Unable to write serialized property infos to file";
    }
    selinux_android_restorecon(kPropertyInfosPath, 0);
}
```





bionic\libc\bionic\system_property_api.cpp

```c++
int __system_property_area_init() {
  bool fsetxattr_failed = false;
  return system_properties.AreaInit(PROP_FILENAME, &fsetxattr_failed) && !fsetxattr_failed ? 0 : -1;
}
```



初始化属性内存共享区域
bionic\libc\system_properties\system_properties.cpp

```c++
bool SystemProperties::AreaInit(const char* filename, bool* fsetxattr_failed) {
  if (strlen(filename) >= PROP_FILENAME_MAX) {
    return false;
  }
  strcpy(property_filename_, filename);
  contexts_ = new (contexts_data_) ContextsSerialized();
  if (!contexts_->Initialize(true, property_filename_, fsetxattr_failed)) {
    return false;
  }
  initialized_ = true;
  return true;
}
```

bionic\libc\system_properties\contexts_serialized.cpp

```c++
bool ContextsSerialized::Initialize(bool writable, const char* filename, bool* fsetxattr_failed) {
  filename_ = filename;
  if (!InitializeProperties()) {
    return false;
  }
  ...
}
bool ContextsSerialized::InitializeProperties() {
  if (!property_info_area_file_.LoadDefaultPath()) {
    return false;
  }
  ...
}
```

__system_property_area_init()经过一系列的方法调用，最终通过mmap()将/dev/__property __/property_info加载到共享内存。
 system\core\property_service\libpropertyinfoparser\property_info_parser.cpp

```c++
bool PropertyInfoAreaFile::LoadDefaultPath() {
  return LoadPath("/dev/__properties__/property_info");
}
bool PropertyInfoAreaFile::LoadPath(const char* filename) {
  int fd = open(filename, O_CLOEXEC | O_NOFOLLOW | O_RDONLY);
  ...
  void* map_result = mmap(nullptr, mmap_size, PROT_READ, MAP_SHARED, fd, 0);
  ...
}
```



从PropertyLoadBootDefaults代码可以看出从多个属性文件.prop中系统属性加载至properties变量，再通过PropertySet()将properties添加到系统中，并初始化只读、编译、usb相关属性值。
 PropertySet()，通过Socket与属性服务进行通信，将props存储共享内存。

```c++
void PropertyLoadBootDefaults() {
    // We read the properties and their values into a map, in order to always allow properties
    // loaded in the later property files to override the properties in loaded in the earlier
    // property files, regardless of if they are "ro." properties or not.
    std::map<std::string, std::string> properties;

    if (IsRecoveryMode()) {
        if (auto res = load_properties_from_file("/prop.default", nullptr, &properties);
            !res.ok()) {
            LOG(ERROR) << res.error();
        }
    }

    // /<part>/etc/build.prop is the canonical location of the build-time properties since S.
    // Falling back to /<part>/defalt.prop and /<part>/build.prop only when legacy path has to
    // be supported, which is controlled by the support_legacy_path_until argument.
    const auto load_properties_from_partition = [&properties](const std::string& partition,
                                                              int support_legacy_path_until) {
        auto path = "/" + partition + "/etc/build.prop";
        if (load_properties_from_file(path.c_str(), nullptr, &properties).ok()) {
            return;
        }
        // To read ro.<partition>.build.version.sdk, temporarily load the legacy paths into a
        // separate map. Then by comparing its value with legacy_version, we know that if the
        // partition is old enough so that we need to respect the legacy paths.
        std::map<std::string, std::string> temp;
        auto legacy_path1 = "/" + partition + "/default.prop";
        auto legacy_path2 = "/" + partition + "/build.prop";
        load_properties_from_file(legacy_path1.c_str(), nullptr, &temp);
        load_properties_from_file(legacy_path2.c_str(), nullptr, &temp);
        bool support_legacy_path = false;
        auto version_prop_name = "ro." + partition + ".build.version.sdk";
        auto it = temp.find(version_prop_name);
        if (it == temp.end()) {
            // This is embarassing. Without the prop, we can't determine how old the partition is.
            // Let's be conservative by assuming it is very very old.
            support_legacy_path = true;
        } else if (int value;
                   ParseInt(it->second.c_str(), &value) && value <= support_legacy_path_until) {
            support_legacy_path = true;
        }
        if (support_legacy_path) {
            // We don't update temp into properties directly as it might skip any (future) logic
            // for resolving duplicates implemented in load_properties_from_file.  Instead, read
            // the files again into the properties map.
            load_properties_from_file(legacy_path1.c_str(), nullptr, &properties);
            load_properties_from_file(legacy_path2.c_str(), nullptr, &properties);
        } else {
            LOG(FATAL) << legacy_path1 << " and " << legacy_path2 << " were not loaded "
                       << "because " << version_prop_name << "(" << it->second << ") is newer "
                       << "than " << support_legacy_path_until;
        }
    };

    // Order matters here. The more the partition is specific to a product, the higher its
    // precedence is.
    LoadPropertiesFromSecondStageRes(&properties);

    // system should have build.prop, unlike the other partitions
    if (auto res = load_properties_from_file("/system/build.prop", nullptr, &properties);
        !res.ok()) {
        LOG(WARNING) << res.error();
    }

    load_properties_from_partition("system_ext", /* support_legacy_path_until */ 30);
    load_properties_from_file("/system_dlkm/etc/build.prop", nullptr, &properties);
    // TODO(b/117892318): uncomment the following condition when vendor.imgs for aosp_* targets are
    // all updated.
    // if (SelinuxGetVendorAndroidVersion() <= __ANDROID_API_R__) {
    load_properties_from_file("/vendor/default.prop", nullptr, &properties);
    // }
    load_properties_from_file("/vendor/build.prop", nullptr, &properties);
    load_properties_from_file("/vendor_dlkm/etc/build.prop", nullptr, &properties);
    load_properties_from_file("/odm_dlkm/etc/build.prop", nullptr, &properties);
    load_properties_from_partition("odm", /* support_legacy_path_until */ 28);
    load_properties_from_partition("product", /* support_legacy_path_until */ 30);

    if (access(kDebugRamdiskProp, R_OK) == 0) {
        LOG(INFO) << "Loading " << kDebugRamdiskProp;
        if (auto res = load_properties_from_file(kDebugRamdiskProp, nullptr, &properties);
            !res.ok()) {
            LOG(WARNING) << res.error();
        }
    }

    for (const auto& [name, value] : properties) {
        std::string error;
        if (PropertySetNoSocket(name, value, &error) != PROP_SUCCESS) {
            LOG(ERROR) << "Could not set '" << name << "' to '" << value
                       << "' while loading .prop files" << error;
        }
    }

    property_initialize_ro_product_props();
    property_initialize_build_id();
    property_derive_build_fingerprint();
    property_derive_legacy_build_fingerprint();
    property_initialize_ro_cpu_abilist();
    property_initialize_ro_vendor_api_level();

    update_sys_usb_config();
}
```



再看看init中是怎么启动这个属性服务的StartPropertyService(&property_fd);

```c++
\android14\system\core\init\property_service.cpp
void StartPropertyService(int* epoll_socket) {
    InitPropertySet("ro.property_service.version", "2");

    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) != 0) {
        PLOG(FATAL) << "Failed to socketpair() between property_service and init";
    }
    *epoll_socket = from_init_socket = sockets[0];
    init_socket = sockets[1];
    StartSendingMessages();

    if (auto result = CreateSocket(PROP_SERVICE_NAME, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK,
                                   /*passcred=*/false, /*should_listen=*/false, 0666, /*uid=*/0,
                                   /*gid=*/0, /*socketcon=*/{});
        result.ok()) {
        property_set_fd = *result;
    } else {
        LOG(FATAL) << "start_property_service socket creation failed: " << result.error();
    }

    listen(property_set_fd, 8);//设置Socket连接数为8

    auto new_thread = std::thread{PropertyServiceThread};//new了一个线程
    property_service_thread.swap(new_thread);

    auto async_persist_writes =
            android::base::GetBoolProperty("ro.property_service.async_persist_writes", false);

    if (async_persist_writes) {
        persist_write_thread = std::make_unique<PersistWriteThread>();
    }
}
```





PropertyServiceThread

```c++
static void PropertyServiceThread() {
    Epoll epoll;
    if (auto result = epoll.Open(); !result.ok()) {
        LOG(FATAL) << result.error();
    }
    //注册epoll,监听property_set_fd改变时调用handle_property_set_fd
    if (auto result = epoll.RegisterHandler(property_set_fd, handle_property_set_fd);
        !result.ok()) {
        LOG(FATAL) << result.error();
    } 
    if (auto result = epoll.RegisterHandler(init_socket, HandleInitSocket); !result.ok()) {
        LOG(FATAL) << result.error();
    }

    while (true) {
        auto epoll_result = epoll.Wait(std::nullopt);
        if (!epoll_result.ok()) {
            LOG(ERROR) << epoll_result.error();
        }
    }
}
```

```c++
static void handle_property_set_fd() {
   
        // HandlePropertySet takes ownership of the socket if the set is handled asynchronously.
        const auto& cr = socket.cred();
        std::string error;
    //调用HandlePropertySet
        auto result = HandlePropertySet(name, value, source_context, cr, &socket, &error);
        if (!result) {
            // Result will be sent after completion.
            return;
        }
}
```





HandlePropertySet

```c++
// This returns one of the enum of PROP_SUCCESS or PROP_ERROR*, or std::nullopt
// if asynchronous.
std::optional<uint32_t> HandlePropertySet(const std::string& name, const std::string& value,
                                          const std::string& source_context, const ucred& cr,
                                          SocketConnection* socket, std::string* error) {
     //检查prop 权限
    if (auto ret = CheckPermissions(name, value, source_context, cr, error); ret != PROP_SUCCESS) {
        return {ret};
    }

    if (StartsWith(name, "ctl.")) {//ctl属性：ctl.start启动服务，ctl.stop关闭服务
        return {SendControlMessage(name.c_str() + 4, value, cr.pid, socket, error)};
    }

    // sys.powerctl is a special property that is used to make the device reboot.  We want to log
    // any process that sets this property to be able to accurately blame the cause of a shutdown.
    if (name == "sys.powerctl") {
        std::string cmdline_path = StringPrintf("proc/%d/cmdline", cr.pid);
        std::string process_cmdline;
        std::string process_log_string;
        if (ReadFileToString(cmdline_path, &process_cmdline)) {
            // Since cmdline is null deliminated, .c_str() conveniently gives us just the process
            // path.
            process_log_string = StringPrintf(" (%s)", process_cmdline.c_str());
        }
        LOG(INFO) << "Received sys.powerctl='" << value << "' from pid: " << cr.pid
                  << process_log_string;
        if (value == "reboot,userspace" && !is_userspace_reboot_supported().value_or(false)) {
            *error = "Userspace reboot is not supported by this device";
            return {PROP_ERROR_INVALID_VALUE};
        }
    }

    // If a process other than init is writing a non-empty value, it means that process is
    // requesting that init performs a restorecon operation on the path specified by 'value'.
    // We use a thread to do this restorecon operation to prevent holding up init, as it may take
    // a long time to complete.
    if (name == kRestoreconProperty && cr.pid != 1 && !value.empty()) {
        static AsyncRestorecon async_restorecon;
        async_restorecon.TriggerRestorecon(value);
        return {PROP_SUCCESS};
    }

    return PropertySet(name, value, socket, error);//设置属性
}
```





PropertySet

```c++
static std::optional<uint32_t> PropertySet(const std::string& name, const std::string& value,
                                           SocketConnection* socket, std::string* error) {
    size_t valuelen = value.size();

    if (!IsLegalPropertyName(name)) {//检测属性合法性
        *error = "Illegal property name";
        return {PROP_ERROR_INVALID_NAME};
    }

    if (auto result = IsLegalPropertyValue(name, value); !result.ok()) {
        *error = result.error().message();
        return {PROP_ERROR_INVALID_VALUE};
    }

    // sdrv property process
    if (StartsWith(name, "cdm.") || StartsWith(name, "csd.")) {
        return SdrvPropProcess(socket, name, value, error);
    }
    //检测属性是否已存在
    prop_info* pi = (prop_info*)__system_property_find(name.c_str());
    if (pi != nullptr) {
        // ro.* properties are actually "write-once".
        if (StartsWith(name, "ro.")) {
            *error = "Read-only property was already set";
            return {PROP_ERROR_READ_ONLY_PROPERTY};
        }
      //属性已存在,并且非ro只读属性，更新属性值
        __system_property_update(pi, value.c_str(), valuelen);
    } else {
        //属性不存在,添加属性值
        int rc = __system_property_add(name.c_str(), name.size(), value.c_str(), valuelen);
        if (rc < 0) {
            *error = "__system_property_add failed";
            return {PROP_ERROR_SET_FAILED};
        }
    }

    // Don't write properties to disk until after we have read all default
    // properties to prevent them from being overwritten by default values.
     //避免在load所有属性之前将属性写入disk，防止属性值被覆盖。
    if (socket && persistent_properties_loaded && StartsWith(name, "persist.")) {
        if (persist_write_thread) {
            //将persist属性持久化disk和/data/property/persistent_properties,这里persist属性新起了一个线程进行写
            //需要注意的是设置persist属性不能在主线程里面时序紧张的时候
            persist_write_thread->Write(name, value, std::move(*socket));
            return {};
        }
        WritePersistentProperty(name, value);
    }

    NotifyPropertyChange(name, value);//特殊属性值(如sys.powerctl)改变后系统需要立即处理。
    return {PROP_SUCCESS};
}
```

这是顺便提一下，persist属性是修改文件/data/property/persistent_properties

上面代码就会判断setprop的key是不是带了persist开头的属性，如果是persist开头，接下来判断persist_write_thread线程是否不为null，如果不为null则调用persist_write_thread->Write进行持久化写入

PersistWriteThread

```c++
PersistWriteThread::PersistWriteThread() {
    auto new_thread = std::thread([this]() -> void { Work(); });
    thread_.swap(new_thread);
}

void PersistWriteThread::Work() {
    while (true) {
        std::tuple<std::string, std::string, SocketConnection> item;

        // Grab the next item within the lock.
        {
            std::unique_lock<std::mutex> lock(mutex_);

            while (work_.empty()) {
                cv_.wait(lock);
            }

            item = std::move(work_.front());
            work_.pop_front();
        }

        std::this_thread::sleep_for(1s);

        // Perform write/fsync outside the lock.
        WritePersistentProperty(std::get<0>(item), std::get<1>(item));
        NotifyPropertyChange(std::get<0>(item), std::get<1>(item));

        SocketConnection& socket = std::get<2>(item);
        socket.SendUint32(PROP_SUCCESS);
    }
}
```

可以看到最后是在独立线程中调用WritePersistentProperty进行写入属性到文件

```c++
\android14\system\core\init\persistent_properties.cpp
void WritePersistentProperty(const std::string& name, const std::string& value) {
    auto persistent_properties = LoadPersistentPropertyFile();

    if (!persistent_properties.ok()) {
        LOG(ERROR) << "Recovering persistent properties from memory: "
                   << persistent_properties.error();
        persistent_properties = LoadPersistentPropertiesFromMemory();
    }
    auto it = std::find_if(persistent_properties->mutable_properties()->begin(),
                           persistent_properties->mutable_properties()->end(),
                           [&name](const auto& record) { return record.name() == name; });
    if (it != persistent_properties->mutable_properties()->end()) {
        it->set_name(name);
        it->set_value(value);
    } else {
        AddPersistentProperty(name, value, &persistent_properties.value());
    }

    if (auto result = WritePersistentPropertyFile(*persistent_properties); !result.ok()) {
        LOG(ERROR) << "Could not store persistent property: " << result.error();
    }
}

```

```c++
Result<void> WritePersistentPropertyFile(const PersistentProperties& persistent_properties) {
    const std::string temp_filename = persistent_property_filename + ".tmp";
    unique_fd fd(TEMP_FAILURE_RETRY(
        open(temp_filename.c_str(), O_WRONLY | O_CREAT | O_NOFOLLOW | O_TRUNC | O_CLOEXEC, 0600)));
    if (fd == -1) {
        return ErrnoError() << "Could not open temporary properties file";
    }
    std::string serialized_string;
    if (!persistent_properties.SerializeToString(&serialized_string)) {
        return Error() << "Unable to serialize properties";
    }
    if (!WriteStringToFd(serialized_string, fd)) {
        return ErrnoError() << "Unable to write file contents";
    }
    fsync(fd.get());
    fd.reset();

    if (rename(temp_filename.c_str(), persistent_property_filename.c_str())) {
        int saved_errno = errno;
        unlink(temp_filename.c_str());
        return Error(saved_errno) << "Unable to rename persistent property file";
    }

    // rename() is atomic with regards to the kernel's filesystem buffers, but the parent
    // directories must be fsync()'ed otherwise, the rename is not necessarily written to storage.
    // Note in this case, that the source and destination directories are the same, so only one
    // fsync() is required.
    auto dir = Dirname(persistent_property_filename);
    auto dir_fd = unique_fd{open(dir.c_str(), O_DIRECTORY | O_RDONLY | O_CLOEXEC)};
    if (dir_fd < 0) {
        return ErrnoError() << "Unable to open persistent properties directory for fsync()";
    }
    fsync(dir_fd.get());

    return {};
}
```

这里又是调用WritePersistentPropertyFile写入到文件





更新和添加属性

```c++
bionic\libc\bionic\system_property_api.cpp
int __system_property_update(prop_info* pi, const char* value, unsigned int len) {
  return system_properties.Update(pi, value, len);//更新属性值
}
int __system_property_add(const char* name, unsigned int namelen, const char* value,
                          unsigned int valuelen) {
  return system_properties.Add(name, namelen, value, valuelen);//添加属性值
}
```



bionic\libc\system_properties\system_properties.cpp

```c++
int SystemProperties::Update(prop_info* pi, const char* value, unsigned int len) {
  if (len >= PROP_VALUE_MAX) {
    return -1;
  }

  if (!initialized_) {
    return -1;
  }

  prop_area* serial_pa = contexts_->GetSerialPropArea();
  if (!serial_pa) {
    return -1;
  }
  prop_area* pa = contexts_->GetPropAreaForName(pi->name);
  if (__predict_false(!pa)) {
    async_safe_format_log(ANDROID_LOG_ERROR, "libc", "Could not find area for \"%s\"", pi->name);
    return -1;
  }

  uint32_t serial = atomic_load_explicit(&pi->serial, memory_order_relaxed);
  unsigned int old_len = SERIAL_VALUE_LEN(serial);

  // The contract with readers is that whenever the dirty bit is set, an undamaged copy
  // of the pre-dirty value is available in the dirty backup area. The fence ensures
  // that we publish our dirty area update before allowing readers to see a
  // dirty serial.
  memcpy(pa->dirty_backup_area(), pi->value, old_len + 1);
  atomic_thread_fence(memory_order_release);
  serial |= 1;
  atomic_store_explicit(&pi->serial, serial, memory_order_relaxed);
  strlcpy(pi->value, value, len + 1);//属性值更新
  // Now the primary value property area is up-to-date. Let readers know that they should
  // look at the property value instead of the backup area.
  atomic_thread_fence(memory_order_release);
  atomic_store_explicit(&pi->serial, (len << 24) | ((serial + 1) & 0xffffff), memory_order_relaxed);
  __futex_wake(&pi->serial, INT32_MAX);  // Fence by side effect
  atomic_store_explicit(serial_pa->serial(),
                        atomic_load_explicit(serial_pa->serial(), memory_order_relaxed) + 1,
                        memory_order_release);
  __futex_wake(serial_pa->serial(), INT32_MAX);

  return 0;
}

int SystemProperties::Add(const char* name, unsigned int namelen, const char* value,
                          unsigned int valuelen) {

  prop_area* pa = contexts_->GetPropAreaForName(name);
  if (!pa) {
    async_safe_format_log(ANDROID_LOG_ERROR, "libc", "Access denied adding property \"%s\"", name);
    return -1;
  }

  bool ret = pa->add(name, namelen, value, valuelen);//向共享内存添加新属性
  if (!ret) {
    return -1;
  }
  。。。
  return 0;
}
```



prop_area.cpp

```c++
bionic\libc\system_properties\prop_area.cpp
bool prop_area::add(const char* name, unsigned int namelen, const char* value,
                    unsigned int valuelen) {
  return find_property(root_node(), name, namelen, value, valuelen, true);
}
...
const prop_info* prop_area::find_property(prop_bt* const trie, const char* name, uint32_t namelen,
                                          const char* value, uint32_t valuelen,
                                          bool alloc_if_needed) {
    ...
    prop_bt* root = nullptr;
    uint_least32_t children_offset = atomic_load_explicit(&current->children, memory_order_relaxed);
    if (children_offset != 0) {//找到属性节点
      root = to_prop_bt(&current->children);
    } else if (alloc_if_needed) {//未找到时新建节点
      uint_least32_t new_offset;
      root = new_prop_bt(remaining_name, substr_size, &new_offset);
      if (root) {
        atomic_store_explicit(&current->children, new_offset, memory_order_release);
      }
    }
    ...
    current = find_prop_bt(root, remaining_name, substr_size, alloc_if_needed);
    remaining_name = sep + 1;
  }
  uint_least32_t prop_offset = atomic_load_explicit(&current->prop, memory_order_relaxed);
  if (prop_offset != 0) {
    return to_prop_info(&current->prop);//返回已存在的prop_info
  } else if (alloc_if_needed) {
    uint_least32_t new_offset;
    //添加新属性
    prop_info* new_info = new_prop_info(name, namelen, value, valuelen, &new_offset);
    ...
  }
}
prop_info* prop_area::new_prop_info(const char* name, uint32_t namelen, const char* value,
                                    uint32_t valuelen, uint_least32_t* const off) {
  ...
  prop_info* info;
  if (valuelen >= PROP_VALUE_MAX) {
    uint32_t long_value_offset = 0;
    char* long_location = reinterpret_cast<char*>(allocate_obj(valuelen + 1, &long_value_offset));
    if (!long_location) return nullptr;
    memcpy(long_location, value, valuelen);
    long_location[valuelen] = '\0';
    long_value_offset -= new_offset;
    info = new (p) prop_info(name, namelen, long_value_offset);
  } else {
    info = new (p) prop_info(name, namelen, value, valuelen);
  }
  *off = new_offset;
  return info;
}
```

从上述code可分析出设置属性流程中根据所设置的属性值是否存在分别走update()和add()流程，而add 最后调用查找属性方法，如果不存在则新建共享内存节点，将prop_info存入。自此，set prop流程结束。



### get prop流程

在上面system\core\base\properties.cpp中__system_property_find(key.c_str())
 bionic\libc\bionic\system_property_api.cpp

```c++
const prop_info* __system_property_find(const char* name) {
  return system_properties.Find(name);
}
```

bionic\libc\system_properties\system_properties.cpp

```c++
const prop_info* SystemProperties::Find(const char* name) {
  ...
  prop_area* pa = contexts_->GetPropAreaForName(name);
  ...
  return pa->find(name);
}
```

bionic\libc\system_properties\prop_area.cpp

```c++
const prop_info* prop_area::find(const char* name) {
  return find_property(root_node(), name, strlen(name), nullptr, 0, false);
}
```

find_property后续流程同上