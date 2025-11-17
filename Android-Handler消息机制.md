## Android-Handler消息机制



App 开发中经常会使用 Handler，它可实现子线程和主线程之间通信，比如子线程代表一个下载任务，下载完成以后需要更新界面上某个控件的状态。

下面是我写的一个 Demo 场景，主 Activity 中启动一个线程，每秒加一，然后使用 handler post 到主线程，刷新界面上的 TextView，把对应的数字显示出来。

```java
class MainActivity : AppCompatActivity() {
    ......
    private lateinit var mCountTextView: TextView
    @Volatile
    private var isCount = false

    private val mHandler = Handler()

    @SuppressLint("SetTextI18n")
    private var mCountThread: Thread = Thread {
        var count = 0
        while (isCount) {
            mHandler.post(Runnable { mCountTextView.text = Integer.toString(count++) })
            Thread.sleep(1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        ......

        mCountTextView = findViewById<TextView>(R.id.text1)
        isCount = true
        mCountThread.start()
    }
```

首先我们创建了一个 Handler 对象，然后在线程中调用其 post 方法，传入的参数是一个 Runnable 对象。post 方法实际上调用了 sendMessageDelayed 方法，第一个入参是一个 Message 类型，通过 getPostMessage 方法将 Runnable 对象“包装”到一个 Message 对象中。第二个入参代表是否需要演示，这里传入 0 ，显然不需要延时。

```java
//frameworks/base/core/java/android/os/Handler.java
public class Handler {
    ......
    /**
    * 将 Runnable r 对象添加到消息队列中。该可运行对象将在 handler 附着的线程上运行。
    */
    public final boolean post(Runnable r)
    {
       return  sendMessageDelayed(getPostMessage(r), 0);
    }
    ......
    private static Message getPostMessage(Runnable r) {
        Message m = Message.obtain();
        m.callback = r;
        return m;
    }
    ......
}
```



sendMessageDelayed 方法中首先检查 delayMillis 是否小于 0，小于 0 则强制赋值为 0。然后接着调用了 sendMessageAtTime，第一个入参还是上面传递下来的 Message 对象，第二个参数是消息处理时间点，这里显然是就是现在的时刻。

在 sendMessageAtTime 方法中先检查 MessageQueue 是否为 null，如果为 null 则构建一个 RuntimeException 对象，打印一条警告级别的 Log，然后此函数返回 false 退出。如果 MessageQueue 不为 null，则调用 enqueueMessage 将相应的 Message 入队。

```java
//frameworks/base/core/java/android/os/Handler.java
public class Handler {
    ......
    public final boolean sendMessageDelayed(Message msg, long delayMillis)
    {
        if (delayMillis < 0) {
            delayMillis = 0;
        }
        return sendMessageAtTime(msg, SystemClock.uptimeMillis() + delayMillis);
    }
    
    public boolean sendMessageAtTime(Message msg, long uptimeMillis) {
        MessageQueue queue = mQueue;
        if (queue == null) {
            RuntimeException e = new RuntimeException(
                    this + " sendMessageAtTime() called with no mQueue");
            Log.w("Looper", e.getMessage(), e);
            return false;
        }
        return enqueueMessage(queue, msg, uptimeMillis);
    }
    ......
}
```



在 enqueueMessage 函数中，首先将 Message target 赋值为当前 Handler 对象，如果 mAsynchronous 为 true，说明支持异步，因此 msg 也要设置对应 flag。最后调用 MessageQueue 的 enqueueMessage 方法入队 msg。

```java
//frameworks/base/core/java/android/os/Handler.java
public final class Handler {
    ......
    private boolean enqueueMessage(MessageQueue queue, Message msg, long uptimeMillis) {
        msg.target = this;
        if (mAsynchronous) {
            msg.setAsynchronous(true);
        }
        return queue.enqueueMessage(msg, uptimeMillis);
    }
    ......
}
```



进入 enqueueMessage 方法，首先判断 msg.target 是否为 null，以及 msg 是否正在使用。如果为 null 则抛出 IllegalArgumentException 异常，同理如果在使用中也抛出 IllegalArgumentException 异常。进入 synchronized 同步代码块，把消息插入到队列（按照即将需要处理的时间点排序）。

```java
//frameworks/base/core/java/android/os/MessageQueue.java
public final class MessageQueue {
    ......
    boolean enqueueMessage(Message msg, long when) {
        if (msg.target == null) {
            throw new IllegalArgumentException("Message must have a target.");
        }
        if (msg.isInUse()) {
            throw new IllegalStateException(msg + " This message is already in use.");
        }

        synchronized (this) {
            if (mQuitting) {
                IllegalStateException e = new IllegalStateException(
                        msg.target + " sending message to a Handler on a dead thread");
                Log.w(TAG, e.getMessage(), e);
                msg.recycle();
                return false;
            }

            msg.markInUse();
            msg.when = when;
            Message p = mMessages;
            boolean needWake;
            if (p == null || when == 0 || when < p.when) {
                // 新链表头，唤醒事件队列如果被阻塞了。
                msg.next = p;
                mMessages = msg;
                needWake = mBlocked;
            } else {
                // 插入到队列中间。通常我们不需要唤醒事件队列，除非在队列的头部有一个屏障，
                // 并且消息是队列中最早的异步消息。
                needWake = mBlocked && p.target == null && msg.isAsynchronous();
                Message prev;
                for (;;) {
                    prev = p;
                    p = p.next;
                    if (p == null || when < p.when) {
                        break;
                    }
                    if (needWake && p.isAsynchronous()) {
                        needWake = false;
                    }
                }
                msg.next = p; // invariant: p == prev.next
                prev.next = msg;
            }

            // 我们可以假设 mPtr != 0，因为 mQuitting 是 false。
            if (needWake) {
                nativeWake(mPtr);
            }
        }
        return true;
    }
    ......
}
```



发送消息的流程到此已经结束了，消息发动到了队列里，处理消息一定是把队列里的消息取出逐个处理了。

MessageQueue 类上的注释指明了 MessageQueue 被 Handler 关联的 Looper 处理了。

翻译过来这段注释的含义如下：

包含 {@link Looper} 要分派的消息列表的低级类。消息不是直接添加到 MessageQueue，而是通过与 Looper 关联的 {@link Handler} 对象添加。

您可以使用 {@link Looper＃myQueue() Looper.myQueue()} 检索当前线程的 MessageQueue。

用于为线程运行消息循环的类。 默认情况下，线程没有与之关联的消息循环； 要创建一个，请在运行循环的线程中调用 {@link #prepare}，然后 {@link #loop} 使其处理消息，直到循环停止为止。

与消息循环的大多数交互是通过 {@link Handler} 类进行的。

```java
//frameworks/base/core/java/android/os/Looper.java
public final class Looper {
    /*
     * 此类包含基于 MessageQueue 设置和管理事件循环所需的代码。 
     * 影响队列状态的 API 应该在 MessageQueue 或 Handler 上定义，而不是在 Looper 本身上定义。 
     * 例如，在队列上定义了空闲处理程序和同步屏障，而在 Looper 上定义了线程的准备、循环和退出。
     */

    private static final String TAG = "Looper";

    // 除非您已调用 prepare()，否则 sThreadLocal.get() 将返回 null。
    static final ThreadLocal<Looper> sThreadLocal = new ThreadLocal<Looper>();
    private static Looper sMainLooper;  // 受 Looper.class 保护

    final MessageQueue mQueue;
    final Thread mThread;

    private Printer mLogging;

     /** 将当前线程初始化为 looper。
      * 这使您有机会创建 handler，然后在实际开始循环之前先引用此 looper。 
      * 确保在调用此方法后调用 {@link #loop()}，并通过调用 {@link #quit()} 结束该方法。
      */
    public static void prepare() {
        prepare(true);
    }

    private static void prepare(boolean quitAllowed) {
        // 每个线程只能创建一个 Looper
        if (sThreadLocal.get() != null) {
            throw new RuntimeException("Only one Looper may be created per thread");
        }
        sThreadLocal.set(new Looper(quitAllowed));
    }

    /**
     * 将当前线程初始化为 looper，将其标记为应用程序的主 looper。 
     * 应用程序的主 looper 是由 Android 环境创建的，因此您无需自己调用此函数。
     */
    public static void prepareMainLooper() {
        prepare(false);
        synchronized (Looper.class) {
            if (sMainLooper != null) {
                throw new IllegalStateException("The main Looper has already been prepared.");
            }
            sMainLooper = myLooper();
        }
    }

    /**
     * 返回应用程序的主 looper，该 looper 位于应用程序的主线程中。
     */
    public static Looper getMainLooper() {
        synchronized (Looper.class) {
            return sMainLooper;
        }
    }

    /**
     * 在此线程中运行消息队列。确保调用 {@link #quit()} 以结束循环。
     */
    public static void loop() {
        final Looper me = myLooper();
        if (me == null) {
            throw new RuntimeException("No Looper; Looper.prepare() wasn't called on this thread.");
        }
        final MessageQueue queue = me.mQueue;

        // 确保此线程的身份是本地进程的身份，并跟踪该身份令牌的实际含义。
        Binder.clearCallingIdentity();
        final long ident = Binder.clearCallingIdentity();

        for (;;) {
            //不断从当前线程的MessageQueue中取出Message，没有元素时阻塞
            Message msg = queue.next(); // 可能会阻塞
            if (msg == null) {
                // 没有消息表示消息队列正在退出。
                return;
            }

            // 如果 UI 事件设置了记录器，则必须在局部变量中
            Printer logging = me.mLogging;
            if (logging != null) {
                logging.println(">>>>> Dispatching to " + msg.target + " " +
                        msg.callback + ": " + msg.what);
            }

            msg.target.dispatchMessage(msg);

            if (logging != null) {
                logging.println("<<<<< Finished to " + msg.target + " " + msg.callback);
            }

            // 确保在分发消息的过程中没有损坏线程的身份。
            final long newIdent = Binder.clearCallingIdentity();
            if (ident != newIdent) {
                Log.wtf(TAG, "Thread identity changed from 0x"
                        + Long.toHexString(ident) + " to 0x"
                        + Long.toHexString(newIdent) + " while dispatching to "
                        + msg.target.getClass().getName() + " "
                        + msg.callback + " what=" + msg.what);
            }

            msg.recycleUnchecked();
        }
    }

    /**
     * 返回与当前线程关联的 Looper 对象。如果调用线程未与 Looper 关联，则返回 null。
     */
    public static @Nullable Looper myLooper() {
        return sThreadLocal.get();
    }

    /**
     * 返回与当前线程关联的 {@link MessageQueue} 对象。 
     * 必须从运行 Looper 的线程中调用此方法，否则将引发 NullPointerException。
     */
    public static @NonNull MessageQueue myQueue() {
        return myLooper().mQueue;
    }

    private Looper(boolean quitAllowed) {
        mQueue = new MessageQueue(quitAllowed);
        mThread = Thread.currentThread();
    }

    /**
     * 当前线程是是否此 looper 的线程。
     */
    public boolean isCurrentThread() {
        return Thread.currentThread() == mThread;
    }

    /**
     * 控制此 Looper 处理消息的日志记录。
     */
    public void setMessageLogging(@Nullable Printer printer) {
        mLogging = printer;
    }

    /**
     * 退出 looper。
     * 使 {@link #loop} 方法终止，而不处理消息队列中的更多消息。
     * 在请求 looper 退出后，任何将消息发布到队列的尝试都将失败。
     * 例如，{@link Handler＃sendMessage(Message)} 方法将返回 false。
     * 使用此方法可能是不安全的，因为在 looper 终止之前可能无法传递某些消息。 
     * 考虑改为使用 {@link #quitSafely}，以确保所有待处理的工作有序地完成。
     */
    public void quit() {
        mQueue.quit(false);
    }

    /**
     * 安全退出 looper。
     * 
     * 使 {@link #loop} 方法在处理完消息队列中所有已经要传递的剩余消息后立即终止。
     * 但是，在循环终止之前，将不会传递将来具有适当时间的未决延迟消息。
     * 在请求循环程序退出后，任何将消息发布到队列的尝试都将失败。
     * 
     * 例如，{@link Handler＃sendMessage(Message)} 方法将返回 false。
     */
    public void quitSafely() {
        mQueue.quit(true);
    }

    /**
     * 获取与此 Looper 关联的线程（Thread）。
     */
    public @NonNull Thread getThread() {
        return mThread;
    }

    /**
     * 获取此 looper 的消息队列。
     */
    public @NonNull MessageQueue getQueue() {
        return mQueue;
    }

    /**
     * 转储 looper 的状态以进行调试。
     */
    public void dump(@NonNull Printer pw, @NonNull String prefix) {
        pw.println(prefix + toString());
        mQueue.dump(pw, prefix + "  ");
    }

    @Override
    public String toString() {
        return "Looper (" + mThread.getName() + ", tid " + mThread.getId()
                + ") {" + Integer.toHexString(System.identityHashCode(this)) + "}";
    }
}
```

到这里答案已经非常清晰了，虽然我们的 App 中没有显式调用 prepareMainLooper() 和 loop()，prepareMainLooper() 的注释也表明是系统自动帮我们调用了。在调用 prepareMainLooper() 方法时，我们会构造 Looper 对象，调用 Looper 构造器的时候创建了关联的 MessageQueue。loop() 方法中首先调用其关联的 MessageQueue 对象 next() 方法，从中获取一条消息，然后在上面我们发送消息的时候给对应的 Message 设置了 target 为发送消息 Handler 本身。接着就会调用 Handler 的 dispatchMessage 方法分发 Message。我们通常会继承 Handler 并实现其 handleMessage 处理自己的逻辑。

在 Demo 中我们实际上发送了一个“包装”了 Runnable 的 Message ，“包装”的时候设置 Message 的 callback 正是对应的 Runnable 对象。接着就会调用 handleCallback 处理对应的 Runnable。其实就是调用 Runnable 的 run 方法。

```java
//frameworks/base/core/java/android/os/Handler.java
public class Handler {
    ......
    /**
     * 子类必须实现这个方法来接收消息。
     */
    public void handleMessage(Message msg) {
    }
    
    /**
     * 在此处处理系统消息。
     */
    public void dispatchMessage(Message msg) {
        if (msg.callback != null) {
            handleCallback(msg);
        } else {
            if (mCallback != null) {
                if (mCallback.handleMessage(msg)) {
                    return;
                }
            }
            //调用Handler自身的handlerMessage，就是我们常常重写的那个
            handleMessage(msg);
        }
    }
    ......
    private static void handleCallback(Message message) {
        message.callback.run();
    }
    ......
}
```

我们在 Demo 中仅仅 new 了一个 Handler 对象，看看发生了什么？

```java
//frameworks/base/core/java/android/os/Handler.java
public class Handler {
    ......
    public Handler() {
        this(null, false);
    }
    ......
    public Handler(Callback callback, boolean async) {
        ......

        mLooper = Looper.myLooper();
        if (mLooper == null) {
            throw new RuntimeException(
                "Can't create handler inside thread that has not called Looper.prepare()");
        }
        mQueue = mLooper.mQueue;
        mCallback = callback;
        mAsynchronous = async;
    }

    ......
}
```



答案清晰了，构造函数中先拿到对应的 Looper，Handler（主线程中创建） 使用的 MessageQueue 是从 Looper 对象中获取的。我们在 Looper 类 loop() 方法循环消息的时候，对 Demo 而言，就是在主线程中轮询消息，并处理了对应的 Runnable，也就是说在主线程中调用了 Runnable 的 run 方法，这就是为什么我们可以通过 Handler 从子线程向主线程发送处理 UI 逻辑消息而不报错的原因！

还有一个疑惑没有解决：主线程的 Looper 在哪里创建？

我们知道 ActivityThread 管理应用程序进程中主线程的执行、调度和运行 Activity、广播，以及作为 Activity 管理器请求的其他操作。它的 main 方法如下：

```java
//frameworks/base/core/java/android/app/ActivityThread.java
public final class ActivityThread {
    ......
    public static void main(String[] args) {
        ......

        Looper.prepareMainLooper();

        ActivityThread thread = new ActivityThread();
        thread.attach(false);

        if (sMainThreadHandler == null) {
            sMainThreadHandler = thread.getHandler();
        }

        ......
        Looper.loop();

        throw new RuntimeException("Main thread loop unexpectedly exited");
    }
}
```

Handler简单使用：

```java
public class MainActivity extends Activity {
    private static final String TAG = "MainActivity";

    private Handler mHandler;
    private Button btnSendeToMainThread;
    private static final int MSG_SUB_TO_MAIN= 100;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        // 1.创建Handler，并重写handleMessage方法
        mHandler = new Handler() {
            @Override
            public void handleMessage(Message msg) {
                super.handleMessage(msg);
                // 处理消息
                switch (msg.what) {
                    case MSG_SUB_TO_MAIN:
                        // 打印出处理消息的线程名和Message.obj
                        Log.e(TAG, "接收到消息： " +    Thread.currentThread().getName() + ","+ msg.obj);
                        break;
                    default:
                        break;
                }
            }
        };

        btnSendeToMainThread = (Button) findViewById(R.id.btn_sendto_mainthread);
        btnSendeToMainThread .setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // 创建一个子线程，在子线程中发送消息
                new Thread(new Runnable() {
                    @Override
                    public void run() {
                        Message msg = Message.obtain();
                        msg.what = MSG_SUB_TO_MAIN;
                        msg.obj = "这是一个来自子线程的消息";
                        // 2.发送消息
                        mHandler.sendMessage(msg);
                    }
                }).start();
            }
        });
    }
}
```



常见问题：

Message:信息的携带者，持有了Handler，存在MessageQueue中，一个线程可以有多个

Hanlder:消息的发起者，发送Message以及消息处理的回调实现，一个线程可以有多个Handler对象

Looper:消息的遍历者，从MessageQueue中循环取出Message进行处理，一个线程最多只有一个

MessageQueue:消息队列，存放了Handler发送的消息，供Looper循环取消息，一个线程最多只有一个

Android中，有哪些是基于Handler来实现通信的？
 答：App的运行、更新UI、AsyncTask、Glide、RxJava等

处理Handler消息，是在哪个线程？一定是创建Handler的线程么？
 答：创建Handler所使用的Looper所在的线程

消息是如何插入到MessageQueue中的？
 答： 是根据when在MessageQueue中升序排序的，when=开机到现在的毫秒数+延时毫秒数

当MessageQueue没有消息时，它的next方法是阻塞的，会导致App ANR么？
 答：不会导致App的ANR，是Linux的pipe机制保证的，阻塞时，线程挂起；需要时，唤醒线程

子线程中可以使用Toast么？
 答：可以使用，但是Toast的显示是基于Handler实现的，所以需要先创建Looper，然后调用Looper.loop。

Looper.loop()是死循环，可以停止么？
 答：可以停止，Looper提供了quit和quitSafely方法

Handler内存泄露怎么解决？
 答： 静态内部类+弱引用 、Handler的removeCallbacksAndMessages等方法移除MessageQueue中的消息