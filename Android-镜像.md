## Android 镜像

对于安卓开发而言，了解各镜像的意义、内容以及如何制作，有极大的意义。

注意，ROM中的5个镜像文件的扩展名都是img，但其格式却不同，也就是说不能使用同一种方法对其进行格式解析。

### 系统镜像（System.img）

系统镜像用于存储Android系统的核心文件，将其解压出来，就是设备中`/system`目录，里面包含了Android系统主要的目录和文件。一般这些文件是不允许修改的。

系统镜像对应的文件名一般叫`system.img`。

当然，系统镜像的文件可以任意命名，之所以叫`system.img`是为了与生成镜像文件之前的system目录保持一致，这样比较容易与其他类型的镜像文件区分。

`system.img`可以添加：

-   Android系统应用
-   更多的library

为了搞清楚`system.img`镜像中的内容，可以将其解压：

-   旧版的镜像是`yaffs`格式的（通过`mkyaffs2image`工具制作的），可以使用`unyafss`命令对其解压。

> Android源代码中并未提供该命令，所以读者可以到 <http://code.google.com/p/unyaffs/downloads/list> 下载unyaffs的二进制程序和源代码。

```
unyaffs system.img
```

如果对编译Android源代码生成的system.img文件执行上面的命令，可以完美的将system.img文件还原成system目录，会从system目录中看到相应的子目录，例如，/system/app、/system/lib等，实际上，system.img文件就是`out/target/product/generic/system`中的文件压缩生成的。

-   另外，高版本Android的system.img通常是ext4格式的文件系统镜像（通过`make_ext4`工具制作），可以使用`simg2img`工具进行转换后挂载。

由于system.img是压缩格式，所以并不能直接使用mount命令挂载。在编译Android 源代码后会在Android源代码目录`/out/host/linux-x86/bin`目录生成一个simg2img命令行工具

> 建议将该目录加到PATH环境变量中，因为当中的各种命令行工具会被经常使用。

`simg2img`可以通过如下的命令将`system.img`转化为普通的Linux镜像文件(`system.img.raw`)；

文件列表如下：

| 目录           | 意义                                                         |
| -------------- | ------------------------------------------------------------ |
| app            | 存放一般的apk文件。                                          |
| bin            | 存放一些Linux的工具，但是大部分都是toolbox的链接.            |
| etc            | 存放系统的配置文件。                                         |
| fonts          | 存放系统的字体文件。                                         |
| framework      | 存放系统平台所有jar包和资源文件包。                          |
| lib            | 存放系统的共享库。                                           |
| media          | 存放系统的多媒体资源，主要是铃声。                           |
| priv-app       | android4.4开始新增加的目录，存放系统核心的apk文件。          |
| tts            | 存放系统的语言合成文件。                                     |
| usr            | 存放各种键盘布局，时间区域文件。                             |
| vendor         | 存放一些第三方厂商的配置文件、firmware以及动态库。           |
| xbin           | 存放系统管理工具，这个文件夹的作用相当于标准Linux文件系统中的sbin. |
| build.prop文件 | 系统属性的定义文件。                                         |

将`system.img.raw`挂载出来后，该目录中的内容实际上与`system.img`中的内容完全一样，现在可以任意修改目录中的内容，再进行打包以达到更新system.img的目的。

> 例如，添加或替换目录中的apk文件，或更换开机动画。

在修改完系统镜像后，还需要使用`make_extfs`命令将挂载目录重新生成`system.img`文件（EXT4文件系统）。

我们可以在Linux终端执行如下的命令生成`system.img`文件。

```
make_ext4fs -s -l 1024M -a system system.img /mnt/system
```

在执行make_ext4fs 命令使用了3个命令行参数，这些参数的含义如下：

-   `-s`：生成Spare格式的镜像。这种格式的镜像文件的尺寸会更小，但无法直接使用mount命令挂载。要想挂载Spare格式的镜像文件，需要首先使用simg2img命令按着前面描述的方式进行转换。如果不加-s参数，生成的system.img文件是可以直接通过mount挂载。不过不管是不是Spare格式的系统镜像文件，Nexus 7都可以使用（其他的Android设备应该也可以），但建议生成Spare格式的镜像文件，因为这样的镜像文件尺寸更小。
-   `-l` : 镜像的尺寸。该参数指定的值并不是生成镜像文件(r如system.img)的实际尺寸，而是文件系统的尺寸。这有些类似在Windows中建立的心得逻辑分区，而该参数指定的值就是逻辑分区的尺寸，生成的镜像文件的尺寸不能大于文件系统的尺寸。例如官方提供的用于Nexus 7的system.img文件（Spare格式的镜像文件）的尺寸大小越是480M，
-   `-a`: 指定挂载点，这里是system.

重新生成经过修改的system.img文件后，首先让设备进入Bootloader模式，然后执行下面的命令即可刷机：

```
fastboot flash system system.img
```

### 用户数据镜像（userdata.img）

用户镜像用来存储与用户相关的数据，一般对应的文件名是`userdata.img`（也可以是任何文件名，为了方便，我们将userdata称为用户镜像文件）。

这些数据大多都是有用户在使用Android设备的过程中产生的，例如，通过Google play安装的第三方APK程序，用户的配置文件等。当然，在制作ROM时，也可以将部分数据放到userdata.img中。

> 例如，如果允许用户使用普通的方法卸载ROM内置的应用，就可以将APK文件放到userdata.img文件中 (这里是普通的应用程序，而system.img放入的是系统应用程序)

`userdata.img`有如下两个功能：

-   封装与用户相关的文件（如果是APK程序，还允许卸载这些程序），并连同ROM一起发布，或单独刷userdata.img文件。
-   规定Android设备存储空间的大小。

在Android设备中可供用户操作的存储区域通常有如下：

-   RAM ：RAM就是传统意义上的内存，与PC的内存是一个概念，只有在通电时才能存储数据，断点后所有数据将自动消失，所有要运行的程序都需要调用RAM。
-   存储空间：现在所有的Android设备都有都带有一定大小的内部存储器（嵌入到芯片上，类似于内部嵌入一个SD卡），用于存储一些随机器发布的系统和应用程序。而PC除了RAM，就是硬盘了。
-   外部存储器（通常是SD卡）：有的Android系统加入了OTG(On-The-Go)支持，所以通过OTG连接的U盘、移动硬盘也应属于外部存储器，有一些Android设备（如Nexus 7) 不支持插入SD卡。

Android系统通过Linux 文件系统将可用的存储空间划分成不同区域，`userdata.img`就属于`userdata`分区，该分区就是前面所说的存储空间。而剩余的内存空间就会将其作为外部存储器。

如果Android设备不支持外部存储器，`userdata.img`就不能太大，否则系统将无法利用剩余的空间映射SD卡（`/sdcard`，目录）。

学习`userdata.img`的第一步就是解剖他。方法与解剖system类似。

首先需要使用`simg2img`命令将`userdata.img`文件还原成非压缩格式的镜像文件，这样可以直接使用`mount`命令将`userdata.img`文件挂载到某个目录，进而查看`userdata.img`中的内容。

```
# 生成还原后的userdata.img.raw文件
simg2img userdata.img userdata.img.raw

# 挂载userdata.img.raw文件
mkdir -p /mnt/rom/userdata
mount  userdata.img.raw /mnt/rom/userdata
```

如果挂载成功，会在/mnt/rom/userdata 目录看到userdata.img 中的内容。

通常该目录除了“lost+found”(该目录一般为空，在系统非法关机时会存放一些文件) 系统目录外，什么都没有。

读者可以执行下面的命令查看当前挂载的用户镜像尺寸。

```
df -h
```

现在可以在`/mnt/rom/userdata`目录放一些目录或文件，例如，将`Test.apk`作为普通的Android应用放入`userdata.img`，如要在`/mnt/rom/userdata`目录建立一个app子目录，然后将Test.apk文件放入app目录即可。

在修改完镜像挂载分区以后，需要使用下面的命令重新打包，为了与userdata.img区别，在这里将该目录打包成了userdata.img.new。

> 要注意，在打包的过程中会确定用户镜像对应的空间大小，例如，下面的命令生成了最大为128M的用户镜像文件（userdata.img.new,ext4格式的镜像文件）。

```
make_ext4fs -s -l 128M -a data userdata.img.new /mnt/rom/userdata
```

> 注意：用户镜像占用的存储空间不能超过Android设备的内部存储器的总尺寸，否则即使成功刷机，Android设备也可能会启动失败，即使启动也由于SD卡无法挂载而出现要求输入密码（实际上就是映射失败）的情况。

参数说明：

-   加上"-s"命令行，参数就表示生成的userdata.img.new 文件是压缩格式，不能直接使用mount命令挂载，需要按着签名的而方法通过simg2img命令来还原才能挂载到某一目录。
-   “-a”命令行参数后面的是文件系统，这里需要制定data。

接下来可以使用下面的命令将`userdata.img.new` 文件刷到Android设备上（加上目录Android设备正处于正常的启动状态，并通过USB线PC相连）。

> 注意：在刷userdata.img.new文件之前，一定 要备份Android设备上已安装的应用程序、配置和其他数据，否则这些数据将全部丢失（SD卡中的数据不会丢失）。

```
adb reboot bootloader

fastboot flash userdata userdata.img.new

fastboot reboot
```

上面的命令在刷完userdata.img.new 后，会重启Android设备。通过“设置”->"存储"可以查看使用情况。

### 内存磁盘镜像（ramdisk.img）

内存磁盘镜像存储了Linux内核启动时要装载的核心文件，通常的镜像文件名为ramdisk.img。

之所以称`ramdisk.img`为内存磁盘镜像，是因为`ramdisk.img`中的文件映射的实际上都是内存中的文件，也就是说，即使有权修改`init.rc`等文件，也只是修改原始文件在内存中的镜像，重新启动Android设备后，又会恢复到最初的状态。而修改这些文件的唯一方法就是重新制作`ramdisk.img`文件，并连同Linux内核二进制文件（`zImage`）生成`boot.img`文件，并且刷入设备中才可以生效。

ramdisk.img是boot.img中重要的组成部分之一，尽管`ramdisk.img`需要放在Linux内核镜像（`boot.img`）中，但却属于Android源代码的一部分。也就是说，在编译Android 源代码后，会生成一个`ramdisk.img`文件，其实该文件就是root目录压缩后生成的文件。

`ramdisk.img`文件中封装的内容是Linux内核与Android系统杰出的第一批文件，其中有一个非常重要的init命令（在root目录中可以找到该命名文件），该命令用于读取`init.rc`以及相关配置文件中的初始化命令。

其实`ramdisk.img`文件只是一个普通的zip压缩文件，可以直接使用`gunzip`命令解压，不过解压后并不是原文件和目录，而是有cpio命令备份的文件，所以还需要使用cpio继续还原。

假设`ramdisk.img`文件在当前目录下，则还原ramdisk.img文件的命令如下：

```
mkdir ramdisk
cp ramdisk

gunzip -c ../ramdisk.img > ../ramdisk.cpio
cpio -i < ../ramdisk.cpio
```

也可以将最后两行命令合成如下的一行。

```
gunzip -c ../ramdisk.img | cpio -i
```

执行上面的命令后，就会在`ramdisk`目录中看到内存磁盘镜像还原后的目录结构，如果现在要修改`init.rc`等配置文件，可以自己在ramdisk目录中找到相应的文件并修改。例如，有Linux的瑞士军刀之称`busybox`，可以放到`ramdisk`中的`sbin`目录下。这样在Recovery模式下就可以使用busybox命令完成很多操作了。

修改完ramdisk目录的内容后，就需要使用下面的命令将ramdisk目录重新生成ramdisk.img文件。

为了与原来的ramdisk.img文件有所区别，这里生成了ramdisk.img.new文件，在执行下面的命令之前，要保证Linux终端的当前目录是ramdisk。

```
cd XX # ramdisk目录
mkbootfs . | minigzip > ../ramdisk.img.new
```

### Linux内核镜像(boot.img)

Linux内核镜像包含了内核二进制（`zImage`）和内存磁盘镜像（`ramdisk.img`）。

一般对应的镜像文件是`boot.img`(也可以是任何其他的名字)。

由于`ramdisk.img`中包含的init命令是与Linux内核第一个交互的程序，所以在`boot.img`中需要同时包含Linux内核（`zImage`）和`ramdisk.img`。

当Linux内核调用init后，系统就会根据`init.rc`及其相关文件的代码对整个Android系统进行初始化。其中主要的初始化工作就是建立如`/system`、`/data`等系统目录，然后使用mount命令将相应的镜像挂载到这些目录上。

Android源代码经过编译后，也可以在其中找到对`boot.img`解压和生成`boot.img`文件的命令。

其中`unpackbooting`为解压命令，`mkbooting`命令可以将`zImage`和`ramdisk.img`文件合并成`boot.img`。

下面先来用`unpackbooting`命令将boot.img解压，再看看`boot.img`是不是有`zImage`和`ramdisk.img`文件组成的。

假设`boot.img`文件（我们可以使用从其他Rom压缩包中获得的boot.img,也可以使用通过Android源代码生成的boot.img）在当前目录中，使用下面的命令可以将boot.img文件解压到boot目录中。

```
mkdir boot
cd boot 
unpackbootimg -i  ../boot.img
```

执行完上面的命令后，会发现boot目录中多了几个文件，其中有两个主要的文件：`boot.img-zImage`和`boot.img-ramdisk.gz`。

前者是Linux 内核文件（与zImage文件完全一样），后者是内存磁盘镜像（与ramdisk.img完全一样）。为了证明`boot.img-ramdisk.gz` 与`ramdisk.img`文件完全相等，可以使用下面的命令将`boot.img-ramdisk.gz`解压到ramdisk目录。

```
mkdir ramdisk
cd ramdisk
gunzip -c ../boot.img-ramdisk.gz | cpio  -i
```

目录结构与`ramdisk.img` 一样。

如果想向init.rc或其他文件中添加新的内容，或在内存磁盘镜像中添加新的命令，可以修改刚才由boot.img-ramdisk.gz 文件解压生成的ramdisk目录中的相应文件和目录的内容，然后使用下面的命令重新将ramdisk目录中的相应文件和目录的内容，然后使用下面的命令重新将ramdisk打包成boot.img-ramdisk.gz.new(当前目录是ramdisk)。

```
mkbootfs . | minigzip > ../boot.img-ramdisk.gz.new
```

接下来回到上一层目录，然后使用下面的命令将`boot.img-zImage` 和`boot.img-ramdisk.gz.new`文件合并成`boot.img.new`文件（为了区分`boot.img`，这里生成了`boot.img.new`文件）。

```
mkbootimg --kernel boot.img-zImage --ramdisk boot.img-ramdisk.gz.new -o boot.img.new
```

如果想修改Linux内核，需要下载Linux内核源代码（官方和CM都提供了相应Android设备的Linux内核源代码）

接下来退到上一层目录，然后使用下面的命令将boot.img-zImage 和boot.img-ramdisk.gz.new

现在可以使用下面的命令重新刷Linux内核（加上Android系统处于正常启动状态，并通过USB线和PC相连）。不过要注意的是Linux内核必须与当前Android设备匹配，否则刷完后Android设备有可能起不来。刷Linux内核不会对系统（`system.img`）和用户数据（`userdata.img`）造成任何影响。

```
adb reboot bootloader

fastboot flash boot boot.img,new 

fastboot reboot
```

重启Android设备后，如果我们修改了Linux内核和内存磁盘镜像，就会立刻生效。

> 注意：`boot.img`解压后，除了生成`boot.img-zImage`和`boot.img-ramdisk.gz`文件外，还会生成一些其他的文件，如`boot.img-base`、`boot.img-cmdline`、`boot.img-pagesize`等，这些文件都是一些配置文件。
>
> 例如`boot.img-cmdline`文件中包含了Linux内核启动时传入的参数。通常并不需要管这些文件，只需要保持默认值即可)。

### 设备树镜像（dtbo.img）

熟悉嵌入式Linux的读者应该知道，现在的BootLoader（通常是uboot）一般与dtb文件相配合，以告知Linux有关驱动节点。

因此，这个一般和`boot.img`相互作用，由于一般手机用户很难修改这一部分的内容，因此不做展开。

### Recovery镜像（recovery.img）

Recovery镜像只用于刷机，通常的镜像文件名为：`receovery.img`。

在学习定制Recovery.img之前，先了解recovery.img到底是个什么东西。

> 关于如何更深入定制recovery.img，请参考recovery的源代码。

从本质上说，`recovery.img`和`boot.img`基本一样。这就意味着，`recovery.img`也是Linux内核（`zImage`）和内存磁盘镜像（`ramdisk.img`）组成的。这两个镜像中的Linux内核是完全一样的，区别只是ramdisk.img中的少部分文件存在差异：

**最主要的差异是recovery.img和ramdisk.img中的sbin目录中多了一个recovery命令进入Recovery主界面，而不会正常启动Android系统。**

实现的原理是：

-   Recovery.img和boot.img在自己的分区各自有一个Linux内核（zImage），彼此的Linux内核调用的init命令解析的init.rc及其相关文件的内容有一定的差异。
-   而Bootloader根据用户的选择决定使用boot.img中Linux内核，还是使用Recovery.img中的Linux内核启动系统。如果使用前者，Android系统就会正常启动，如果使用后者，就会进入Recovery选择菜单，所以recovery.img和boot.img的第二个差异就是其中的init.rc及其相关配置文件的内容略有不同。

从前面的描述还可以看出，`recovery.img`和`boot.img`其实都是一个最小的运行系统，也就是说他们都各自带一个满足最低要求的运行环境（`ramdisk.img`）。`boot.img`利用这个运行环境监理更大的运行环境（`system.img`） ，而`recovery.img`就直接使用了这个运行环境进行基本的操作（复制文件、删除文件、加压文件、mount等），这些操作也就是Recovery模式下刷机要进行的一些操作。

既然了解了`recovery.img`是什么东西，那么就可以解压`recovery.img`，并且重写生成`recovery.img`文件。

假设`recovery.img`文件在当前目录下，解压`recovery.img`：

```
mkdir recovery

cd recovery

uppackbootimg -i ../recovery.img
```

执行下面的命令会在recovery目录下生成如下5个文件：

```
recovery.img-zImage

recovery.img-ramdisk.gz

recovery.img-cmdline

recovery.img-pagesize

recovery.img-base
```

其中前两个分别为recovery.img中的Linux内核和内存磁盘镜像。可以使用下面的命令解压recovery.img-ramdisk.gz文件：

```
mkdir ramdisk

cd ramdisk

gunzip -c ../recovery.img-ramdisk.gz | cpio -i
```

现在回到上一层目录，最后按着4.2.4小节的方法重新生成内存镜像文件（这里为Recovery.img-randisk.gz.new），并使用下面的命令重新生成Recovery镜像（这里为recovery.img.new ）。

重新生成Recovery镜像文件：

```
mkbootimg --kernel recovery.img-zImage --ramdisk recovery.img-ramdisk.gz.new -o recovery.img.new
```

现在可以使用下面的命令重新刷Recovery（加上Android 处在正常启动状态），并进入Recovery模式。

```
adb reboot bootloader

fastboot flash recovery recovery.img.new

fastboot reboot

adb reboot recovery
```

### 缓存镜像（cache.img）

缓存镜像用于存储系统或用户应用产生的临时数据，通常的镜像文件名为chche.img。

一般ROM并不需要包含缓存镜像，不过在这里还是介绍一下如何制作和刷缓存镜像。

缓存镜像实际上就是一个空的ext4格式的文件系统镜像，可以使用下面的命令生成缓存镜像。

```
mkdir -p /mnt/rom/cache

make_ext4fs -s -l 256M -a cache cache.img /mnt/rom/cache
```

可以使用下面的abd命令刷缓存镜像：

```
adb reboot bootloader
fastboot flash cache cache.img
fastboot reboot
```