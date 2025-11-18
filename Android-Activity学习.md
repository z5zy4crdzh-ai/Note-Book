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



## Activity的四个启动模式

Activity作为四大组件之一，也可以说是四大组件中最重要的一个组件，它负责App的视图，还负责用户交互，而且有时候还经常其他组件绑定使用，可以说非常的重要。

虽然说我们天天都在使用Activity，但是你真的对Activity的生命机制烂熟于心，完全了解了吗？的确，Activity的生命周期方法只有七个（自己数-。+），但是其实那只是最平常的情况，或者说是默认的情况。也就是说在其他情况下，Activity的生命周期可能不会是按照我们以前所知道的流程，这就要说到我们今天的重点了——Activity的启动模式：我们的Activity会根据自身不同的启动模式，自身的生命周期方法会进行不同的调用。



一、在将启动模式之前必须了解的一些知识：

在正式的介绍Activity的启动模式之前，我们首先要了解一些旁边的知识，这些知识如果说模糊不清，那么在讨论启动模式的时候会一头雾水（笔者亲身感悟）。

1. 一个应用程序通常会有多个Activity，这些Activity都有一个对应的action（如MainActivity的action），我们可以通过action来启动对应Activity（隐式启动）。

```xml
<action android:name="android.intent.action.MAIN" />
```

1. 一个应用程序可以说由一系列组件组成，这些组件以进程为载体，相互协作实现App功能。
2. 任务栈（Task Stack）或者叫退回栈（Back Stack）介绍：

> 3.1.任务栈用来存放用户开启的Activity。
>
> 3.2.在应用程序创建之初，系统会默认分配给其一个任务栈（默认一个），并存储根Activity。
>
> 3.3.同一个Task Stack，只要不在栈顶，就是onStop状态：

<img width="350" height="192" alt="image" src="https://github.com/user-attachments/assets/4335efd5-c616-40ad-919f-0b249e003e98" />


> 3.4.任务栈的id自增长型，是Integer类型。
>
> 3.5.新创建Activity会被压入栈顶。点击back会将栈顶Activity弹出，并产生新的栈顶元素作为显示界面（onResume状态）。
>
> 3.6.当Task最后一个Activity被销毁时，对应的应用程序被关闭，清除Task栈，但是还会保留应用程序进程（狂点Back退出到Home界面后点击Menu会发现还有这个App的框框。个人理解应该是这个意思），再次点击进入应用会创建新的Task栈。

1. Activity的affinity：

> 4.1.affinity是Activity内的一个属性（在ManiFest中对应属性为taskAffinity）。默认情况下，拥有相同affinity的Activity属于同一个Task中。
>
> 4.2.Task也有affinity属性，它的affinity属性由根Activity（创建Task时第一个被压入栈的Activity）决定。
>
> 4.3.在默认情况下（我们什么都不设置），所有的Activity的affinity都从Application继承。也就是说Application同样有taskAffinity属性。
>
> ```bash
> <application
>        android:taskAffinity="gf.zy"
> ```
>
> 4.4.Application默认的affinity属性为Manifest的包名。

暂时就是这么多了，如果还有不妥的地方我会补充的。接下来我们来正式看Activity的启动模式：



二、Activity启动模式：



### 1. 默认启动模式standard：

该模式可以被设定，不在manifest设定时候，Activity的默认模式就是standard。在该模式下，启动的Activity会依照启动顺序被依次压入Task中：

<img width="823" height="402" alt="image" src="https://github.com/user-attachments/assets/4ee2c466-bb73-407b-a2de-7f4994721501" />


上面这张图讲的已经很清楚了，我想应该不用做什么实验来论证了吧，这个是最简单的一个，我们过。



### 2. 栈顶复用模式singleTop：

在该模式下，如果栈顶Activity为我们要新建的Activity（目标Activity），那么就不会重复创建新的Activity。

<img width="867" height="389" alt="image" src="https://github.com/user-attachments/assets/69c73bf0-bf48-4f12-b932-65f8c26eecc6" />


```
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="zy.pers.activitytext">
 
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:taskAffinity="gf.zy"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
 
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name=".TwoActivity"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="ONETEXT_TWOACTIVITY" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity>
        <activity android:name=".ThreeActivity">
            <intent-filter>
                <action android:name="ONETEXT_THREEACTIVITY" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </activity>
    </application>
 
</manifest>
```

这是我的第一个应用OneText的Mainfest结构，里面创建了三个Activity，我们把第二个Activity的模式设置为singleTop。

每个Activity界面都只有一个显示当前界面名称的TextView和一个用来组跳转的Button，所以应用OneText的功能就是从活动1跳转到活动2，活动2继续跳转活动2，代码就不给大家展示了，都能写出来。

![image](https://img-blog.csdn.net/2018060610494550)

我们发现在我们跳转到TwoActivity之后，点击跳转新的TwoActivity时候，他没有响应。

为了作对比，我们再把TwoActivity设置为standard，看一看效果：

![image](https://img-blog.csdn.net/20180606105155211)

我们发现创建了很多的TwoActivity。

同时我们打印上task的Id（我没有把所有周期方法都打印log）：

![image](https://img-blog.csdn.net/20180606105445656)

发现他们全部都是来自一个Task。这个可以过。

应用场景：

开启渠道多，适合多应用开启调用的Activity：通过这种设置可以避免已经创建过的Activity被重复创建（多数通过动态设置使用，关于动态设置下面会详细介绍）

### 3. 栈内复用模式singleTask：

与singleTop模式相似，只不过singleTop模式是只是针对栈顶的元素，而singleTask模式下，如果task栈内存在目标Activity实例，则：

1. 将task内的对应Activity实例之上的所有Activity弹出栈。
2. 将对应Activity置于栈顶，获得焦点。

![image](https://img-blog.csdn.net/20180606105812988)

同样我们也用代码来实现一下这个过程：

还是刚才的那一坨代码，只是我们修改一下Activity1的模式为singleTask，然后让Activity2跳转到Activity3，让Activity3跳转到Activity1：

![image](https://img-blog.csdn.net/20180606110610917)

在跳回MainActivity之后点击back键发现直接退出引用了，这说明此时的MainActivity为task内的最后一个Activity。所以这个模式过。

应用场景：

程序主界面，我们肯定不希望主界面被多创建，而且在主界面退出的时候退出整个App是最好的设想。

耗费系统资源的Activity：对于那些及其耗费系统资源的Activity，我们可以考虑将其设为singleTask模式，减少资源耗费（在创建阶段耗费资源的情况，个人理解-。+）。



### 4.全局唯一模式singleInstance：

这是我们最后的一种启动模式，也是我们最恶心的一种模式：在该模式下，我们会为目标Activity分配一个新的affinity，并创建一个新的Task栈，将目标Activity放入新的Task，并让目标Activity获得焦点。新的Task有且只有这一个Activity实例。    如果已经创建过目标Activity实例，则不会创建新的Task，而是将以前创建过的Activity唤醒（对应Task设为Foreground状态）

![image](https://img-blog.csdn.net/20180606111812956)

我们为了看的更明确，这次不按照上图的步骤设计程序了（没错，这几张图都不是我画的-。+！）。

我们先指定一下这次的程序：还是这三个Activity，这次Activity3设置为singleInstance，1和2默认（standard）。

然后我们看一下这个效果：

![image](https://img-blog.csdn.net/20180606113044248)

说一下我们做了什么操作：

首先由1创建2,2创建3，然后又由3创建2,2创建3,3创建2，然后一直back，图如下：

![image](https://img-blog.csdn.net/20180606113647437)

还请各位别嫌弃我-。+，图虽然不好看，但是很生动形象。。。。具体说一下：这张图对应着我们上面的程序流程，黄色的代表Background的Task，蓝色的代表Foreground的Task。

我们发现back的时候会先把Foreground的Task中的Activity弹出，直到Task销毁，然后才将Background的Task唤到前台，所以最后将Activity3销毁之后，会直接退出应用。



在Android面试中，Activity启动模式是高频考点，需深入理解其机制与应用场景。以下是精讲内容，结构清晰，便于记忆与表达：

------

### **5. 四种启动模式的核心区别**

- **standard（默认模式）**
  - 每次启动均创建新实例，遵循“后进先出”的栈结构。
  - **示例**：从Activity A（standard）跳转自身，栈中不断新增A的实例。
- **singleTop（栈顶复用）**
  - 若目标Activity位于栈顶，则复用实例（调用`onNewIntent`），否则新建。
  - **应用场景**：防止连续点击导致重复页面（如支付按钮跳转）。
- **singleTask（栈内单例）**
  - 在指定任务栈中保持唯一实例。若存在，则清除其上方所有Activity，并调用`onNewIntent`。
  - **关键点**：通过`taskAffinity`指定任务栈，默认与包名一致。
  - **典型应用**：App主页（如微信主界面）。
- **singleInstance（全局单例）**
  - 独占一个任务栈，且栈内仅自身。其他Activity启动时进入其他栈。
  - **使用场景**：独立运行的界面（如系统拨号盘）。

------

### **6. 高频面试题解析**

#### **Q1：singleTask与taskAffinity的关系？**

- 答

  ：

  - 默认情况下，singleTask的Activity位于应用主任务栈。
  - 若设置不同`taskAffinity`，则会创建新任务栈。例如，Activity A设置`singleTask`且`taskAffinity="com.example.task2"`，启动时会新建独立栈。

#### **Q2：从Activity A（standard）启动B（singleTask），B启动C（singleTop），C再启动B，栈状态如何？**

- 答

  ：

  1. A启动B → 新建任务栈（假设B的`taskAffinity`不同），栈1：[A]，栈2：[B]。
  2. B启动C → 栈2变为[B, C]。
  3. C启动B → 栈2中B已存在，清除C，调用`onNewIntent`，栈2：[B]。

#### **Q3：onNewIntent调用时机与数据处理？**

- 答

  ：

  - 在singleTop/singleTask模式下，若Activity被复用，系统调用`onNewIntent()`。

  - 关键代码

    ：

    ```java
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent); // 更新Intent
        handleData(intent); // 处理新数据
    }
    ```

------

### **7. Intent Flags与启动模式的协同**

- FLAG_ACTIVITY_NEW_TASK

  ：

  - 结合`taskAffinity`创建新任务栈。若未指定，则与默认栈行为一致。

- FLAG_ACTIVITY_SINGLE_TOP

  ：

  - 等同于`singleTop`模式，优先复用栈顶实例。

- FLAG_ACTIVITY_CLEAR_TOP

  ：

  - 若目标Activity已存在，清除其上方所有实例。与`singleTask`配合时，复用实例；否则销毁重建。

------

### **8. 典型场景与误区**

- **场景：避免重复打开同一页面**
  - **方案**：对详情页使用`singleTop`，或在Intent中添加`FLAG_ACTIVITY_CLEAR_TOP|FLAG_ACTIVITY_SINGLE_TOP`。
- **误区：singleTask一定在新栈中？**
  - 错误！仅当`taskAffinity`与当前栈不同时，才会创建新栈。

------

### **9. 生命周期与启动模式**

- **复用Activity时的生命周期**：
  顺序为：原实例`onPause()` → 新实例`onCreate()`（若新建） → 原实例`onNewIntent()` → `onResume()`。

------

### **总结**

- 核心口诀

  ：

  - standard堆叠无脑创，singleTop栈顶防重复。
  - singleTask栈内单例清上方，singleInstance孤独一栈无同伴。

- **面试技巧**：结合绘图（任务栈变化）和实际代码逻辑，展示对机制的透彻理解。

