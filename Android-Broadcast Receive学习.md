### Broadcast Receive

标准广播：**一种完全异步执行的广播**，所有的广播接收器都可以同时接收到这条广播，彼此没有先后之分，所有的接收者都是同等对待

有序广播：按照顺序执行的广播方式，同一个时刻只有一个广播接收器能够接收到广播，并且优先级高的广播接收器最先接收到广播，除此之外，接收到广播的接收器还可以截断正在传递的广播，后续的广播器就无法收到这条广播了

广播注册方式：动态注册，静态注册

静态注册（这里我自定义自己的广播）：

```xml
<receiver
            android:name=".MyReceive"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="com.example.myapplication.MY_BROADCAST_RECEIVER" />
            </intent-filter>
        </receiver>
```

```java
public class MyReceive extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        Toast.makeText(context, "这是一个广播!", Toast.LENGTH_SHORT).show();
    }
}
```

发送广播：

```java
Intent intent = new Intent("com.example.myapplication.MY_BROADCAST_RECEIVER");
                sendBroadcast(intent);
```

接收注册广播：

```java
 registerReceiver(myReceive, intentFilter);
```

动态注册：

```java
protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(R.layout.activity_main);
    intentFilter = new IntentFilter();
    intentFilter.addAction("android.net.conn.CONNECTIVITY_CHANGE");
    networkChangeReceiver = new NetworkChangeReceiver();
    registerReceiver(networkChangeReceiver, intentFilter);
}
protected void onDestroy() {
    super.onDestroy();
    unregisterReceiver(networkChangeReceiver);
}
class NetworkChangeReceiver extends BroadcastReceiver {
    @Override
    public void onReceiver(Context context, Intent intent) {
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo networkInfo = connectivityManager.getActivityNetworkInfo();
        if (networkInfo != null && networkInfo.isAvailable()) {
            Toast.makeText(context, "network is available...", Toast.LENGTH_SHORT);
        } else {
            Toast.makeText(context, "network is unavailable...", Toast.LENGTH_SHORT);
        }
    }
}
```

首先，使用IntentFilter()设置自身期望捕获到的广播信号，这个信号要和发出的广播信号相同才会有响应。  其次，内部类NetworkChangeReceiver()继承自BroadcastReceiver，需要监听广播信号的，都必须要继承该类，并且实现其中的onReceive方法。 紧接着，registerReceiver把NetworkChangeReceiver的对象和IntentFilter的对象进行注册，方便接收传来的广播信号。  最后，unregisterReceiver取消了注册，任何注册了广播信号的对象都必须要实现取消注册的功能。 上面的代码实现在onCreate方法中，因此app需要打开才可以接收广播。

### ContentProvider

ContentProvider 用来在不同的app之间实现数据共享，并且提供统一的接口。

ContentProvider是类似数据库中表的方式将数据暴露，也就是说ContentProvider就像一个数据库，外界获取其数据，类似于数据库的增删改查，只不过是采用URI来表示外界需要访问的“数据库”。

ContentProvider定义了一个对外开放的接口，从而可以让其他app使用我们自己应用中的文件、数据库内存储的信息

Android中如果想将自己应用的数据，一般都是数据库中的数据，提供给第三发的应用，那么我们只能通过ContentProvider 来实现。

ContentProvider 是app之间共享数据的接口，使用的时候需要先定义一个类继承ContentProvider ，然后覆写query、insert、update、delete等方法，因为其四大组件之一因此必须在AndroidManifest 文件中进行注册，把自己的数据通过url的形式共享出去。

