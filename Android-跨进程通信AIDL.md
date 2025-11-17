## Android-跨进程通信AIDL

服务（Service）是android系统中非常重要的组件。Service可以脱离应用程序运行。也就是说，应用程序只起到一个启动Service的作用。一但Service被启动，就算应用程序关闭，Service仍然会在后台运行。

android系统中的Service主要有两个作用：后台运行和跨进程通讯。后台运行就不用说了，当Service启动后，就可以在Service对象中 运行相应的业务代码，而这一切用户并不会察觉。而跨进程通讯是这一节的主题。如果想让应用程序可以跨进程通讯，就要使用我们这节讲的AIDL服 务，AIDL的全称是Android Interface Definition Language，也就是说，AIDL实际上是一种接口定义语言。通过这种语言定义接口后，Eclipse插件（ODT）会自动生成相应的Java代码接 口代码。下面来看一下编写一个AIDL服务的基本步骤。

在Main类所有的目录建立一个IMyService.aidl文件，内容如下：

```java
package com.aosp.myservice;
interface IMyService {
   int resetFactorySystem();
   void getSystemCpuRate(String UUID);
}
```



然后建立一个MyService类，该类是Service的子类，代码如下：

```java
public class MyService extends Service  {  
    //IMyService.Stub类是根据IMyService.aidl文件生成的类，该类中包含了接口方法（resetFactorySystem）  
    public class MyServiceImpl extends IMyService.Stub  {  
          @Override
        public int resetFactorySystem() throws RemoteException {
             LogUtils.e(TAG + "resetFactorySystem start ret:" + RET_OK);
             NaviManager.getInstance().resetFactory();
             execFactoryReset();
             return RET_OK;
              }
        public void getSystemCpuRate(String UUID){
            FirstCpu = systemInfoUtil.getCpuInfo();
            Uuid = UUID;
            mHandler.postDelayed(CalculateCpuRateTask, 100);
              }
    }  

    @Override  
    public IBinder onBind(Intent intent)   {          
        //该方法必须返回MyServiceImpl类的对象实例  
        return new MyServiceImpl();  
    }  
    @Override
    public boolean onUnbind(Intent intent) {
        return super.onUnbind(intent);
    }
}  
```

 最后需要在AndroidManifest.xml文件中配置MyService类，代码如下：

```xml
<!--  注册服务 -->  
<service android:name=".MyService">  
    <intent-filter>  
        <!--  指定调用AIDL服务的ID  -->  
        <action android:name="com.aosp.myservice" />  
    </intent-filter>  
</service>  
```





下面来看看如何调用这个AIDL服务。首先建立一个android工程：aidlclient。然后将aidlservice工程中自动生成的 IMyService.java文件复制到aidlclient工程中。在调用AIDL服务之前需要先使用bindService方法绑定AIDL服务。 bindService方法需要一个ServiceConnection对象。ServiceConnection有一个 onServiceConnected方法，当成功绑定AIDL服务且，该方法被调用。并通过service参数返回AIDL服务对象。下面是调用 AIDL服务的完成代码。

```java
public class Main extends Activity implements OnClickListener {
    private IMyService myService = null;
    // 创建ServiceConnection对象
    private ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            // 获得AIDL服务对象
            myService = IMyService.Stub.asInterface(service);
            try {
                // 调用AIDL服务对象中的getValue方法，并以对话框中显示该方法的返回值
                new AlertDialog.Builder(Main.this).setMessage(myService.resetFactorySystem()).setPositiveButton("确定", null).show();
            } catch (Exception e) {
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
        }
    };

    @Override
    public void onClick(View view) {
        // 绑定AIDL服务
        bindService(new Intent("com.aosp.myservice"), serviceConnection, Context.BIND_AUTO_CREATE);
    }
}
```



AIDL返回一个类示例

首先创建一个新的aidl文件

```java
// SystemInfo.aidl
package com.aosp.myservice;

// Declare any non-default types here with import statements

parcelable SystemInfo;
```

我们这个类需要实现parcelable接口，以支持跨进程传输，接下来创建SystemInfo.java

```java
package com.adayo.aaop_deviceservice;

import android.os.Parcel;
import android.os.Parcelable;

public class SystemInfo implements Parcelable {


    private String uuid;
    private byte exception;
    private int cpuLoad;
    private int avaRam;
    private int avaRom;

    public String getUuid() {
        return uuid;
    }

    public void setUuid(String uuid) {
        this.uuid = uuid;
    }

    public byte getException() {
        return exception;
    }

    public void setException(byte exception) {
        this.exception = exception;
    }

    public int getCpuLoad() {
        return cpuLoad;
    }

    public void setCpuLoad(int cpuLoad) {
        this.cpuLoad = cpuLoad;
    }

    public int getAvaRam() {
        return avaRam;
    }

    public void setAvaRam(int avaRam) {
        this.avaRam = avaRam;
    }

    public int getAvaRom() {
        return avaRom;
    }

    public void setAvaRom(int avaRom) {
        this.avaRom = avaRom;
    }

//    protected SystemInfo(Parcel in) {
//    }

    public static final Creator<SystemInfo> CREATOR = new Creator<SystemInfo>() {
        @Override
        public SystemInfo createFromParcel(Parcel in) {
            SystemInfo systemInfo = new SystemInfo();
            systemInfo.setUuid(in.readString());
            systemInfo.setException(in.readByte());
            systemInfo.setCpuLoad(in.readInt());
            systemInfo.setAvaRam(in.readInt());
            systemInfo.setAvaRom(in.readInt());
            return new SystemInfo();
        }

        @Override
        public SystemInfo[] newArray(int size) {
            return new SystemInfo[size];
        }
    };

    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void writeToParcel(Parcel dest, int flags) {
        dest.writeString(uuid);
        dest.writeByte(exception);
        dest.writeInt(cpuLoad);
        dest.writeInt(avaRam);
        dest.writeInt(avaRom);
    }
}
```

然后在impl文件中使用就好了

```java
public class MyService extends Service  {  
    //IMyService.Stub类是根据IMyService.aidl文件生成的类，该类中包含了接口方法（resetFactorySystem）  
    public class MyServiceImpl extends IMyService.Stub  {  
          @Override
        public int resetFactorySystem() throws RemoteException {
                SystemInfo systemInfo = new SystemInfo();
                systemInfo.setUuid(Uuid);
                systemInfo.setCpuLoad(777);
                systemInfo.setAvaRam(Integer.parseInt(ramStr));
                systemInfo.setAvaRom(888);
              }
  }
```



最后就是客户端绑定Service并调用AIDL接口，可以直接通过对象直接调用get函数获取数据