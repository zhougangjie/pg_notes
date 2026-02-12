# insert

- insert 核心流程梳理，将从最简单的插入数据开始，逐步讨论事务、锁、资源管理等相关内容
- 调试语句：`insert into tb values(1)`

## `exec_simple_query` 流程概览

```cpp
start_xact_command
pg_parse_query
pg_analyze_and_rewrite_fixedparams
pg_plan_queries
PortalDefineQuery
PortalRun | PortalRunMulti | ProcessQuery /* tcop */
EndCommand
finish_xact_command
```

## `exec_simple_query` 流程详解-插入数据

```cpp
/* ... */
pg_plan_queries
CreatePortal
PortalDefineQuery
PortalStart
PortalRun | PortalRunMulti | ProcessQuery /* tcop */
    CreateQueryDesc
    ExecutorStart
    ExecutorRun | standard_ExecutorRun | ExecutePlan | ExecProcNode | ExecProcNodeFirst /* executor */
        ExecModifyTable | ExecInsert /* executor */
            table_tuple_insert       /* access/tableam.h call Relation::TableAmRoutine::tuple_insert */
                heapam_tuple_insert  /* access/heap/heapam_handler.c */
                    heap_insert      /* access/heap/heapam.c */
                        RelationGetBufferForTuple /* access/heap/hio.c */
                        RelationPutHeapTuple      /* access/heap/hio.c */
                            PageAddItemExtended   /* storage/page/bufpage.c */
                        MarkBufferDirty(buffer)   /* storage/buffer/bufmgr.c */
                        XLogInsert /* access/transam/xloginsert.c */
                            XLogRecordAssemble
                            XLogInsertRecord
                        PageSetLSN
    ExecutorFinish
PortalDrop
EndCommand
finish_xact_command
```

## `exec_simple_query` 流程详解-提交事务

```cpp
start_xact_command
pg_parse_query
pg_analyze_and_rewrite_fixedparams
pg_plan_queries
CreatePortal
PortalDefineQuery
PortalStart
PortalRun | PortalRunMulti | ProcessQuery /* tcop */
PortalDrop
EndCommand
finish_xact_command
    CommitTransactionCommand
        CommitTransaction
            s->state = TRANS_COMMIT;
            RecordTransactionCommit
                XactLogCommitRecord
                    XLogInsert
                XLogFlush /* wal -> disk */
                TransactionIdCommitTree
                    TransactionIdSetTreeStatus
                        TransactionIdSetPageStatus
                            TransactionIdSetPageStatusInternal
            s->state = TRANS_DEFAULT;
    xact_started = false;
```


## `exec_simple_query` 流程详解-完整过程

```cpp
start_xact_command
    StartTransactionCommand
        StartTransaction
            s->state = TRANS_START;
            /* initialize current transaction state fields */
            /* ... */
            s->state = TRANS_INPROGRESS;
    xact_started = true;
pg_parse_query
pg_analyze_and_rewrite_fixedparams
pg_plan_queries
CreatePortal
PortalDefineQuery
PortalStart
PortalRun | PortalRunMulti | ProcessQuery /* tcop */
    CreateQueryDesc
    ExecutorStart
    ExecutorRun | standard_ExecutorRun | ExecutePlan | ExecProcNode | ExecProcNodeFirst /* executor */
        ExecModifyTable | ExecInsert /* executor */
            table_tuple_insert       /* access/tableam.h call Relation::TableAmRoutine::tuple_insert */
                heapam_tuple_insert  /* access/heap/heapam_handler.c */
                    heap_insert      /* access/heap/heapam.c */
                        RelationGetBufferForTuple /* access/heap/hio.c */
                        RelationPutHeapTuple      /* access/heap/hio.c */
                            PageAddItemExtended   /* storage/page/bufpage.c */
                        MarkBufferDirty(buffer)   /* storage/buffer/bufmgr.c */
                        XLogInsert /* access/transam/xloginsert.c */
                            XLogRecordAssemble
                            XLogInsertRecord
                        PageSetLSN
    ExecutorFinish
PortalDrop
EndCommand
finish_xact_command
    CommitTransactionCommand
        CommitTransaction
            s->state = TRANS_COMMIT;
            RecordTransactionCommit
                XactLogCommitRecord
                    XLogInsert
                XLogFlush /* wal -> disk */
                TransactionIdCommitTree
                    TransactionIdSetTreeStatus
                        TransactionIdSetPageStatus
                            TransactionIdSetPageStatusInternal
            s->state = TRANS_DEFAULT;
    xact_started = false;
```

