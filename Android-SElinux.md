## Android SElinux

### 1.什么是selinux

SELinux（Security-Enhanced Linux）是一个为 Linux 内核提供强化的安全性机制的项目。它通过实施强制访问控制（MAC）来增强系统的安全性。传统的 Linux 安全模型使用的是基于用户和组的自愿访问控制（DAC），而 SELinux 引入了基于策略的强制访问控制。

在 SELinux 中，每个进程、文件和系统资源都有一个安全上下文，其中包含了关于其访问权限的详细信息。这种访问控制的强制性意味着即使用户具有访问某个资源的权限，SELinux 策略也可以限制对该资源的访问。

SELinux 主要有以下几个核心概念：

安全上下文（Security Context）： 每个对象（如进程、文件、套接字等）都有一个关联的安全上下文，它包含了 SELinux 策略中定义的有关该对象的信息。 策略（Policy）： SELinux 使用一个策略来定义系统中的安全规则。这个策略规定了哪些对象可以访问哪些资源，以及以何种方式进行访问。 强制访问控制（MAC）： SELinux 引入了强制访问控制，这意味着即使在传统的自愿访问控制机制下具有访问权限的用户也受到 SELinux 策略的限制。 SELinux 在一些 Linux 发行版中已经被默认启用，它提供了额外的安全层，有助于防止未经授权的访问、减缓攻击传播和提高系统的整体安全性。

实际上就是你在某些地方访问某些东西时，权限被拒绝了，然后Log中有提示avc的警告，这个时候就需要进行添加avc权限来进行访问。

### 2.什么是avc权限

AVC权限通常指的是 Android 中的权限控制，其中 AVC 是 Access Vector Cache（访问向量缓存）的缩写。Android 使用了 Linux 内核，而 AVC 是 Linux 内核中用于强制访问控制（MAC）的一部分。Android 使用了 SELinux（Security-Enhanced Linux）来实现 MAC。

在 Android 中，AVC 权限用于限制应用程序对系统资源的访问。这包括文件、网络、硬件等资源。每个应用程序都有一个特定的安全上下文，AVC 权限通过安全上下文来控制应用程序对系统资源的访问权限。

AVC 权限的实现有助于提高 Android 系统的安全性，防止应用程序越权访问敏感信息或系统资源。开发人员在编写应用程序时需要遵循这些权限，以确保其应用程序在运行时能够按照设定的规则进行访问控制。

### 3.selinux设置

在rc文件中定义服务

```
service ivi.name-server /vendor/bin/name-server
    class main
    user root
    group root system
    disabled
    seclabel u:r:fdbx:s0           // 定义selinux策略 在启动Service前将seclabel设置为seclabel. 主要用于在rootfs上启动的service，比如ueventd, adbd.
在系统分区上运行的service有自己的SELinux安全策略，如果不设置，默认使用init的安全策略.
```

在fdbus.te文件中定义

```
type fdbx, domain, mlstrustedsubject;
type fdbx_exec, exec_type, vendor_file_type, file_type;

init_daemon_domain(fdbx)

allow fdbx self:udp_socket { create bind setopt getattr };
allow fdbx self:tcp_socket { create bind setopt listen getattr };
allow fdbx node:tcp_socket node_bind;
allow fdbx node:udp_socket node_bind;

allow fdbx self:netlink_route_socket { create nlmsg_read nlmsg_readpriv read write };
allow fdbx fdbx_socket:dir { add_name remove_name search write };
allow fdbx fdbx_socket:sock_file { create unlink write };

```

一开始没有添加avc相关权限，会报错

```
 type=1400 audit(0.0:40): avc: denied { getattr } for comm="host-server" lport=41983 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=udp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:40): avc: denied { getattr } for lport=41983 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=udp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:41): avc: denied { create } for comm="host-server" scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:41): avc: denied { create } for scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:42): avc: denied { setopt } for comm="host-server" scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:42): avc: denied { setopt } for scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:43): avc: denied { bind } for comm="host-server" scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:43): avc: denied { bind } for scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:44): avc: denied { node_bind } for comm="host-server" src=60000 scontext=u:r:fdbx:s0 tcontext=u:object_r:node:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:44): avc: denied { node_bind } for src=60000 scontext=u:r:fdbx:s0 tcontext=u:object_r:node:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:45): avc: denied { listen } for comm="host-server" lport=60000 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:45): avc: denied { listen } for lport=60000 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I auditd  : type=1400 audit(0.0:46): avc: denied { getattr } for comm="host-server" lport=60000 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
01-01 00:00:47.671   675   675 I host-server: type=1400 audit(0.0:46): avc: denied { getattr } for lport=60000 scontext=u:r:fdbx:s0 tcontext=u:r:fdbx:s0 tclass=tcp_socket permissive=1
```

scontext和tcontext都是安全上下文，分别称为主体和客体，主体一般都是进程，客体则是主体访问的资源。

缺少什么权限： { listen }权限，

谁缺少权限： scontext=u:r:fdbx:s0

对哪个资源缺少权限： tcontext=u:r:fdbx:s0

什么类型的资源： tclass=tcp_socket

完整的意思： fdbx进程fdbx类型的tcp_socket缺少listen权限。

所以添加：allow fdbx self:tcp_socket { create bind setopt listen getattr };



### 4.添加编译目录下SE

创建sepolicy目录下文件BoardConfig.mk

```
# Board specific SELinux policy variable definitions
$(warning "begin oem sepolicy")
SEPOLICY_PATH:= vendor/wkk/sepolicy
#BOARD_SEPOLICY_DIRS += vendor/wkk/sepolicy

PRODUCT_PUBLIC_SEPOLICY_DIRS := \
    $(PRODUCT_PUBLIC_SEPOLICY_DIRS) \
    $(SEPOLICY_PATH)/public 

PRODUCT_PRIVATE_SEPOLICY_DIRS := \
    $(PRODUCT_PRIVATE_SEPOLICY_DIRS) \
    $(SEPOLICY_PATH)/private \

BOARD_SEPOLICY_DIRS := \
    $(BOARD_SEPOLICY_DIRS) \
    $(SEPOLICY_PATH)/vendor 
```

然后在device底下的BoardConfig.mk添加编译wkk目录SE

```
-include vendor/wkk/BoardConfig.mk
-include vendor/wkk/*/BoardConfig.mk
```

### 5.例子，添加设备节点相关Se

首先声明设备节点的type，sepolicy/vendor/device.te

```
type gtyc_radio_device, dev_type;
```

然后再声明节点域

```
# radio
/dev/i2c-6(/.*)?                               u:object_r:wkk_radio_device:s0
```

最后通过log分析所缺少的权限进行添加，其中ioctls需要特别注意，它的权限添加要多一步，从log中分析缺少ioctlcmd=0x707，ioctlcmd=0x703，默认是没有707和703的，需要自己添加

```
05-21 02:15:59.396 10913 10913 I auditd  : type=1400 audit(0.0:3110): avc: denied { read write } for comm="HwBinder:10913_" name="i2c-6" dev="tmpfs" ino=17864 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.396 10913 10913 I HwBinder:10913_: type=1400 audit(0.0:3110): avc: denied { read write } for name="i2c-6" dev="tmpfs" ino=17864 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.396 10913 10913 I auditd  : type=1400 audit(0.0:3111): avc: denied { open } for comm="HwBinder:10913_" path="/dev/i2c-6" dev="tmpfs" ino=17864 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.396 10913 10913 I HwBinder:10913_: type=1400 audit(0.0:3111): avc: denied { open } for path="/dev/i2c-6" dev="tmpfs" ino=17864 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.396 10913 10913 I auditd  : type=1400 audit(0.0:3112): avc: denied { ioctl } for comm="HwBinder:10913_" path="/dev/i2c-6" dev="tmpfs" ino=17864 ioctlcmd=0x703 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.396 10913 10913 I HwBinder:10913_: type=1400 audit(0.0:3112): avc: denied { ioctl } for path="/dev/i2c-6" dev="tmpfs" ino=17864 ioctlcmd=0x703 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
 auditd  : type=1400 audit(0.0:3113): avc: denied { ioctl } for comm="HwBinder:10913_" path="/dev/i2c-6" dev="tmpfs" ino=17864 ioctlcmd=0x707 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
05-21 02:15:59.400 10913 10913 I HwBinder:10913_: type=1400 audit(0.0:3113): avc: denied { ioctl } for path="/dev/i2c-6" dev="tmpfs" ino=17864 ioctlcmd=0x707 scontext=u:r:hal_broadcastradio_default:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
```

/sepolicy/vendor/hal_broadcastradio_default.te

```
#============= hal_broadcastradio_default ==============
allow hal_broadcastradio_default gtyc_radio_device:chr_file { read write ioctl open };
allowxperm hal_broadcastradio_default gtyc_radio_device:chr_file ioctl { i2c_ioctls };
```

/sepolicy/vendor/ioctl_defines

```
# ==============================================

##########################
#
define(`I2C_SLAVE', `0x0703')
define(`I2C_RDWR', `0x0707')
```

/sepolicy/vendor/ioctl_macros

```
# ==============================================
# ==============================================

define(`i2c_ioctls', `{
  I2C_SLAVE
  I2C_RDWR
}')
```

单编SE命令进行验证

```
lunch之后单编selinux：  make selinux_policy
```