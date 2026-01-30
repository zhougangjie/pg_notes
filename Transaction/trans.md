# Transaction

- 隔离性: https://postgres-internals.cn/docs/chapter02/
- 快照: https://postgres-internals.cn/docs/chapter04/
- 预写式日志: https://postgres-internals.cn/docs/chapter10/
- WAL: https://www.interdb.jp/pg/pgsql09/index.html
- 锁: https://postgres-internals.cn/docs/chapter12/
- 并发: https://www.interdb.jp/pg/pgsql05/index.html

| **事务特性**    | **核心实现方式**                               | **关键补充 (内核视角)**                        |
| ----------- | ---------------------------------------- | -------------------------------------- |
| **隔离性 (I)** | **MVCC** (快照隔离) + **Lock Manager** (锁机制) | DDL 也是基于 MVCC。**2PL (两阶段锁)** 用于处理读写冲突。 |
| **持久性 (D)** | **WAL** (预写日志) + **Checkpointer**        | 还有 **Double Write** 机制（在某些存储环境下）防止半写。  |
| **原子性 (A)** | **CLog** (状态位) + **WAL**                 | 事务提交本质上是修改 CLog 里的 2 个 bit 位。          |
| **一致性 (C)** | 它是 A+I+D 的综合结果 + **数据完整性约束**             | 包括 唯一索引、外键、Check 约束等主动校验。              |
