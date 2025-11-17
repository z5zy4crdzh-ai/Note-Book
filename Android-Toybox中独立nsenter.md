## Toybox中 nsenter抽出

Android Q版本中，许多Linux命令以及Android自带的命令并不是都有自身的二进制文件存在/system/bin/目录下，而是集成在toybox这个二进制文件中，通过toybox来执行对应的命令；可以看到下面的命令很多都是软链接到toybox上，在该工具对应源码下的README中，首行就是其用途的介绍，是一个集成多个Linux命令行的工具。源码路径为android/external/toybox/

```
lrwxr-xr-x  1 root shell       6 2024-01-01 08:00 ln -> toybox
lrwxr-xr-x  1 root shell       6 2024-01-01 08:00 load_policy -> toybox 
lrwxr-xr-x  1 root shell       6 2024-01-01 08:00 log -> toybox
```

nsenter命令是toybox中的一个，**nsenter**命令是一个可以在**指定进程的命令空间下运行指定程序的命令**，一个最典型的用途就是进入容器的网络命令空间。相当多的容器为了轻量级，是不包含较为基础的命令的，比如说ip address，ping，telnet，ss，tcpdump等等命令，这就给调试容器网络带来相当大的困扰：只能通过docker inspect ContainerID命令获取到容器IP，以及无法测试和其他网络的连通性。这时就可以使用nsenter命令仅进入该容器的网络命名空间，使用宿主机的命令调试容器网络。

```
$ nsenter --help

nsenter [options] [program [arguments]]

options:
-t, --target pid：指定被进入命名空间的目标进程的pid
-m, --mount[=file]：进入mount命令空间。如果指定了file，则进入file的命令空间
-u, --uts[=file]：进入uts命令空间。如果指定了file，则进入file的命令空间
-i, --ipc[=file]：进入ipc命令空间。如果指定了file，则进入file的命令空间
-n, --net[=file]：进入net命令空间。如果指定了file，则进入file的命令空间
-p, --pid[=file]：进入pid命令空间。如果指定了file，则进入file的命令空间
-U, --user[=file]：进入user命令空间。如果指定了file，则进入file的命令空间
-G, --setgid gid：设置运行程序的gid
-S, --setuid uid：设置运行程序的uid
-r, --root[=directory]：设置根目录
-w, --wd[=directory]：设置工作目录

如果没有给出program，则默认执行$SHELL。

```

要独立出nsenter命令，首先需要知道toybox是怎么调用到nsenter命令的

toybox的main函数中比较简单，先判断参数是否异常，然后将参数放到toys结构体中，调用toybox_main()继续往下执行。在toybox_main中完成命令的执行，这些命令又都是存在toy_list这张映射表中。通过toy_exec中的toy_find可以找到，查找方式是通过二分法进行查找，因为所有的命令在数组中是有序的，找到后将指针赋值给which这个结构体指针。

toy_exec_which中会先做检查，然后在toy_init中完成命令的初始化，通过toy_singleinit将对应命令和命令的参数存放到toys中。

真正关键的部分为if (toys.which) toys.which->toy_main()，这一步会真正调起对应命令所在的入口函数，执行对应命令的逻辑；这里需要看下toy_main的定义，是在toy_list 结构体中的一个函数指针。在main.c中定义了该结构体数组，是在newtoys.h声明的宏定义，拿nsenter这个命令来举例，toy_main指向了nsenter_main这个函数，所以通过该入口可以真正调起df的逻辑入口，执行完之后就退出。其他的基本都类似

所以他的顺序是： main -> toybox_main() -> toy_exec_which() -> toy_main() ,最后的toy_main()就是调用各种命令的函数入口

toy_exec_which()：

```
void toy_exec_which(struct toy_list *which, char *argv[])
{
  // Return if we can't find it (which includes no multiplexer case),
  if (!which) return;

  // Return if stack depth getting noticeable (proxy for leaked heap, etc).

  // Compiler writers have decided subtracting char * is undefined behavior,
  // so convert to integers. (LP64 says sizeof(long)==sizeof(pointer).)
  // Signed typecast so stack growth direction is irrelevant: we're measuring
  // the distance between two pointers on the same stack, hence the labs().
  if (!CFG_TOYBOX_NORECURSE && toys.stacktop)
    if (labs((long)toys.stacktop-(long)&which)>6000) return;

  // Return if we need to re-exec to acquire root via suid bit.
  if (toys.which && (which->flags&TOYFLAG_ROOTONLY) && toys.wasroot) return;

  // Run command
  toy_init(which, argv);
  if (toys.which) toys.which->toy_main();
  xexit();
}
```

那它这里是toys.which->toy_main()是怎么调用到各个命令的入口函数呢，它有个newtoys.h头文件定义了各种命令，通过toy_list结构体来调用。

newtoys.h：

```
USE_NOHUP(NEWTOY(nohup, "<1^", TOYFLAG_USR|TOYFLAG_BIN|TOYFLAG_ARGFAIL(125)))
USE_NPROC(NEWTOY(nproc, "(all)", TOYFLAG_USR|TOYFLAG_BIN))
USE_NSENTER(NEWTOY(nsenter, "<1F(no-fork)t#<1(target)i:(ipc);m:(mount);n:(net);p:(pid);u:(uts);U:(user);", TOYFLAG_USR|TOYFLAG_BIN))
USE_OD(NEWTOY(od, "j#vw#<1=16N#xsodcbA:t*", TOYFLAG_USR|TOYFLAG_BIN))
USE_ONEIT(NEWTOY(oneit, "^<1nc:p3[!pn]", TOYFLAG_SBIN))
```

所以要独立出nsenter命令，先把两个c文件合并在一起，再添加一个toy_list的命令映射表，因为我们不引用它这个头文件了。既然已经独立出来了，这就是属于我们自己的小工具，那是否能自定义参数呢，我这里就多添加了-s参数来判断容器类型。s：代表后面需要添加参数

```
struct toy_list toy_list[1] = {
    { "ns_tool", nsenter_main,"<1F(no-fork)t#<1(target)i:(ipc);m:(mount);n:(net);p:(pid);u:(uts);U:(user);s:(sys)", TOYFLAG_USR|TOYFLAG_BIN }
};
```

因为它判断是否有输入参数是根据flags来判断的，相对应的flags.h头文件中也要添加我们新加的新参数

```
#ifdef FOR_nsenter
#ifndef TT
#define TT this.nsenter
#endif
#define FLAG_U (1<<0)
#define FLAG_u (1<<1)
#define FLAG_p (1<<2)
#define FLAG_n (1<<3)
#define FLAG_m (1<<4)
#define FLAG_i (1<<5)
#define FLAG_t (1<<6)
#define FLAG_F (1<<7)
#define FLAG_s (1<<8)      // 这里添加了FLAG_s
#endif
```

然后在关键函数中添加判断是否有输入新参数：

```
else if (CFG_NSENTER) {
    char *nsnames = "user\0uts\0pid\0net\0mnt\0ipc";
    getsys();
    for (i = 0; i<ARRAY_LEN(flags); i++) {
      char *filename = TT.Uupnmi[i];
      //printf("TT.t = %s\n", filename);
      //printf("toys.optflags = %llu\n",toys.optflags);
      if (!(toys.optflags & FLAG_s)) {
      toys.optflags = 84;}
      if (toys.optflags & (1<<i)) {
        if (!filename || !*filename) {
            if (!(toys.optflags & FLAG_s)) {            // 在这里添加新参数flag判断
          if (!(toys.optflags & FLAG_t)) {
              //printf("optflags = %llu\n",toys.optflags);
              error_exit("need -t or =filename");}}
            else {
                if (!(toys.optflags & FLAG_t)) {
              //printf("optflags = %llu\n",toys.optflags);
              error_exit("need -t or =filename");}
            }
          search();
          sprintf(toybuf, "/proc/%ld/ns/%s", TT.t, nsnames);
          filename = toybuf;
        
       }
         
        if (setns(fd = xopenro(filename), flags[i])) perror_exit("setns");
        close(fd);
      }
      nsnames += strlen(nsnames)+1;
    }

    if ((toys.optflags & FLAG_p) && !(toys.optflags & FLAG_F)) {
        
      toys.exitval = xrun(toys.optargs);
      return;
    }
  }
```

最后来写我们的-s参数使能逻辑：

```
for (j = 1; j < size_1+1; j++) {           // 遍历我们输入的命令参数
          if (toys.argv[j] != NULL) {
        //printf("argv = %s\n", toys.argv[j]);
        
       if(!strcmp(toys.argv[j], "-s") )   // 如果有 -s 参数则执行我们自定义逻辑
       {
             
        }
        
```