-- recalcule l'uplift stratifié d'une campagne sans passer par int_campaign_uplift__stratified,
-- puis le compare au modèle. attendu : by_hand = model
-- dbt show --select check_campaign_uplift_by_hand --vars "{campaign_id: 8}"

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

),

by_band as (

    select
        spend_band,
        count_if(is_targeted) as n_targeted,
        count_if(not is_targeted) as n_control,
        avg(iff(is_targeted, daily_spend_change, null))
            - avg(iff(not is_targeted, daily_spend_change, null)) as band_uplift
    from banded
    group by spend_band

)

select
    {{ campaign_id }} as campaign_id,
    sum(iff(n_targeted >= {{ min_size }} and n_control >= {{ min_size }}, band_uplift * n_targeted, 0))
        / nullif(sum(iff(n_targeted >= {{ min_size }} and n_control >= {{ min_size }}, n_targeted, 0)), 0) as by_hand,
    (select stratified_daily_uplift
     from {{ ref('int_campaign_uplift__stratified') }}
     where campaign_id = {{ campaign_id }}) as model
from by_band
