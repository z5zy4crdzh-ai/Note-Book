### Service

服务（Service)是Android中实现程序后台运行的解决方案，它非常适合去执行那些不需要和用户交互而且还要求长期运行的任务。服务的运行不依赖于任何用户界面，即使程序被切换到后台，或者用户打开了另外一个应用程序，服务仍然能够保持正常运行。

不过需要注意的是，服务并不是运行在一个独立的进程当中的，而是依赖于创建服务时所在的应用程序进程。与某个应用程序进程被杀掉时，所有依赖于该进程的服务也会停止运行。另外.也不要被服务的后台概念所迷惑，实际上服务并不会自动开启线程，所有的代码都是默认运行在主线程当中的。也就是说，我们需要在服务的内部手动创建子线程，并在这里执行具体的任务，否则就有可能出现主线程被阻塞住的情况。  1.service用于在后台完成用户指定的操作。service分为两种：  （a）started（启动）：当应用程序组件（如activity）调用startService()方法启动服务时，服务处于started状态。  （b）bound（绑定）：当应用程序组件调用bindService()方法绑定到服务时，服务处于bound状态。  2.startService()与bindService()区别：  (a)started service（启动服务）是由其他组件调用startService()方法启动的，这导致服务的onStartCommand()方法被调用。当服务是started状态时，其生命周期与启动它的组件无关，并且可以在后台无限期运行，即使启动服务的组件已经被销毁。因此，服务需要在完成任务后调用stopSelf()方法停止，或者由其他组件调用stopService()方法停止。  (b)使用bindService()方法启用服务，调用者与服务绑定在了一起，调用者一旦退出，服务也就终止，大有“不求同时生，必须同时死”的特点。  3. 开发人员需要在应用程序配置文件中声明全部的service，使用标签。

4.Service通常位于后台运行，它一般不需要与用户交互，因此Service组件没有图形用户界面。Service组件需要继承Service基类。Service组件通常用于为其他组件提供后台服务或监控其他组件的运行状态。  Service是一个专门在后台处理长时间任务的Android组件，它没有UI。它有两种启动方式，**startService和bindService**。

**startService**只是启动Service，启动它的组件（如Activity）和Service并没有关联，只有当Service调用stopSelf或者其他组件调用stopService服务才会终止。 当第一次调用的时候，方法顺序是：

构造方法——oncreate()——onStartCommand()

当第二次被调用的时候，直接调用onStartCommand()

结束：stopService():——>onDestory()

**bindService**方法启动Service，其他组件可以通过回调获取Service的代理对象和Service交互，而这两方也进行了绑定，当启动方销毁时，Service也会自动进行unBind操作，绑定到service上面的组件可以有多个，当发现所有绑定都进行了unBind时才会销毁Service。* 第一次调用：

构造方法——oncreate()——onBind()——onServiceConnected()

结束：unbindService():如果当前有Activity与Service相连——>onUnbind()——>onDestory()

Service的onCreate回调函数可以做耗时的操作吗？ 不可以， Service的onCreate是在主线程（ActivityThread）中调用的，耗时操作会阻塞UI

```xml
<service android:name=".MyService"
            android:foregroundServiceType="mediaProjection"
            android:enabled="true"
            android:exported="true">
</service>
```

2.我们为什么要使用服务？ 做一些需要长期执行的后台工作。

3.进程的优先级： 前台进程 > 可见进程 > 服务进程 > 后台进程 > 空进程

服务生命周期：

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/7dea9d3c81d8455a83295fb9a64e1649~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=389&h=507&s=95708&e=png&a=1&b=fae2c3)

服务类（这里设置了一个前台服务，下拉框有消息弹出）：

```java
public class MyService extends Service {
    private int count = 0;
    private boolean isRunning = false;

        @Override
        public void onCreate() {
            super.onCreate();
        }
        @Override
        public int onStartCommand(Intent intent, int flags, int startId) {
            System.out.println("执行了onStartCommand()");
            NotificationCompat.Builder mBuilder = new NotificationCompat.Builder(getApplicationContext()).setAutoCancel(true);// 点击后让通知将消失
            mBuilder.setContentText("您有一条新消息");
            mBuilder.setContentTitle("文件管理器");
            mBuilder.setSmallIcon(R.drawable.nm);
            mBuilder.setWhen(System.currentTimeMillis());//通知产生的时间，会在通知信息里显示
            mBuilder.setPriority(Notification.PRIORITY_DEFAULT);//设置该通知优先级
            mBuilder.setOngoing(false);//ture，设置他为一个正在进行的通知。他们通常是用来表示一个后台任务,用户积极参与(如播放音乐)或以某种方式正在等待,因此占用设备(如一个文件下载,同步操作,主动网络连接)
            mBuilder.setDefaults(Notification.DEFAULT_ALL);//向通知添加声音、闪灯和振动效果的最简单、最一致的方式是使用当前的用户默认设置，使用defaults属性，可以组合：
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                String channelId = "channelId" + System.currentTimeMillis();
                NotificationChannel channel = new NotificationChannel(channelId, getResources().getString(R.string.app_name), NotificationManager.IMPORTANCE_HIGH);
                manager.createNotificationChannel(channel);
                 mBuilder.setChannelId(channelId);
            }
            mBuilder.setContentIntent(null);
            startForeground(222, mBuilder.build());
            return super.onStartCommand(intent, flags, startId);
        }
        @Override
        public void onDestroy() {
            super.onDestroy();
            System.out.println("执行了onDestory()");
        }

        @Nullable
        @Override
        public IBinder onBind(Intent intent) {
            return null;
        }

}
```

启动服务：

```java
 startService(intent);
```

结束服务：

```java
stopService(stopIntent);
```

