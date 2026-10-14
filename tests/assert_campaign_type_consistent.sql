-- le type de campagne doit être le même dans les deux tables
select
    ch.household_id,
    ch.campaign_id,
    ch.campaign_type,
    c.campaign_type as expected_type
from {{ ref('stg_dunnhumby__campaign_households') }} as ch
inner join {{ ref('stg_dunnhumby__campaigns') }} as c
    on ch.campaign_id = c.campaign_id
where ch.campaign_type <> c.campaign_type