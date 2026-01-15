# Planner

## 查询计划

[plannodes.h](..src/include/nodes/plannodes.h)

相关函数: `pg_plan_query`

`PlannedStmt`

```cpp
typedef struct PlannedStmt
{
	pg_node_attr(no_equal, no_query_jumble)
	NodeTag		type;
	CmdType		commandType;	/* select|insert|update|delete|merge|utility */
	uint64		queryId;		/* query identifier (copied from Query) */
	bool		hasReturning;	/* is it insert|update|delete RETURNING? */
	bool		hasModifyingCTE;	/* has insert|update|delete in WITH? */
	struct Plan *planTree;		/* tree of Plan nodes */
	List	   *rtable;			/* list of RangeTblEntry nodes */
	/* ... */
	Node	   *utilityStmt;	/* non-null if this is utility stmt */
}
```

`Plan`

```cpp
typedef struct Plan
{
	pg_node_attr(abstract, no_equal, no_query_jumble)
	NodeTag		type;
	/* estimated execution costs for plan (see costsize.c for more info) */
	Cost		startup_cost;	/* cost expended before fetching any tuples */
	Cost		total_cost;		/* total cost (assuming all tuples fetched) */
	/* planner's estimate of result size of this plan step */
	Cardinality plan_rows;		/* number of rows plan is expected to emit */
	int			plan_width;		/* average row width in bytes */
}
```

`Scan`

```cpp
/*
 * ==========
 * Scan nodes
 *
 * Scan is an abstract type that all relation scan plan types inherit from.
 * ==========
 */
typedef struct Scan
{
	pg_node_attr(abstract)
	Plan		plan;
	Index		scanrelid;		/* relid is index into the range table */
} Scan;
```

```cpp
/* ----------------
 *		sequential scan node
 * ----------------
 */
typedef struct SeqScan
{
	Scan		scan;
} SeqScan;
```

```cpp
typedef struct IndexScan
{
	Scan		scan;
	Oid			indexid;		/* OID of index to scan */
	List	   *indexqual;		/* list of index quals (usually OpExprs) */
	List	   *indexqualorig;	/* the same in original form */
	List	   *indexorderby;	/* list of index ORDER BY exprs */
	List	   *indexorderbyorig;	/* the same in original form */
	List	   *indexorderbyops;	/* OIDs of sort ops for ORDER BY exprs */
	ScanDirection indexorderdir;	/* forward or backward or don't care */
} IndexScan;
```

## Portal

Receiver<---->Portal<---->Executor<---->Access<---->Storage

```cpp
CreatePortal /* Create unnamed portal to run the query or queries in */
PortalDefineQuery /* A simple subroutine to establish a portal's query */
PortalStart /* Prepare a portal for execution */
	CreateQueryDesc /* Create QueryDesc in portal's context */
PortalRun /* Run a portal's query or queries */
PortalDrop /*  */
```

核心结构

- `Portal`
- `QueryDesc`