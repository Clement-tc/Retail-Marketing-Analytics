-- un coupon ne peut être utilisé que pendant sa campagne
select
    r.household_id,
    r.coupon_upc,
    r.campaign_id,
    r.day_number,
    c.start_day,
    c.end_day
from {{ ref('stg_dunnhumby__coupon_redemptions') }} as r
inner join {{ ref('stg_dunnhumby__campaigns') }} as c
    on r.campaign_id = c.campaign_id
where r.day_number not between c.start_day and c.end_day