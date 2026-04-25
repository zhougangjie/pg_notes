# Executor

### 1. 执行器生命周期与核心数据结构

| 阶段                | 核心函数                 | 关键动作                      | 节点操作                                                     |
| :---------------- | :------------------- | :------------------------ | :------------------------------------------------------- |
| **初始化 (Init)**    | `ExecutorStart` <br> | 解析计划树，构建运行时状态树，打开表，编译表达式。 | `ExecInitNode`: **`Plan`** -> **`PlanState`** (动态状态)<br> |
| **执行 (Run)**      | `ExecutorRun` <br>   | 循环拉取数据，逐行处理，发送给客户端。       | `ExecProcNode`: **`TupleTableSlot`**, **`ExprContext`**  |
| **资源清理 (End)**    | `ExecutorEnd` <br>   | 关闭文件/扫描描述符，销毁哈希表/排序临时文件。  | `ExecEndNode`                                            |
| **最终收尾 (Finish)** | `ExecutorFinish`     | 执行排队的 AFTER 触发器，更新统计信息。   | **`AfterTriggerEvent`** (触发器事件队列)                        |

### 2. 关键数据结构详解

#### A. 计划与状态 (The Brain)
*   **`Plan` (Tree)**: **只读、静态**。定义“做什么”（逻辑结构、目标列、过滤条件）。可被缓存共享。
*   **`PlanState` (Tree)**: **读写、动态**。定义“怎么做/做到哪了”（文件句柄、内存指针、进度）。每个查询独占。
    *   **关系**: `PlanState->plan` 指向对应的 `Plan` 节点。

#### B. 数据传递 (The Blood)
*   **`TupleTableSlot`**: 执行器中数据流动的标准容器。
    *   **`ss_ScanTupleSlot`**: 存放从磁盘读取的**原始物理行**。
    *   **`ps_ResultTupleSlot`**: 存放经过投影/计算后的**逻辑输出行**。
    *   **特性**: 单槽复用，一次只存一行，避免内存爆炸。

#### C. 扫描与排序 (The Muscle)
*   **`ScanState`**:
    *   `ss_currentRelation`: 表的元数据。
    *   `ss_currentScanDesc`: **扫描进度控制器**（读到哪个页/行了），而非列描述。
*   **`Tuplesortstate`**:
    *   `memtuples`: 内存中的元组数组（用于收集数据）。
    *   **机制**: 内存满了 -> 排序 -> 溢出到磁盘临时文件 (Run) -> 多路归并。
    *   **优化**: 遇到 `LIMIT` 时，退化为 **Top-K 堆排序**，无需全量排序。

#### D. 暂存与触发器 (The Buffer & Hook)
*   **`Tuplestore`**: 通用元组暂存器。支持**回溯 (Rescan)** 和**透明溢出**。用于 Materialize、CTE、游标。
*   **`AfterTriggerEvent`**: 轻量级事件指针（仅存 CTID）。
    *   **机制**: 行级 AFTER 触发器可以**排队延迟执行**，确保看到语句结束后的**最终一致状态**。

---

### 3. 核心架构思想

1.  **火山模型 (Volcano Model)**: 自顶向下请求 (`ExecProcNode`)，自底向上返回数据。
2.  **动静分离**: `Plan` (静态逻辑) 与 `PlanState` (动态运行时) 分离，实现计划缓存与并发安全。
3.  **流式处理**: 通过 `TupleTableSlot` 的单槽复用，实现极低内存占用的大规模数据处理。
4.  **外部排序**: 通过 `Tuplesortstate` 的内存-磁盘协同，解决超出 `work_mem` 的大数据集排序问题。

这个框架保证了 PostgreSQL 既能处理复杂的 OLTP 事务，也能应对大规模的 OLAP 分析查询。

```
/* Portal & Executor */

CreatePortal

PortalDefineQuery // portal->stmts = plantree_list;

PortalStart // Prepare a portal for execution. params, strategy, queryDesc
	ExecutorStart // prepare the plan for execution
		standard_ExecutorStart
			InitPlan /* Initialize the plan state tree */
				ExecInitNode
					ExecInitSeqScan
						ExecOpenScanRelation
	PORTAL_READY

PortalRun - PortalRunSelect

	/* 5. Executor */
	ExecutorRun - tandard_ExecutorRun - ExecutePlan // Processes the query plan until retrieved 'numberTuples' tuples
		ExecProcNode - ExecSeqScan
			ExecScan - ExecScanFetch - SeqNext // executor module
				/* Access + Storage*/
				table_scan_getnextslot - heap_getnextslot - heapgettup_pagemode
					heapgetpage - ReadBufferExtended -  ReadBuffer_common

						LockBuffer(buffer, BUFFER_LOCK_SHARE);

						BufferGetPage - BufferGetBlock
							return (Block) (BufferBlocks + ((Size) (buffer - 1)) * BLCKSZ);
						for (lineoff = FirstOffsetNumber; lineoff <= lines; lineoff++)
							PageGetItemId // Returns an item identifier of a page.
								return &((PageHeader) page)->pd_linp[offsetNumber - 1];
							PageGetItem // Retrieves an item on the given page.
								return (Item) (((char *) page) + ItemIdGetOffset(itemId));

						// True if heap tuple satisfies a time qual
						HeapTupleSatisfiesVisibility - HeapTupleSatisfiesMVCC

						LockBuffer(buffer, BUFFER_LOCK_UNLOCK);

					ExecStorePinnedBufferHeapTuple // buffer tuple -> tuple table
						tts_buffer_heap_store_tuple
							IncrBufferRefCount
							return slot;
				ExecProject
PortalDrop
```