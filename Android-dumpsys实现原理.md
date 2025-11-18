## Android-dumpsys实现原理



dumpsys是一个android里面的可执行文件。
从名字就可以看出，主要是用于dump 当前android system的一些信息。比如

```
activity（当前系统中所有activity的堆栈关系） 
alarm（当前系统中所有的Alarms）
```

等等，是一项分析问题，运行状态，使用情况等十分有效的手段。
查看所支持的dump选项

```dockerfile
 adb shell dumpsys -l
```

会列出所有可以dump的选项，比如想获取所有window相关的信息，可以使用命令

```gauss
 adb shell dumpsys window
```

实现逻辑

既然是一个可执行文件，必然是先找到其mk文件：/frameworks/native/cmds/dumpsys/Android.mk

```shell
LOCAL_SRC_FILES:= \
    dumpsys.cpp
...
LOCAL_MODULE:= dumpsys
include $(BUILD_EXECUTABLE)
```

dumpsys的源码结构其实很简单，只有一个dumpsys.cpp
/frameworks/native/cmds/dumpsys/dumpsys.cpp

```java
 int main(int argc, char* const argv[])
{
    ...
    sp sm = defaultServiceManager();
    ...
    Vector services;
    ...
    services = sm->listServices();
    ...
    const size_t N = services.size();

    for (size_t i=0; i service = sm->checkService(services[i]);
        ...
        int err = service->dump(STDOUT_FILENO, args);
        ...
    }

    return 0;
}
```

先通过defaultServiceManager()函数获得ServiceManager对象，然后根据dumpsys传进来的参数通过函数checkService来找到具体的service, 并执行该service的dump方法，达到dump service的目的。

gfxinfo实例讲解

因为笔者最近在研究手机跑2D/3D场景的性能评测，所以这里以dumpsys **gfxinfo**为例，说下它的大致流程。

具体服务

由上文可以知道，dumpsys的实现其实是根据参数来找到某个具体的service，然后执行其dump方法。
我们熟悉的系统service有ActivityManagerSerice（activity），WindowManagerService（window）等，那gfxinfo具体对应的是哪个service呢？
在文件：/frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java中有下面这段代码

```java
 public void setSystemProcess() {
      ...
      ServiceManager.addService("gfxinfo", new GraphicsBinder(this));
       ...
}
```

在ams里面，通过ServiceManager添加了一个name为gfxinfo的serivce叫GraphicsBinder，该service就是gfxinfo对应的service.

```java
    static class GraphicsBinder extends Binder {
        ...
        @Override
        protected void dump(FileDescriptor fd, PrintWriter pw, String[] args) {
            if (mActivityManagerService.checkCallingPermission(android.Manifest.permission.DUMP)
                    != PackageManager.PERMISSION_GRANTED) {
                pw.println("Permission Denial: can't dump gfxinfo from from pid="
                        + Binder.getCallingPid() + ", uid=" + Binder.getCallingUid()
                        + " without permission " + android.Manifest.permission.DUMP);
                return;
            }

            mActivityManagerService.dumpGraphicsHardwareUsage(fd, pw, args);
        }
    }

```

> 这里有一个权限检查，如果app想要dump系统信息必须要配置 **android.Manifest.permission.DUMP**权限，而该权限是三方app没办法使用的。

那作为一个三方app，我们有办法**绕过**该权限检查吗？这里按下不表，接着往后看。

ActivityThread

当我们执行adb shell dumpsys gfxinfo的时候，其实最后执行的是ams中的dumpGraphicsHardwareUsage该方法。

```java
 final void dumpGraphicsHardwareUsage(FileDescriptor fd,
            PrintWriter pw, String[] args) {
        ArrayList procs = collectProcesses(pw, 0, false, args);
        ...
       for (int i = procs.size() - 1 ; i >= 0 ; i--) {
            ProcessRecord r = procs.get(i);
            if (r.thread != null) {
                ...
                r.thread.dumpGfxInfo(tp.getWriteFd().getFileDescriptor(), args);
                ...
            }
        }
    }
```

可以看出，最后真正做dump动作的，其实是r.thread这个对象，这里直接给出r.thread其实就是ActivityThread中的内部类：ApplicationThread，省略代码的追查，让主线更加清晰。

collectProcesses函数的主要作用就是：根据参数找到对应的进程信息

> 该参数就是命令行中gfxinfo后面传进来的参数。
> 如果gfxinfo后面没有跟参数，则表示获取所有的Process信息
> 如果gfxinfo后面跟 包名， 则只获取指定报名的Process信息

文件：/frameworks/base/core/java/android/app/ActivityThread.java

```java
 public final class ActivityThread {
  ...
  private class ApplicationThread extends ApplicationThreadNative {
        ...
        @Override
        public void dumpGfxInfo(FileDescriptor fd, String[] args) {
            dumpGraphicsInfo(fd);
            WindowManagerGlobal.getInstance().dumpGfxInfo(fd);
        }
        ...
  }
}
```

Native-dumpGraphicsInfo实现

dumpGraphicsInfo是一个native函数实现在
/frameworks/base/core/jni/android_view_GLES20Canvas.cpp

```java
 static void
android_app_ActivityThread_dumpGraphics(JNIEnv* env, jobject clazz, jobject javaFileDescriptor) {
#ifdef USE_OPENGL_RENDERER
    int fd = jniGetFDFromFileDescriptor(env, javaFileDescriptor);
    android::uirenderer::RenderNode::outputLogBuffer(fd);
#endif // USE_OPENGL_RENDERER
}
```

/frameworks/base/libs/hwui/RenderNode.cpp

```java
 void RenderNode::outputLogBuffer(int fd) {
    DisplayListLogBuffer& logBuffer = DisplayListLogBuffer::getInstance();
    ...
    FILE *file = fdopen(fd, "a");

    fprintf(file, "\nRecent DisplayList operations\n");
    logBuffer.outputCommands(file);

    String8 cachesLog;
    Caches::getInstance().dumpMemoryUsage(cachesLog);
    fprintf(file, "\nCaches:\n%s", cachesLog.string());
    ...
}
```

可以看出是打印了一些RenderNode的信息，包括memory和cache。

Native-ThreadedRenderer实现

/frameworks/base/core/java/android/view/WindowManagerGlobal.java

```java
 public void dumpGfxInfo(FileDescriptor fd) {
    ...
    HardwareRenderer renderer =
                  root.getView().mAttachInfo.mHardwareRenderer;
    if (renderer != null) {
           renderer.dumpGfxInfo(pw, fd);
     }
    ...
}
```

HardwareRenderer是一个抽象类，具体的实现是在
/frameworks/base/core/java/android/view/ThreadedRenderer.java

```java
 @Override
    void dumpGfxInfo(PrintWriter pw, FileDescriptor fd) {
        pw.flush();
        nDumpProfileInfo(mNativeProxy, fd);
    }
```

nDumpProfileInfo也是一个native函数，也是去抓取一些graphic信息，不再做详细讲解。
到这里，dumpsys gfxinfo的流程就基本讲解完了。

总结

dumpsys的实现其实是通过serviceManager拿到对应的service信息，然后执行该service的dump函数。
需要注意的是：每个service都有一个权限检查，需要系统app才可以dump。


