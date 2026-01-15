
# 语义分析 `parse_analyze_fixedparams`

## Overview

### 语义分析任务

语义分析: 将以 `RawStmt` 节点为根的原始解析树(Parse Tree)，转换为 Query 节点树

1. 相关函数: `parse_analyze_fixedparams`

2. 核心流程

`RawStmt/parsetree` ----> `parse analysis（analyze.c）` + `ParseState` ----> `Query`

3. 关键结构：

- `ParseState`: 语义分析的工作上下文（working context），转换 `ParseTree` 为 `Query` 结构的**临时结构**，生成 `Query` 后丢弃

```cpp
/* State information used during parse analysis */
struct ParseState
{
	const char *p_sourcetext;	/* source text, or NULL if not available */
	List	   *p_rtable;		/* range table so far */
	List	   *p_joinexprs;	/* JoinExprs for RTE_JOIN p_rtable entries */
	List	   *p_joinlist;		/* join items so far (will become FromExpr node's fromlist) */
	List	   *p_namespace;	/* currently-referenceable RTEs (List of ParseNamespaceItem) */
	ParseNamespaceItem *p_target_nsitem;	/* target rel's NSItem, or NULL */
	int			p_next_resno;	/* next targetlist resno to assign */
	/* ... */
};
```

- `Query`

```cpp
typedef struct Query
{
	NodeTag		type;

	CmdType		commandType;	/* select|insert|update|delete|merge|utility */

	/* where did I come from? */
	QuerySource querySource pg_node_attr(query_jumble_ignore);

	/* ... */
	Node	   *utilityStmt;	/* non-null if commandType == CMD_UTILITY */
	/* ... */
	List	   *rtable;			/* list of range table entries */
	/* ... */
	List	   *targetList;		/* target list (of TargetEntry) */
	/* ... */
	Node	   *havingQual;		/* qualifications applied to groups */
	/* ... */
} Query;
```

---

### 查询分类

`transformStmt` 处理三种不同查询 `select`(`select into` 会被视为 `create table as`，在 `transformOptionalselectInto` 中处理)

```cpp
exec_simple_query - pg_analyze_and_rewrite_fixedparams - pg_analyze_and_rewrite_fixedparams
	transformTopLevelStmt - transformOptionalselectInto
		transformStmt
			| transformValuesClause      /* values (1, 2); */
			| transformselectStmt        /* select a, b from tb; */
			| transformSetOperationStmt  /* select a, b from tb union values (1, 2);*/
```

```sql
DROP TABLE IF EXISTS tb;
CREATE TABLE tb  AS select n AS a, n * 10 AS b, n * 100 AS c FROM generate_series(1, 5) AS n;
select a, b FROM tb where a = 2;
```

### 对象层级关系

| 层级         | 中文名称        | 核心作用                           | 唯一标识        | 关联系统表     |
| ------------ | --------------- | ---------------------------------- | --------------- | -------------- |
| Database     | 数据库          | 最高级隔离单元（独立的系统表集合） | `OID`           | `pg_database`  |
| Schema       | 模式 / 名称空间 | 数据库内的逻辑隔离单元             | `OID`           | `pg_namespace` |
| **Relation** | 关系            | 模式内的核心对象（表/索引/视图等） | `OID`           | `pg_class`     |
| Column       | 字段            | 关系内的最小数据单元               | `OID`+`attrnum` | `pg_attribute` |

参考文档：

- https://postgres-internals.cn/docs/chapter01/
- https://www.interdb.jp/pg/pgsql01/02.html
- [download pdAdmin 4](https://www.pgadmin.org/download/)

### 查询分析总体流程

`transformselectStmt`

```cpp
transformselectStmt
	transformFromClause 		/* from tb */
	transformTargetList 		/* select a, b */
	transformWhereClause		/* where a = 2 */
	transformSortClause
	transformGroupClause
	transformDistinctClause
	transformLimitClause
	transformWindowDefinitions
	transformLockingClause
	/* ... */
```

## 分析表名 `from tb`

函数: `transformFromClause(pstate, stmt->fromClause);` + `transformFromClauseItem`
任务: Process the FROM clause and add items to the query's range table, joinlist, and namespace.

### 表的多种抽象形式

1. 文本标识: `tb --- Identifier —— RangeVar`
2. 语法分析: `RangeVar --- selectStmt::fromClause`
3. 语义分析: `RangeTableEntry --- ParseState::p_rtable --- Query::p_rtable`
4. 名称空间: `NamespaceItem --- ParseState::p_namespace`
5. 优化结构: `RelOptInfo`: TODO
6. 关系缓存: `Relation ---- relation_open()`
7. 持久数据: `pg_class` + `pg_attribute`, `pg_attrdef`, `pg_index`, `pg_constraint`, `pg_rewrite`, ...

```text
SQL: FROM tb
   ↓
RangeVar       —— 名字
   ↓
RangeTblEntry  —— 语义对象（作用域）
   ↓
Var            —— 列绑定（编号）
   ↓
RelOptInfo     —— 优化对象（代价）
   ↓
Relation       —— 物理对象（存储）
```

`Query`查询树中的关键抽象: `Range Table`(范围清单) : A range table is a List of `RangeTblEntry` nodes.

```cpp
typedef struct Query
{
    /* ... */
    List   *rtable;  /* list of range table entries: RangeTblEntry */
    /* ... */
} Query;

typedef struct RangeTblEntry
{
    RTEKind     rtekind;  /* Range kind */
    Oid 	    relid; 	  /* OID of the relation */
	char		relkind;  /* relation kind */
    /* ... */
} RangeTblEntry;

typedef enum RTEKind
{
	RTE_RELATION, /* ordinary relation reference */
	RTE_SUBQUERY, /* subquery in FROM */
	RTE_JOIN,     /* join */
	/* ... */
} RTEKind;
```

```cpp
transformFromClause
	transformFromClauseItem
		transformTableEntry
			addRangeTableEntry
				RangeVar -> parserOpenTable() -> Relation
					/* build RTE */
				pstate->p_rtable = lappend(pstate->p_rtable, rte);
				buildNSItemFromTupleDesc
```

- 通过语法分析得到的表名称被封装在 `RangeVar` 变量中
- `parserOpenTable`语义分析的重要任务: 访问元数据检索`Relation`
- 将 `relid` 添加到 `RangeTblEntry` 中并构建名称空间`Item`以供后续分析列

### 检索表结构`Relation`

`parserOpenTable` 如何根据 `RangeVar`(表名) 找到 `Relation` 结构？

1. 核心缓存定义

`RelCache` (关系描述符缓存)

- 本质：表的句柄，以动态哈希表存储 `RelationData` (重型对象)
- 内容：封装元组描述、锁信息及存储状态，是内核操作表的物理入口
- 约束：底层物理检索仅支持 `relid` 唯一键【无法直接通过`RangeVar`检索】

`SysCache` (系统元组缓存)

- 缓存：建立在系统表唯一索引（常用索引）之上的内存哈希缓存
- 封装：`CatCTup`，封装了来自基表的完整元组（Heap Tuple）
- 优势：无需“回表”。一旦命中，直接返回指向内存副本的指针，性能比索引扫描快数十倍

`pg_class`上的索引：

```sql
"pg_class_oid_index" PRIMARY KEY, btree (oid)
"pg_class_relname_nsp_index" UNIQUE CONSTRAINT, btree (relname, relnamespace)
```

对应的`SysCache`缓存：

```
SysCache[RELOID]
SysCache[RELNAMENSP]
```

2 `parserOpenTable` 执行逻辑

1. 获取`relid` (`RangeVar`->`relid`)

   1. 由于 `RelCache` 不支持字符串查找，内核首先访问 `SysCache`（具体为 `RELNAMENSP` 缓存）
   2. 利用 `RangeVar` 提供的表名和 Schema 信息进行匹配，获取该表的唯一身份id：`relid`

2. 查找表结构 (`relid`->`Relation`)
   1. 拿到 `relid` 后，内核转而访问 `RelCache`
   2. 通过 `relid` 这一唯一键检索 `RelationIdCache` 哈希表

`RangeVar` --> `relid` --> `Relation`

```cpp
parserOpenTable /* parser/parse_relation.c: parser support routines dealing with relations */
	table_openrv_extended /* access/table/table.c: Generic routines for table related code*/
		relation_openrv_extended /* access/common/relation.c: Generic relation related routines */
			relOid = RangeVarGetRelidExtended /* catlog/namespace.c: searching namespaces */
			relation_open(relOid) /* access/common/relation.c: open any relation by relation OID */
				Relation	rd;
				RelationIdCacheLookup /* utils/cache/relcache.c: Lookup a reldesc by OID */
				RelationIncrementReferenceCount
				return rd;
```

`RangeVarGetRelidExtended` 内部查找过程

```cpp
RangeVarGetRelidExtended
	RelnameGetRelid
		get_relname_relid  /* utils/cache/lsyscache.c: routines for common queries in system catalog cache */
			GetSysCacheOid /* utils/cache/syscache.c: System cache management routines*/
				tuple = SearchSysCache /* get tuple */
					SearchCatCache /* utils/cache/catcache.c: System catalog cache for tuples matching a key*/
						SearchCatCacheInternal /* hash and iterate */
				return heap_getattr(tuple, oidcol, ...);
```

系统目录缓存管理抽象层次：

- `lsyscache.c`: 封装 `syscache` 的轻量 API
- `syscache.c`: 逻辑索引缓存管理层
- `catcache.c`: 底层元组缓存实现

### 系统表缓存 `SysCache`

![](SysCache.png)

> https://cloud.tencent.com/developer/article/2000765?from_column=20421&from=20421

## 添加名称空间 `buildNSItemFromTupleDesc`

为什么 PG 需要“名称空间” (NSItem)？

### 两种别名方式

1. `select a as x, b as y from tb;`

2. `select x, y, c from tb as t(x, y);`（仅PG支持）

在 PostgreSQL 中，这两种方式分别对应 **“投影别名”** 和 **“数据源别名”**。

| 方式 | 语法示例 | 生效阶段 | 核心作用 |
| --- | --- | --- | --- |
| **投影别名** | `select a AS x ...` | **输出层** (Output) | **修饰性**：主要为了改变最终结果集的抬头，或者给表达式（如 `a+b`）取名。 |
| **数据源别名** | `FROM tb AS t(x, y)` | **输入层** (Input) | **结构性**：在数据进入查询树时，就彻底重定义了该表的逻辑结构。 |

### 为什么需要数据源别名

尽管第一种方式（投影别名）看起来更直观，但在处理复杂逻辑时，第二种方式（数据源别名）具有不可替代的优势：

1. **解决“无名数据”的定义问题**

这是最核心的需求。对于 `VALUES` 子句、解构函数（如 `unnest`）或子查询，它们产生的数据往往没有物理列名。

* 投影别名：无法在数据源处定义名称，导致 `WHERE` 或 `JOIN` 子句无法引用这些列。
* 数据源别名：在 `FROM` 处直接给这些匿名列封装为表的形式，让整个查询块都能合法引用它们。

一下两种场景必须使用数据源别名

```sql
select a from (values (1), (2), (3)) as tb(a) where a < 3;

select * FROM unnest(array[1, 2, 3]) AS t(val) WHERE val > 1;
```

2. **实现“逻辑与物理”的解耦（位置绑定）**

* 投影别名：是基于名字的。如果底层表字段从 `a` 改名为 `a_new`，你必须修改 `select a_new AS x`。
* 数据源别名：是基于位置的。`t(x, y)` 永远绑定该表的第 1 列和第 2 列。SQL无需变化。

3. **简化复杂查询的引用**

* 投影别名：在标准 SQL 中，`select` 里的别名通常不能在同级的 `WHERE` 中直接使用，因为 `WHERE` 的执行早于 `select`。
* 数据源别名：由于在 `FROM` 阶段就完成了定义，别名 `x, y` 在后续所有的 `WHERE`、`JOIN`、`GROUP BY` 中都是全局可见的“真名”。

```sql
select a as x, b as y, c from tb as t where x < 3; -- 失败
select x, y  from tb2 as t(x, y) where x < 3;
```

4. **内核处理的一致性 (buildNSItem)**

在内核底层，`AS t(x, y)` 会直接驱动 `buildNSItemFromTupleDesc` 创建一个**完整的逻辑视图**。

* 如果使用方式一，内核需要维护一套复杂的“别名追踪机制”来确保 `ORDER BY` 能找到 `select` 里的 `x`。
* 如果使用方式二，内核直接把 `x` 存入 `NSItem` 的逻辑入口。对解析器来说，`x` 就是这列的“本名”，处理起来路径更短、性能更高。

5. **局限性**

不适用超宽表的部分列起别名，如1000列的表要为第800列其别名，按位置绑定时只能前八百列都起名占位，此时用`a as x`更好。

![400](assets/namespaceitem.png)

## 分析列名 `select a, b`

`qry->targetList = transformTargetList`

```cpp
transformTargetList /* parser/parse_target.c */
	transformTargetEntry
		transformExpr /* parser/parser_expr.c */
			transformExprRecurse
				transformColumnRef
					colNameToVar /* parser/parser_relation.c*/
						scanNSItemForColumn
							scanRTEForColumn /* Scan the nsitem's column names (or aliases) for a match */
								foreach(c, eref->colnames) /* Scan the user column names (or aliases) for a match */
								specialAttNum(colname) /* quick check to see if name could be a system column */
									SystemAttributeByName /* ctid, xmin, cmin, xmax, cmax, tableoid */
								SearchSysCacheExists2
		FigureColname
		makeTargetEntry /* creates a TargetEntry node */
```

> Entry 后缀：某类实体的标准化描述单元，代表 “一个可枚举、可管理的独立条目”，PostgreSQL 源码中大量使用 XXXEntry 命名的结构体，核心设计思路是：将某一类 “有明确边界、可独立描述、需纳入集合管理” 的实体，封装为 XXXEntry 结构体，作为该类实体的最小描述单元。
>
> - 独立性：每个 Entry 描述一个独立的实体（如 RTE 描述一个表 / 子查询，TE 描述一个目标列）；
> - 可枚举：多个 Entry 会被组织为列表（List \*）管理（如 Query->rtable 是 RTE 列表，Query->targetList 是 TE 列表）；
> - 结构化：通过字段完整描述实体的核心属性，覆盖 “身份、类型、属性、关联关系”；
> - 贯穿性：从解析阶段生成，到优化 / 执行阶段全程复用，是查询生命周期的核心数据载体。

## 分析过滤条件 `where a = 2`

`qry->sortClause = transformSortClause`

```cpp
transformWhereClause
	transformExpr
		transformExprRecurse
			transformAExprOp
				lexpr = transformExprRecurse(pstate, lexpr);
					transformColumnRef
				rexpr = transformExprRecurse(pstate, rexpr);
					make_const
				make_op
					oper(pstate, opname, ltypeId, rtypeId, false, location);
						make_oper_cache_key
						find_oper_cache_entry
				result->opno = oprid(tup); /* pg_operator: oid=96 | oprname='=' | oprcode='int4eq' */
				result->opfuncid = opform->oprcode; /*op_proc: oid=65 | proname='int4eq' */
				result->args = args
```

<!-- 

## 查询重写

1. 相关函数: `pg_rewrite_query`

2. 核心结构：`Query` 

-->