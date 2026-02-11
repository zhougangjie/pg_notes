# insert

## `insert into tb values(1)`

```cpp
exec_simple_query
    start_xact_command
        StartTransactionCommand
            StartTransaction
                s->state = TRANS_START;
                /* initialize current transaction state fields */
                /* ... */
                s->state = TRANS_INPROGRESS;
        xact_started = true;
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
                table_tuple_insert /* access/tableam.h call Relation::TableAmRoutine::tuple_insert */
                    heapam_tuple_insert /* access/heap/heapam_handler.c */
                        heap_insert /* access/heap/heapam.c */
                            RelationGetBufferForTuple /* access/heap/hio.c */
                            RelationPutHeapTuple /* access/heap/hio.c */
                                PageAddItemExtended /* storage/page/bufpage.c */
                            XLogInsert /* access/transam/xloginsert.c */
                                XLogRecordAssemble
                                XLogInsertRecord
        ExecutorFinish
    PortalDrop
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
