
# Buffer Overview

## 核心价值

- **读优化:** 内存比磁盘快几个数量级。数据页首次读取后缓存在内存，后续访问直接命中内存，不再触发慢速磁盘 I/O。
- **写优化:** 修改数据时先只改内存（标记为脏页），然后通过后台进程**异步、批量**刷回磁盘。避免每次修改都直接卡在慢速磁盘写上。

## 内存结构

![](assets/data_buffer.png)

1. Buffer Table

- `SharedBufHash`
- buf_table.c
- mapping BufferTags to buffer indexes

```c
/* entry for buffer lookup hashtable */
typedef struct
{
	BufferTag	key;			/* Tag of a disk page */
	int			id;				/* Associated buffer ID */
} BufferLookupEnt;
```

```c
typedef struct buftag
{
	Oid			spcOid;			/* tablespace oid */
	Oid			dbOid;			/* database oid */
	RelFileNumber relNumber;	/* relation file number */
	ForkNumber	forkNum;		/* fork number */
	BlockNumber blockNum;		/* blknum relative to begin of reln */
} BufferTag;
```

2. `BufferDescriptors`

- `BufferDescPadded *BufferDescriptors;`

```c
typedef struct BufferDesc
{
	BufferTag	tag;			/* ID of page contained in buffer */
	int			buf_id;			/* buffer's index number (from 0) */

	/* state of the tag, containing flags, refcount and usagecount */
	pg_atomic_uint32 state;

	int			wait_backend_pgprocno;	/* backend of pin-count waiter */
	int			freeNext;		/* link in freelist chain */
	LWLock		content_lock;	/* to lock access to buffer contents */
} BufferDesc;
```


3. `BufferBlocks`

- `char *BufferBlocks;`
- shared memory
- shared_buffers = 128M
