## Android init.rc

Android Init 语言由四大类语句组成，它们是 Actions、Commands、Services 和 Options。

所有这些都是面向行的，由空格分隔的标记组成。 c 样式的反斜杠转义可用于将空格插入到标记中。 双引号也可用于防止空格将文本分成多个标记。 反斜杠，当它是一行的最后一个字符时，可以用于换行。

以 # 开头的行（允许前导空格）是注释。

Actions 和 Services 隐式声明了一个新部分。 所有Commands或Options都属于最近声明的部分。 第一部分之前的Commands或Options将被忽略。

Actions 和Services 具有唯一的名称。 如果第二个 Action 或 Service 被声明为与现有的同名，则将其作为错误忽略。 （???我们应该覆盖而不是）

### Actions

Actions 是命名的命令序列。 Actions 有一个触发器，用于确定动作何时发生。 当发生与Actions 的触发器匹配的事件时，该Actions 将添加到待执行队列的尾部（除非它已经在队列中）。

队列中的每个 action 都按顺序出队，并且该动作中的每个命令都按顺序执行。 Init 在活动中的命令执行“之间”处理其他活动（设备创建/销毁、属性设置、进程重 启）。

命令采取以下形式：

```
on <trigger>
   <command>
   <command>
   <command>
```

### Services

服务是在它们退出时启动并（可选）重新启动的程序。 服务采取以下形式：

```
service <name> <pathname> [ <argument> ]*
   <option>
   <option>
   ...
```

### Options

选项是服务的调节器。他们影响init进程如何并且何时运行这个服务。

```
 critical
    这是一个设备关键服务。如果他在四分钟内存在超过四次，设备将会重启进入恢复模式。
  
  disabled
    这个服务将不能与他的类自动启动。他必须通过名称被显示启动。
  
  setenv <名称> <值>
    在启动进程中设置环境变量<名称>到<数值>
  
 socket <name> <type> <perm> [ <user> [ <group> [ <seclabel> ] ] ]
   创建一个unix域套接字，命名为 /dev/socket/<name>，并且传递他的文件描述符fd到启动进程中。
   <type>必须是"dgram","stream"或者是"seqpacket"。
   User和group默认为0。
   'seclabel'是这个套接字的SELinux安全上下文。
   他默认为服务安全上下文，由seclabel指定或者是基于服务可执行文件安全上下文计算得来。
 
 user <username>
   在运行这个服务之前改为username(用户名称)。
   当前默认为root.目前，如果你的进程需要linux功能，那么你不能使用这个命令。你必须在进程中
   请求功能但依然root，然后降级到你期望的uid。
 
 group <groupname> [ <groupname> ]*
   在运行这个服务之前修改为groupname。在第一个之前的组名称被用来设置进程的追加的组（通过setgrooups()）
   。目前默认为root。
 
 seclabel <seclabel>
   在执行这个服务之前改为seclabel。主要是从rootfs等中被services使用。
   位于系统分区的services可以基于他们的文件安全上下文使用策略定义的转换。
   如果未被指定或者是在策略中没有转换被定义，默认为初始化上下文。
 
 oneshot
   当他退出的时候不要重启服务。
 
 class <name>
   为服务指定一个类名称。位于一个命名的类中的所有服务一起被启动或停止。
   如果服务未被class选项指定，则该服务位于类'default'中。
 
 onrestart
   当services重启的时候运行一个命令。
 
 writepid <file...>
   当子进程被创建的时候，将子进程的pid写入到给定的文件中。意味着cgroup/cpuset
   用法。
```

### 触发器

触发器是可用于匹配某些类型的字符串 事件并用于导致动作发生。

**boot** 这是 init 启动时将发生的第一个触发器 （在 /init.conf 加载后）

**<name>=<value>** 设置属性 <name> 时会发生这种形式的触发器 到特定值 <value>。

**device-added-<path>** **device-removed-<path></pre>** 添加设备节点时会发生这些形式的触发器 或删除。

**service-exited-<name>** 这种形式的触发器在指定的服务退出时发生。

```
on boot
# basic network init
    ifup lo
    hostname localhost
    domainname localdomain

# set RLIMIT_NICE to allow priorities from 19 to -20
    setrlimit 13 40 40

# Define the oom_adj values for the classes of processes that can be
# killed by the kernel.  These are used in ActivityManagerService.
    setprop ro.FOREGROUND_APP_ADJ 0
    setprop ro.VISIBLE_APP_ADJ 1
...
```

### 命令

```
exec <path> [ <argument> ]*
   fork 并执行一个程序 (<path>)。这将阻塞直到
   程序完成执行。最好避免执行
   与内置命令不同，它冒着获取的风险
   初始化“卡住”。 （？？？也许应该有一个超时？）

export <name> <value>
   将环境变量 <name> 设置为等于 <value> 在
   全局环境（将被所有进程继承
   此命令执行后启动）

ifup <interface>
   使网络接口 <interface> 联机。

import <filename>
   解析一个初始化配置文件，扩展当前配置。

hostname <name>
   设置主机名。

chdir <directory>
   更改工作目录。

chmod <octal-mode> <path>
   更改文件访问权限。

chown <owner> <group> <path>
   更改文件所有者和组。

chroot <directory>
  更改进程根目录。

class_start <serviceclass>
   启动指定类的所有服务，如果它们是
   尚未运行。

class_stop <serviceclass>
   停止指定类的所有服务，如果它们是
   目前正在运行。

domainname <name>
   设置域名。

insmod <path>
   将模块安装在 <path>

mkdir <path> [mode] [owner] [group]
   在 <path> 处创建一个目录，可选择使用给定的模式、所有者和
   团体。如果未提供，则使用权限 755 和
   由 root 用户和 root 组拥有。

mount <type> <device> <dir> [ <mountoption> ]*
   尝试将命名设备挂载到目录 <dir>
   <device> 可以是 mtd@name 的形式来指定一个 mtd 块
   设备名称。
   <mountoption>s 包括 "ro", "rw", "remount", "noatime", ...

restorecon <path>
   将 <path> 命名的文件恢复到指定的安全上下文
   在 file_contexts 配置中。
   init.rc 创建的目录不需要，因为这些是
   由 init 自动正确标记。

setcon <securitycontext>
   将当前进程安全上下文设置为指定的字符串。
   这通常仅在 early-init 中用于设置初始化上下文
   在任何其他进程开始之前。

setenforce 0|1
   设置 SELinux 系统范围的强制执行状态。
   0 是允许的（即记录但不拒绝），1 是强制的。

setkey
   待定

setprop <name> <value>
   将系统属性 <name> 设置为 <value>。

setrlimit <resource> <cur> <max>
   设置资源的 rlimit。

setsebool <name> <value>
   将 SELinux 布尔 <name> 设置为 <value>。
   <value> 可以是 1|true|on 或 0|false|off

start <service>
   如果服务尚未运行，则启动该服务。

stop <service>
   如果服务当前正在运行，则停止它的运行。

symlink <target> <path>
   在 <path> 处创建一个符号链接，其值为 <target>

sysclktz <mins_west_of_gmt>
   设置系统时钟基准（如果系统时钟在 GMT 计时，则为 0）

trigger <event>
   触发事件。用于将另一个动作排队
   行动。

wait <path> [ <timeout> ]
  轮询给定文件的存在并在找到时返回，
  或已达到超时。如果未指定超时，则
  当前默认为五秒。

write <path> <string> [ <string> ]*
   在 <path> 打开文件并写入一个或多个字符串
   用 write(2)
```