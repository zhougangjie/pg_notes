# Executor

## ExecutePlan

Processes the query plan until we have retrieved 'numberTuples' tuples, moving in the specified direction.

```cpp
/*
* Loop until we've processed the proper number of tuples from the plan.
*/

ResetPerTupleExprContext(estate); /* Reset the per-output-tuple exprcontext */
slot = ExecProcNode(planstate); /* Execute the plan and obtain a tuple */
dest->receiveSlot(slot, dest)
printtup(TupleTableSlot *slot, DestReceiver *self) /* send a tuple to the client */

/*
    * Count tuples processed, if this is a SELECT.  (For other operation
    * types, the ModifyTable plan node must count the appropriate
    * events.)
    */
if (operation == CMD_SELECT)
    (estate->es_processed)++;

/*
    * check our tuple count.. if we've processed the proper number then
    * quit, else loop again and process more tuples.  Zero numberTuples
    * means no limit.
    */
current_tuple_count++;
if (numberTuples && numberTuples == current_tuple_count)
    break;
}
```

交互

```text
执行器 → Access Layer（IndexScan） → Storage Layer → 磁盘
  │          │                          │
  │          ▼                          ▼
  │      1. 解析id=2 → 调用B-Tree接口  1. 读取索引文件块
  │      2. 获取ctid                   2. 返回索引项（ctid）
  │      3. 调用heap_gettuple          3. 读取堆表文件块
  │      4. 校验MVCC可见性             4. 返回tuple（行数据）
  ▼          ▼                          ▼
结果组装 → 返回给Portal → 客户端
```
