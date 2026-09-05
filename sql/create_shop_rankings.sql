-- 店舗・日付・機種ごとのRANK集計。
-- 元のslotテーブルでRLSとanonのSELECT権限が設定済みであることが前提。
create or replace view public.shop_rankings
with (security_invoker = true)
as
select
  day,
  shopid,
  name,
  count(*)::integer as total_machines,
  count(*) filter (where trim(rank::text) = '4')::integer as rank4_count,
  count(*) filter (where trim(rank::text) = '5')::integer as rank5_count,
  count(*) filter (where trim(rank::text) = '6')::integer as rank6_count,
  count(*) filter (
    where trim(rank::text) in ('4', '5', '6')
  )::integer as rank456_count,
  count(*) filter (
    where trim(rank::text) in ('5', '6')
  )::integer as rank56_count,
  round(
    100.0 * count(*) filter (
      where trim(rank::text) in ('4', '5', '6')
    ) / nullif(count(*), 0),
    1
  ) as rank456_rate
from public.slot
group by day, shopid, name;

create or replace view public.shop_rankings_day_list
with (security_invoker = true)
as
select distinct day
from public.slot;

create or replace view public.shop_rankings_name_list
with (security_invoker = true)
as
select distinct day, name
from public.slot
where name is not null;

revoke all on public.shop_rankings from anon, authenticated;
revoke all on public.shop_rankings_day_list from anon, authenticated;
revoke all on public.shop_rankings_name_list from anon, authenticated;

grant select on public.shop_rankings to anon, authenticated;
grant select on public.shop_rankings_day_list to anon, authenticated;
grant select on public.shop_rankings_name_list to anon, authenticated;
