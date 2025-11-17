### Activity

android 中，Activity 相当于一个页面，可以在Activity中添加Button、CheckBox 等控件，一个android 程序有多个Activity组成。

![img](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/eebb6c690b83411cbc28f579e6c0b747~tplv-k3u1fbpfcp-jj-mark:0:0:0:0:q75.image#?w=931&h=970&s=95930&e=webp&b=fffefe)

主要有三种状态：

0.  运行状态，活动进入前台，位于栈顶，此时活动处于运行状态。运行状态的活动可以获得焦点，活动的内容会高亮显示。
0.  暂停状态，其他活动进入天台，当前活动不在处于栈顶，但仍可见只是变暗，此时活动处于暂停状态。暂停状态的活动不能获得焦点，活动中的内容会变暗。
0.  停止状态，当活动不在处于栈顶，被其他活动完全覆盖，不可见时，此时活动处于停止状态。处于停止状态的活动虽然不可见，但是仍然保持所有状态，包括变量

生命周期的七种方法：

-   onCreate（）：当活动初始化时候开始调用
-   onStart（）：活动从不可见变为可见，但是颜色还是暗色，不能活动焦点，不能接收用户事件。此时调用此方法。
-   onResume（）：活动从暗色变为高亮，活动获得焦点，接收用户事件。此时调用此方法。
-   onPause（）：活动从运行状态到暂停状态，通常会在这个方法种将一些消耗CPU的资源释放掉，以及保持一些关键数据，但是这个方法的执行速度一定要快，不然会影响到新的栈顶的活动的使用。
-   onStop（）：活动从暂停状态变为停止状态调用此方法。
-   onRestart（）：处于停止的活动，活动重新回到前台，变成活动状态调用。
-   onDestory（）：活动被销毁时候调用。

声明活动：

```xml
<activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />

                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name=".FileActivity" ></activity>
        <activity android:name=".InFileActivity" ></activity>
```

多个活动跳转：

```java
protected void onCreate(Bundle savedInstanceState) {
    ImageButton button1 =  findViewById(R.id.button_1);
        button1.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // 在这里编写点击事件的具体逻辑
                Intent intent = new Intent(MainActivity.this,FileActivity.class);
                startActivity(intent);
                Toast.makeText(MainActivity.this, "正在打开外部存储", Toast.LENGTH_SHORT).show();
            }
        });
}  
    
```

参数传递（暂时还没用到）：

Activity的启动方法：

显示启动：

class跳转：

```java
Intent intent = new Intent(LoginActivity.this,SuccessActivity.class);
intent.putExtra("userid",txtUserid.getText().toSting());    //userid是键，后面的是值
startActivity(intent);
```

包名类名跳转：

```java
Intent intent = new Intent(); 
intent.setClassName(FirstActivity.this,"com.hello.launchapplication.SecondActivity");
startActivity(intent);
```

隐式启动：

隐式启动并不明确指出想要启动的哪一个活动，而是指定了一系列的action和category等信息，然后由系统去分析这个Intent，并帮我们找出合适的活动去启动

在AndroidManifest.xml文件中 定义action和category属性 action的名字可以随便定义，而category默认的配置为DEFAULT

```xml
<activity android:name=".SecondActivity" >
<intent-filter>
<action android:name="com.example.activitytest.ACTION_START" />
<category android:name="android.intent.category.DEFAULT" />
</intent-filter>
</activity>
```

```java
Intent intent = new Intent("com.example.activitytest.ACTION_START");
startActivity(intent)
```

例如启动系统的Activity

```java
拨打电话
intent.setAction(Intent.ACTION_CALL);
发送短信
intent.setAction(Intent.ACTION_SENDTO);
打开相机
intent.setAction(MediaStore.ACTION_IMAGE_CAPTURE);
```

```java
package com.xiaozeng.syatemapplication;

public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        //开启拨号界面
        Button button = findViewById(R.id.button1);
        button.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent();
                intent.setAction(Intent.ACTION_DIAL);
                startActivity(intent);
            }
        });

        //开启短信界面
        Button button2 = findViewById(R.id.button2);
        button2.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent();
                Uri sms = Uri.parse("smsto:"+"10086");
                intent.setAction(Intent.ACTION_SENDTO);
                intent.setData(sms);
                intent.putExtra("sms body","服务满分yyyyyyyyy");
                startActivity(intent);
            }
        });

        //开启相机界面
        Button button3 = findViewById(R.id.button3);
        button3.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent();
                intent.setAction(MediaStore.ACTION_IMAGE_CAPTURE);
                startActivity(intent);
            }
        });

    }
}

```

下一个活动接收参数：

```java
Intent intent = this.getIntent();
Bundle bundle = intent.getExtras();
String userid = bundle.getString("userid")
```

返回上一个活动，多个活动之间的跳转，是将多个活动放到栈中，通过入栈和出栈实现。进行下一个活动是通过startAcivity（Intent）方法将意图所找到的活动入栈，使其处于栈顶，这样就实现了跳转。如果像返回上一个活动，可以使用活动的 void finish（）方法。调用当前活动的finish()方法回到上一个活动：

```java
button.setOnClickListener(new View.OnClickListener){
        @Override
        public void onClick(View v){
                    finish();
            }
        }

```

intent：

-   Android中提供了Intent机制来协助应用间的交互与通讯，或者采用更准确的说法是，Intent不仅可用于应用程序之间，也可用于应用程序内部的activity, service和broadcast receiver之间的交互。Intent这个英语单词的本意是“目的、意向、意图”。
-   Intent是一种运行时绑定（runtime binding)机制，它能在程序运行的过程中连接两个不同的组件。通过Intent，你的程序可以向Android表达某种请求或者意愿，Android会根据意愿的内容选择适当的组件来响应。