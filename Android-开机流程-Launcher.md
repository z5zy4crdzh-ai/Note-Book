### Launcher

Launcher 概述 系统启动的最后一步是启动一个应用程序来显示系统中已经安装的应用程序，这个应用程序就叫做 Launcher。Launcher 在启动过程中会请求 PackageManagerService 返回系统中已经安装的应用程序信息，并将这些信息封装成一个快捷图标列表显示在系统屏幕上，这样用户就可以通过点击这些快捷图标来启动相应的应用程序。

通俗的讲，Launcher 就是 Android 系统的桌面， 它的作用主要有以下两点：

作为 Android 系统的启动器，用于启动应用程序； 作为 Android 系统的桌面，用于显示和管理应用程序的快捷图标或者其他桌面组件； 2 Launcher 启动过程 SystemServer 进程在启动的过程中会启动 PackageManagerService，PackageManagerService 启动后会将系统中的应用程序安装完成，在此之前已经启动的 ActivityManagerService 会将 Launcher 启动起来。

Launcher 的启动分为三个部分：

SystemServer 完成启动 Launcher 的 Activity 的相关配置； Zygote 进程 fork 出 Launcher 进程； 进入 ActivityThread.main 函数，最终完成 Launcher 的 Activity.onCreate 操作； 第一阶段 完成 Launcher 的相关配置

![图1](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/535647b3c98e4ed4bdd243c4e12c51dc~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=3879&h=1972&s=307887&e=png&b=ffffff)

#### startOtherServices()：

在 `SystemServer.startOtherServices` 方法中调用 `ActivityManagerService.systemReady`方法，`Launcher` 进程的启动就是从这里开始的

```
// /frameworks/base/services/java/com/android/server/SystemServer.java
private void startOtherServices() {
    ...
    mActivityManagerService.systemReady(() -> { // 1
        Slog.i(TAG, "Making services ready");
        traceBeginAndSlog("StartActivityManagerReadyPhase");
        mSystemServiceManager.startBootPhase(
            SystemService.PHASE_ACTIVITY_MANAGER_READY);
        traceEnd();
        }
       ...                                
    ）
}                                                      
```

#### systemReady()：

\build\android\frameworks\base\services\core\java\com\android\server\am\ActivityManagerService.java

ActivityManagerService的**systemReady**()正是Launcher启动的入口。在其中会去调用**startHomeOnAllDisplays**()来启动Launcher.

```
public void systemReady(final Runnable goingCallback, TimingsTraceLog traceLog) {
        traceLog.traceBegin("PhaseActivityManagerReady");
        synchronized(this) {
            if (mSystemReady) {
                // If we're done calling all the receivers, run the next "boot phase" passed in
                // by the SystemServer
                if (goingCallback != null) {
                    goingCallback.run();
                }
                return;
            }
            ...
        Slog.i(TAG, "System now ready");
            // AMS就绪
        EventLog.writeEvent(EventLogTags.BOOT_PROGRESS_AMS_READY, SystemClock.uptimeMillis());
            ...
        if (bootingSystemUser) {  
               // 调用startHomeOnAllDisplays来启动Launcher
                mAtmInternal.startHomeOnAllDisplays(currentUserId, "systemReady");
            }
 }
```

#### mAtmInternal：

\build\android\frameworks\base\services\core\java\com\android\server\wm\ActivityTaskManagerService.java

这里的mAtmInternal是**ActivityTaskManagerInternal**，是一个抽象类，真正的实现是在ActivityTaskManagerService的内部类LocalService中，ActivityTaskManagerService的内部类LocalService,它继承自ActivityManagerInternal，确实有startHomeOnAllDisplays()方法。这里最终调用到RootActivityContainer 的startHomeOnDisplay()方法

```
   final class LocalService extends ActivityTaskManagerInternal {
       ...
          @Override
        public boolean startHomeOnAllDisplays(int userId, String reason) {
            synchronized (mGlobalLock) {
                return mRootWindowContainer.startHomeOnAllDisplays(userId, reason);
            }
        }

       ...
   }
```

#### startHomeOnAllDisplays()：

\build\android\frameworks\base\services\core\java\com\android\server\wm\RootActivityContainer.java

**RootActivityContainer**的作用是：调用packageManagerService中去查询手机系统中已安装的所有的应用，哪一个符合launcher标准，且得到一个Intent对象，并交给**ActivityStarter**。

获取的displayId为DEFAULT_DISPLAY， 通过getHomeIntent 来构建一个category为CATEGORY_HOME的Intent，表明是一个符合launcher应用的Intent；然后通过resolveHomeActivity()从系统所用已安装的引用中，找到一个符合该Intent的Activity，最终调用startHomeActivity()来启动Activity

```
boolean startHomeOnDisplay(int userId, String reason, int displayId, boolean allowInstrumenting,
            boolean fromHomeKey) {
        // Fallback to top focused display if the displayId is invalid.
        if (displayId == INVALID_DISPLAY) {
            displayId = getTopDisplayFocusedStack().mDisplayId;
        }

        Intent homeIntent = null;
        ActivityInfo aInfo = null;
        if (displayId == DEFAULT_DISPLAY) {
            // 表明是构建一个符合launcher应用的Intent
            homeIntent = mService.getHomeIntent();
            // 通过PMS从系统所用已安装的引用中，找到一个符合homeIntent的Activity
            aInfo = resolveHomeActivity(userId, homeIntent);
        } else if (shouldPlaceSecondaryHomeOnDisplay(displayId)) {
            Pair<ActivityInfo, Intent> info = resolveSecondaryHomeActivity(userId, displayId);
            aInfo = info.first;
            homeIntent = info.second;
        }
        if (aInfo == null || homeIntent == null) {
            return false;
        }

        if (!canStartHomeOnDisplay(aInfo, displayId, allowInstrumenting)) {
            return false;
        }

        // Updates the home component of the intent.
        homeIntent.setComponent(new ComponentName(aInfo.applicationInfo.packageName, aInfo.name));
        homeIntent.setFlags(homeIntent.getFlags() | FLAG_ACTIVITY_NEW_TASK);
        // Updates the extra information of the intent.
        if (fromHomeKey) {
            homeIntent.putExtra(WindowManagerPolicy.EXTRA_FROM_HOME_KEY, true);
        }
        // Update the reason for ANR debugging to verify if the user activity is the one that
        // actually launched.
        final String myReason = reason + ":" + userId + ":" + UserHandle.getUserId(
                aInfo.applicationInfo.uid) + ":" + displayId;
        // 启动launcher
        mService.getActivityStartController().startHomeActivity(homeIntent, aInfo, myReason,
                displayId);
        return true;
    }
```

#### resolveHomeActivity()：

\build\android\frameworks\base\services\core\java\com\android\server\wm\RootActivityContainer.java

通过Binder跨进程通知PackageManagerService从系统所用已安装的引用中，找到一个符合HomeItent的Activity

```
ActivityInfo resolveHomeActivity(int userId, Intent homeIntent) {
        final int flags = ActivityManagerService.STOCK_PM_FLAGS;
        final ComponentName comp = homeIntent.getComponent();
        ActivityInfo aInfo = null;
        try {
            if (comp != null) {
                // Factory test.
                aInfo = AppGlobals.getPackageManager().getActivityInfo(comp, flags, userId);
            } else {
                final String resolvedType =
                        homeIntent.resolveTypeIfNeeded(mService.mContext.getContentResolver());
              //  1.通过queryIntentActivities来查找符合HomeIntent需求Activities
              //  2.通过chooseBestActivity找到最符合Intent需求的Activity信息
                final ResolveInfo info = AppGlobals.getPackageManager()
                        .resolveIntent(homeIntent, resolvedType, flags, userId);
                if (info != null) {
                    aInfo = info.activityInfo;
                }
            }
        } catch (RemoteException e) {
            // ignore
        }

        if (aInfo == null) {
            Slog.wtf(TAG, "No home screen found for " + homeIntent, new Throwable());
            return null;
        }

        aInfo = new ActivityInfo(aInfo);
        aInfo.applicationInfo = mService.getAppInfoForUser(aInfo.applicationInfo, userId);
        return aInfo;
    }
```

#### startHomeActivity()：

\build\android\frameworks\base\services\core\java\com\android\server\wm\ActivityStartController.java

**ActivityStartController**.startHomeActivity()方法：这个类唯一的作用就是配置activity启动前的一些信息，并把这些信息传递给ActivityStart去做启动

```
void startHomeActivity(Intent intent, ActivityInfo aInfo, String reason, int displayId) {
        final ActivityOptions options = ActivityOptions.makeBasic();
        options.setLaunchWindowingMode(WINDOWING_MODE_FULLSCREEN);
        if (!ActivityRecord.isResolverActivity(aInfo.name)) {
            // The resolver activity shouldn't be put in home stack because when the foreground is
            // standard type activity, the resolver activity should be put on the top of current
            // foreground instead of bring home stack to front.
            options.setLaunchActivityType(ACTIVITY_TYPE_HOME);
        }
        options.setLaunchDisplayId(displayId);
        // obtainStarter方法返回一个 ActivityStarter对象，它负责 Activity 的启动
        mLastHomeActivityStartResult = obtainStarter(intent, "startHomeActivity: " + reason)
                .setOutActivity(tmpOutRecord)
                .setCallingUid(0)
                .setActivityInfo(aInfo)
                .setActivityOptions(options.toBundle())
                .execute();         // execute()会触发 ActivityStarter的execute方法
        mLastHomeActivityStartRecord = tmpOutRecord[0];
        final ActivityDisplay display =
                mService.mRootActivityContainer.getActivityDisplay(displayId);
        final ActivityStack homeStack = display != null ? display.getHomeStack() : null;
        if (homeStack != null && homeStack.mInResumeTopActivity) {
            // If we are in resume section already, home activity will be initialized, but not
            // resumed (to avoid recursive resume) and will stay that way until something pokes it
            // again. We need to schedule another resume.
            //如果home activity 处于顶层的resume activity中，则Home Activity 将被初始化，但不会被恢复（以避免递归恢复），
            //并将保持这种状态，直到有东西再次触发它。我们需要进行另一次恢复
            mSupervisor.scheduleResumeTopActivities();
        }
    }
```

#### ActivityStarter.execute()：

```
int execute() {
    ...
    if (mRequest.mayWait) {
        return startActivityMayWait(...)
    } else {
         return startActivity(...) 
    }
    ...
}

```

#### startActivity()：

\build\android\frameworks\base\services\core\java\com\android\server\wm\ActivityStarter.java

做一些其它的校验，包括后台启动activity，activity启动权限等

```
private int startActivity(IApplicationThread caller, Intent intent, Intent ephemeralIntent,
            String resolvedType, ActivityInfo aInfo, ResolveInfo rInfo,
            IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor,
            IBinder resultTo, String resultWho, int requestCode, int callingPid, int callingUid,
            String callingPackage, int realCallingPid, int realCallingUid, int startFlags,
            SafeActivityOptions options,
            boolean ignoreTargetSecurity, boolean componentSpecified, ActivityRecord[] outActivity,
            TaskRecord inTask, boolean allowPendingRemoteAnimationRegistryLookup,
            PendingIntentRecord originatingPendingIntent, boolean allowBackgroundActivityStart) {
    
    
    if (err == ActivityManager.START_SUCCESS && intent.getComponent() == null) {
            // We couldn't find a class that can handle the given Intent.
            // That's the end of that!          Activity没有在清单文件中注册！！！
            err = ActivityManager.START_INTENT_NOT_RESOLVED;
        }

        if (err == ActivityManager.START_SUCCESS && aInfo == null) {
            // We couldn't find the specific class specified in the Intent.
            // Also the end of the line.        Activity对应的java文件不存在！！！
            err = ActivityManager.START_CLASS_NOT_FOUND;
        }
```