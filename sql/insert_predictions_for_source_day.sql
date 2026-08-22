-- source_dayとその前日の実績から、翌日の予想を作成する。
-- 対象はマイジャグラーのみ。
-- 次回以降はsource_dayだけを最新実績日に変更する。
--
-- 判定優先順位:
--   1. 前日がREG 1/300以下、BIG 1/300以上 → 不発据え置き候補
--   2. 2日間のいずれかがREG 1/300以下 → 回避候補
--   3. 2日間ともREG 1/300超       → 上げ候補
--   4. 上記以外                         → 判定保留
-- 前日に存在するマイジャグラーは全台保存する。

with params as (
  select date '2026-08-22' as source_day
),
daily as (
  select
    p.source_day,
    s.day::date as data_day,
    s.shopid,
    s.slotid::text as slotid,
    s.name,
    nullif(replace(trim(s.count::text), ',', ''), '')::numeric as spins,
    nullif(replace(trim(s.big::text), ',', ''), '')::numeric as big,
    nullif(replace(trim(s.reg::text), ',', ''), '')::numeric as reg,
    round(
      coalesce(
        nullif(replace(trim(s.big::text), ',', ''), '')::numeric,
        0
      ) * 240
      + coalesce(
        nullif(replace(trim(s.reg::text), ',', ''), '')::numeric,
        0
      ) * 96
      - coalesce(
        nullif(replace(trim(s.count::text), ',', ''), '')::numeric,
        0
      ) * (50::numeric / 40),
      0
    ) as estimated_medal,
    case
      when nullif(replace(trim(s.reg::text), ',', ''), '')::numeric > 0
        then nullif(replace(trim(s.count::text), ',', ''), '')::numeric
          / nullif(replace(trim(s.reg::text), ',', ''), '')::numeric
      else null
    end as reg_denominator,
    case
      when nullif(replace(trim(s.big::text), ',', ''), '')::numeric > 0
        then nullif(replace(trim(s.count::text), ',', ''), '')::numeric
          / nullif(replace(trim(s.big::text), ',', ''), '')::numeric
      else null
    end as big_denominator
  from public.slot as s
  cross join params as p
  where s.day::date in (
    p.source_day - 1,
    p.source_day
  )
    and s.name ilike '%マイジャグラー%'
),
two_days as (
  select
    source_day,
    shopid,
    slotid,
    max(name) filter (where data_day = source_day) as name,

    max(spins) filter (where data_day = source_day - 1) as spins_previous,
    max(big) filter (where data_day = source_day - 1) as big_previous,
    max(reg) filter (where data_day = source_day - 1) as reg_previous,
    max(estimated_medal) filter (where data_day = source_day - 1) as estimated_medal_previous,
    max(reg_denominator) filter (where data_day = source_day - 1) as reg_denominator_previous,

    max(spins) filter (where data_day = source_day) as spins_current,
    max(big) filter (where data_day = source_day) as big_current,
    max(reg) filter (where data_day = source_day) as reg_current,
    max(estimated_medal) filter (where data_day = source_day) as estimated_medal_current,
    max(reg_denominator) filter (where data_day = source_day) as reg_denominator_current,
    max(big_denominator) filter (where data_day = source_day) as big_denominator_current
  from daily
  group by source_day, shopid, slotid
),
classified as (
  select
    *,
    case
      -- 前日のREGは良いがBIGが付かなかった台を最優先にする。
      when spins_current >= 5000
        and reg_current > 0
        and reg_denominator_current <= 300
        and (big_current = 0 or big_denominator_current >= 300)
        then 'hold_misfire'

      -- 2日間のどちらかに高設定傾向があれば回避する。
      when (
        spins_previous >= 5000
        and reg_previous > 0
        and reg_denominator_previous <= 300
      ) or (
        spins_current >= 5000
        and reg_current > 0
        and reg_denominator_current <= 300
      )
        then 'avoid_recent_high'

      -- 2日間とも十分回され、どちらもREGが1/300を超えた台。
      when spins_previous >= 5000
        and spins_current >= 5000
        and (reg_previous = 0 or reg_denominator_previous > 300)
        and (reg_current = 0 or reg_denominator_current > 300)
        then 'raise_candidate'

      else 'marginal'
    end as prediction_type
  from two_days
  -- 台の入れ替えを避けるため、前日にも存在する台だけを対象にする。
  where name is not null
)
insert into public.predictions (
  prediction_day,
  source_through_day,
  shopid,
  slotid,
  name,
  score,
  positive_probability,
  grade,
  reasons,
  model_version
)
select
  source_day + 1,
  source_day,
  shopid,
  slotid,
  name,
  -(
    coalesce(estimated_medal_previous, 0)
    + coalesce(estimated_medal_current, 0)
  ) as score,
  null as positive_probability,
  prediction_type as grade,
  jsonb_build_array(
    jsonb_build_object(
      'day', to_char(source_day - 1, 'YYYY-MM-DD'),
      'spins', spins_previous,
      'reg_denominator', round(reg_denominator_previous, 1),
      'estimated_medal', estimated_medal_previous
    ),
    jsonb_build_object(
      'day', to_char(source_day, 'YYYY-MM-DD'),
      'spins', spins_current,
      'reg_denominator', round(reg_denominator_current, 1),
      'big_denominator', round(big_denominator_current, 1),
      'estimated_medal', estimated_medal_current
    )
  ) as reasons,
  'myjuggler_2day_v1' as model_version
from classified
on conflict (prediction_day, shopid, slotid, model_version)
do update set
  source_through_day = excluded.source_through_day,
  name = excluded.name,
  score = excluded.score,
  positive_probability = excluded.positive_probability,
  grade = excluded.grade,
  reasons = excluded.reasons,
  updated_at = now();

-- 挿入結果の確認
select
  prediction_day,
  shopid,
  grade,
  count(*) as machines
from public.predictions
where prediction_day = (
    select max(prediction_day)
    from public.predictions
    where model_version = 'myjuggler_2day_v1'
  )
  and model_version = 'myjuggler_2day_v1'
group by prediction_day, shopid, grade
order by shopid, grade;
