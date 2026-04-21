PostgreSQL 中三种 MemoryContext 核心区别（极简版）：

1. AllocSetContext (默认, aset.c)
	- 定位：通用万能型，PG 默认内存上下文
	- 特点：维护多块内存，按大小分空闲链表 (freelist)，可复用碎片
	- 适用：任意大小、混合分配、频繁随机 free 的常规场景

2. GenerationContext (generation.c)
	- 定位：代/批量释放型（FIFO、同生命周期组）
	- 特点：不重用单个 free 块；整块只有全空才释放
	- 适用：同生命周期对象

3. SlabContext (slab.c)
	- 定位：固定大小对象池
	- 特点：只能分配创建时指定的固定大小；无碎片、O(1) 分配/释放
	- 适用：同尺寸对象
