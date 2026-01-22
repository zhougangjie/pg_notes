# Storage

## table and file

```sql
-- 空表初始文件 0 KB
create table tbl (a int);

-- 插入第一行数据，文件扩展为 8 KB
insert into tbl values (1);

-- 获取表的文件路径
select pg_relation_filepath('tbl');
```

![](assets/page.png)

## `pageinspect` 介绍

- PostgreSQL 提供的一个内省扩展模块
- 允许用户通过 SQL 界面直接观察磁盘数据页（Page）的原始二进制内容及元数据结构
- 代码位于 `postgres/contrib/pageinspect/`，编译后使用 

```sh
# 1. 自动获取PG服务端头文件目录（模糊化安装路径） 
PG_INCLUDE=$(<PG_INSTALL_DIR>/bin/pg_config --includedir-server) 

# 2. 编译扩展（指定PG版本+头文件路径） 
make PG_CONFIG=<PG_INSTALL_DIR>/bin/pg_config CPPFLAGS="-I$PG_INCLUDE" 

# 3. 安装扩展（指定PG版本） 
make install PG_CONFIG=<PG_INSTALL_DIR>/bin/pg_config
```

psql 客户端运行

```sql
create extension pageinspect;
```

常用函数说明：

- `get_raw_page`: 从磁盘读取原始 8KB 数据块
- `page_header`: 查看 LSN、lower、upper 等页头元数据
- `heap_page_items`: 解析行指针和元组头（xmin, xmax）

- `bt_page_items`: 查看索引记录及其指向的元组地址
- `heap_page_item_attrs`: 解码字段内容

## page

查询页头信息

```sql
select * from page_header(get_raw_page('tbl', 0));
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
|    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
| 0/2926898 |        0 |     0 |    28 |  8160 |    8192 |     8192 |       4 |         0 |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
```

继续插入两条数据

```sql
insert into tbl values (1), (1);
```

再次查询页头信息

```sql
select * from page_header(get_raw_page('tbl', 0));
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
|    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
| 0/2926978 |        0 |     0 |    36 |  8096 |    8192 |     8192 |       4 |         0 |
+-----------+----------+-------+-------+-------+---------+----------+---------+-----------+
```

- lower += 8
- upper -= 64

```cpp
typedef struct PageHeaderData
{
	/* XXX LSN is member of *any* block, not only page-organized ones */
	PageXLogRecPtr pd_lsn;		/* LSN */
	uint16		pd_checksum;	/* checksum */
	uint16		pd_flags;		/* flag bits, see below */
	LocationIndex pd_lower;		/* offset to start of free space */
	LocationIndex pd_upper;		/* offset to end of free space */
	LocationIndex pd_special;	/* offset to start of special space */
	uint16		pd_pagesize_version;
	TransactionId pd_prune_xid; /* oldest prunable XID, or zero if none */
	ItemIdData	pd_linp[FLEXIBLE_ARRAY_MEMBER]; /* line pointer array */
} PageHeaderData;
```

## update

```sql
-- 执行一次更新，制造旧版本数据
UPDATE test_mvcc SET val = 'world' WHERE id = 1;
```