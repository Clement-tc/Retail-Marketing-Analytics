-- détail d'une campagne tranche par tranche : effectifs, évolution des ciblés et des témoins,
-- uplift de la tranche. utile pour comprendre d'où vient l'effet (ou son absence)
-- dbt show --select explore_campaign_uplift_bands --vars "{campaign_id: 8}"

{% set campaign_id = var('campaign_id', 8) %}
{% set n_bands = var('uplift_spend_bands') %}
{% set min_size = var('uplift_min_households_per_band') %}

with compared as (

    select
        is_targeted,
        daily_spend_before,
        daily_spend_during - daily_spend_before as daily_spend_change
    from {{ ref('int_campaign_households__aggregated') }}
    where campaign_id = {{ campaign_id }}
      and spend_before > 0
      and (is_targeted or not is_in_other_campaign)

),

banded as (

    select
        *,
        ceil({{ n_bands }} * cume_dist() over (order by daily_spend_before)) as spend_band
    from compared

)

select
    spend_band,
    round(min(daily_spend_before), 2) as min_spend_before,
    round(max(daily_spend_before), 2) as max_spend_before,
    count_if(is_targeted) as n_targeted,
    count_if(not is_targeted) as n_control,
    round(avg(iff(is_targeted, daily_spend_change, null)), 2) as targeted_change,
    round(avg(iff(not is_targeted, daily_spend_change, null)), 2) as control_change,
    round(avg(iff(is_targeted, daily_spend_change, null))
        - avg(iff(not is_targeted, daily_spend_change, null)), 2) as band_uplift,
    count_if(is_targeted) >= {{ min_size }} and count_if(not is_targeted) >= {{ min_size }} as is_valid_band
from banded
group by spend_band
order by spend_band
