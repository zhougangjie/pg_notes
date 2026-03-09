# PostgreSQL 锁系统学习笔记（从一个最小例子理解整体）

本文以一个 **最简单的并发 UPDATE 场景** 为起点，梳理 PostgreSQL 锁系统的核心机制和结构，作为后续深入源码的基础。

系统：PostgreSQL

---

# 1 示例场景

表：

```sql
create table t(
  id int primary key,
  v int
);

insert into t values (1,10);
```

两个事务：

事务 T1

```sql
begin;
update t set v = 20 where id = 1;
```

事务 T2

```sql
begin;
update t set v = 30 where id = 1;
```

结果：

```
T2 被阻塞
```

这个简单场景已经涉及 PostgreSQL 锁系统的大部分核心机制。

---

# 2 这个例子涉及的锁类型

| 类型                        | 作用         |
| --------------------------- | ------------ |
| 表锁 (Heavyweight Lock)     | 防止 DDL     |
| 行锁 (Tuple Lock)           | 控制并发更新 |
| 事务锁 (TransactionID Lock) | 等待事务结束 |
| 等待队列                    | 管理阻塞进程 |
| 唤醒机制                    | 锁释放时唤醒 |

---

# 3 T1 执行 UPDATE 时发生的事情

调用链（简化）

```
ExecUpdate
  ↓
heap_update
```

会发生三件关键事情：

## 3.1 获取表锁

锁模式：

```
RowExclusiveLock
```

锁对象：

```
relation t
```

入口函数：

```
LockAcquire()
```

锁对象类型：

```
LOCKTAG_RELATION
```

作用：

```
防止 DDL
例如：
DROP TABLE
ALTER TABLE
```

---

## 3.2 读取 tuple

读取 tuple header：

```
xmin = 插入事务
xmax = 0
```

含义：

```
当前没有事务锁定这行
```

---

## 3.3 加行锁

PostgreSQL 行锁不在 Lock Manager 中，而是存储在 **tuple header**：

字段：

```
xmax
```

更新后：

```
xmin = 原事务
xmax = T1
```

含义：

```
T1 正在修改这行
```

---

# 4 T2 执行 UPDATE

调用链：

```
ExecUpdate
  ↓
heap_update
```

---

## 4.1 获取表锁

T2 也会获取：

```
RowExclusiveLock
```

但该锁模式：

```
RowExclusiveLock vs RowExclusiveLock
是兼容的
```

因此：

```
不会阻塞
```

---

## 4.2 读取 tuple

T2 读取 tuple header：

```
xmin = 原事务
xmax = T1
```

说明：

```
该行正在被 T1 修改
```

关键函数：

```
HeapTupleSatisfiesUpdate()
```

返回：

```
TM_BeingModified
```

---

# 5 T2 等待 T1

触发等待：

```
XactLockTableWait(T1)
```

作用：

```
等待事务 T1 结束
```

锁对象：

```
LOCKTAG_TRANSACTION
```

即：

```
transaction id = T1
```

调用：

```
LockAcquire(xid)
```

由于 T1 持有该锁：

```
T2 -> ProcSleep()
```

进入等待。

---

# 6 等待队列结构

等待关系：

```
TransactionLock(T1)
      ↓
     LOCK
      ↓
  wait queue
      ↓
   PGPROC(T2)
```

进程结构：

```
PGPROC
  waitLock = xid(T1)
```

---

# 7 T1 提交

执行：

```
commit
```

调用流程：

```
CommitTransaction
   ↓
ProcArrayEndTransaction
   ↓
LockReleaseAll
```

释放：

```
LOCKTAG_TRANSACTION(T1)
```

---

# 8 唤醒 T2

锁释放后：

```
GrantLock
   ↓
ProcWakeup
```

唤醒等待进程。

---

# 9 T2 重新检查 tuple

被唤醒后：

```
重新检查 tuple
```

此时：

```
T1 已提交
```

tuple 状态：

```
xmin = T1
xmax = T1
```

含义：

```
该行已被更新
```

T2 会继续执行更新逻辑。

---

# 10 PostgreSQL 并发控制模型

PostgreSQL 并发控制核心：

```
MVCC + 锁
```

分工：

| 机制             | 作用         |
| ---------------- | ------------ |
| MVCC             | 读不阻塞     |
| Tuple Lock       | 行更新冲突   |
| Transaction Lock | 等待事务结束 |
| Table Lock       | 防止 DDL     |

---

# 11 PostgreSQL 锁系统核心结构

Lock Manager 结构：

```
LOCKTAG -> LOCK -> PROCLOCK -> PGPROC
```

含义：

```
锁对象 -> 锁状态 -> 进程关系 -> 进程
```

结构关系：

```
Shared Memory

LockHashTable
     ↓
   LOCKTAG
     ↓
    LOCK
    /  \
   /    \
PROCLOCK PROCLOCK
   |        |
  PGPROC   PGPROC
```

---

# 12 等待机制

锁冲突时：

```
LockAcquire
   ↓
ProcSleep
```

锁释放时：

```
LockRelease
   ↓
GrantLock
   ↓
ProcWakeup
```

---

# 13 这个例子覆盖的机制

已覆盖：

| 机制     | 是否涉及 |
| -------- | -------- |
| 表锁     | ✓        |
| 行锁     | ✓        |
| 事务锁   | ✓        |
| 等待队列 | ✓        |
| 唤醒机制 | ✓        |

未涉及：

```
deadlock detection
multixact
lwlock
spinlock
```

---

# 14 推荐扩展学习顺序

基于本例逐步扩展：

1️⃣ Transaction Lock

```
XactLockTableWait
```

2️⃣ Lock Manager 核心

```
LockAcquire
ProcSleep
ProcWakeup
```

3️⃣ 死锁检测

```
deadlock.c
DeadLockCheck
```

4️⃣ MultiXact（多事务行锁）

```
multixact.c
```

5️⃣ Lightweight Lock

```
lwlock.c
```

---

# 15 核心理解一句话

PostgreSQL 锁系统本质是：

```
共享内存 hash table
+
等待队列
+
进程结构
```

解决的问题只有一个：

```
谁在等待谁
```
