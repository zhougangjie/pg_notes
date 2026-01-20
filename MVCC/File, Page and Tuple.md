![](assets/page.png)

# pageinspect 插件基本使用

```sql
CREATE EXTENSION pageinspect;

drop table if exists test_mvcc;
CREATE TABLE test_mvcc (id int);
INSERT INTO test_mvcc VALUES (1);
```

## file

```sql
-- 空表初始文件 0 KB
CREATE TABLE tbl (a INT);

-- 插入第一行数据，文件扩展为 8 KB
INSERT INTO tbl VALUES (1);

-- 获取表的文件路径
SELECT pg_relation_filepath('tbl');
```

## page

```sql
SELECT * FROM page_header(get_raw_page('test_mvcc', 0));
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
|    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
| 0/2892280 |        0 |     0 |    28 |  8160 |    8192 |     8192 |       4 |         0 |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
```

## tuple

`HeapTupleData`: 元组在内存中的管理工具（内存句柄）
`HeapTupleHeaderData`: 元组在磁盘上的二进制布局（物理实体）
```cpp
/* HeapTupleData is an in-memory data structure that points to a tuple */
typedef struct HeapTupleData
{
	uint32		t_len;			/* length of *t_data */
	ItemPointerData t_self;		/* SelfItemPointer */
	Oid			t_tableOid;		/* table the tuple came from */
	HeapTupleHeader t_data;		/* -> tuple header and data */
} HeapTupleData;
```

```cpp
struct HeapTupleHeaderData
{
	union
	{
		HeapTupleFields t_heap;
		DatumTupleFields t_datum;
	}			t_choice;
	ItemPointerData t_ctid;		/* current TID of this or newer tuple */
	uint16		t_infomask2;	/* number of attributes + various flags */
	uint16		t_infomask;		/* various flag bits, see below */
	uint8		t_hoff;			/* sizeof header incl. bitmap, padding */
	/* ^ - 23 bytes - ^ */
    
	bits8		t_bits[FLEXIBLE_ARRAY_MEMBER];	/* bitmap of NULLs */

	/* MORE DATA FOLLOWS AT END OF STRUCT */
};
```

## update

```sql
-- 执行一次更新，制造旧版本数据
UPDATE test_mvcc SET val = 'world' WHERE id = 1;
```