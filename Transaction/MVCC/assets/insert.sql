drop table if exists tb;
create table tb(a int);

select txid_current();
select txid_current();

begin;
select txid_current();
select txid_current();
insert into tb values (1);

-- psql2: select from tb; 对另一事务不可见

select * from page_header(get_raw_page('tb', 0));

select lp, lp_off, lp_flags, lp_len, t_xmin, t_xmax, t_field3, t_ctid, t_infomask from heap_page_items(get_raw_page('tb', 0));

-- `lp`: 行指针序号
-- `lp_off`: 页面内物理偏移量
-- `lp_flags`: 状态标记(1: LP_NORMAL， 2: REDIRECT, 3: DEAD, 0: UNUSED)
-- `lp_len`: 元组长度。这行数据（含头+数据+对齐）总共占用了 28 字节，实际存储占用 32 字节（8 字节对齐）
-- `t_xmin`: 插入事务 ID。表示这个元组是由事务号为 t_xmin 的操作创建的
-- `t_xmax`: 删除/锁定事务 ID。0 表示该行目前是“活的”，尚未被删除或更新
-- `t_field3`: 命令 ID (t_cid)。表示这是事务 t_xmin 里的第几个命令（从 0 开始计数，纯 select 不参与计数）
-- `t_ctid`: 物理指针, 指向最新版本（此时自己就是最新版本，所以指向自己）
-- `t_infomask`: 状态信息， `HEAP_XMAX_INVALID`

commit;

select lp, lp_off, lp_flags, lp_len, t_xmin, t_xmax, t_field3, t_ctid, t_infomask from heap_page_items(get_raw_page('tb', 0));

-- psql2: select from tb; 此时对另一事务可见，且更新 t_infomask 状态信息

select lp, lp_off, lp_flags, lp_len, t_xmin, t_xmax, t_field3, t_ctid, t_infomask from heap_page_items(get_raw_page('tb', 0));

-- `t_infomask` 变为 2304 = 2048 + 256 = `HEAP_XMIN_COMMITTED` + `HEAP_XMAX_INVALID`
-- 解释：基于 Hint Bits 的延迟状态更新
