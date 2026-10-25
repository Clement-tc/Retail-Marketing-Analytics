-- vérifie le grain de int_campaign_households__aggregated : une ligne par campagne x foyer
-- attendu : n_rows = n_keys = expected_rows, null_keys = 0
-- dbt show --select check_campaign_households_grain

with model as (

    select * from {{ ref('int_campaign_households__aggregated') }}

),

duplicates as (

    -- clés présentes plusieurs fois (group by, qui compte aussi les clés contenant un null)
    select campaign_id, household_id
    from model
    group by campaign_id, household_id
    having count(*) > 1

)

select
    (select count(*) from model) as n_rows,
    (select count(distinct campaign_id, household_id) from model) as n_keys,
    (select count(*) from duplicates) as duplicated_keys,
    (select count_if(campaign_id is null or household_id is null) from model) as null_keys,
    (select count(*) from {{ ref('stg_dunnhumby__campaigns') }})
        * (select count(*) from {{ ref('int_households__unioned') }}) as expected_rows
