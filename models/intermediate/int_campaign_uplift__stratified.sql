{% set n_bands = var('uplift_spend_bands') %}
{% set min_size = var('uplift_min_households_per_band') %}

with campaign_households as (

    select * from {{ ref('int_campaign_households__aggregated') }}

),

compared as (

    -- foyers comparés : ciblés + témoins propres, actifs avant la campagne,
    -- campagnes complètes uniquement (période « pendant » entièrement livrée)
    select
        campaign_id,
        household_id,
        is_targeted,
        is_targeted and not is_in_other_campaign as is_targeted_only,
        daily_spend_before,
        daily_spend_during - daily_spend_before as daily_spend_change
    from campaign_households
    where is_complete
      and spend_before > 0
      and (is_targeted or not is_in_other_campaign)

),

banded as (

    -- tranche de dépense avant campagne, calculée par campagne sur les foyers comparés ;
    -- cume_dist plutôt que ntile pour que deux foyers ex aequo tombent dans la même tranche
    select
        *,
        ceil({{ n_bands }} * cume_dist() over (
            partition by campaign_id
            order by daily_spend_before
        )) as spend_band
    from compared

),

by_band as (

    -- différence de différences dans chaque tranche
    select
        campaign_id,
        spend_band,
        count_if(is_targeted) as targeted_households,
        count_if(is_targeted_only) as targeted_only_households,
        count_if(not is_targeted) as control_households,
        avg(iff(is_targeted, daily_spend_change, null))
            - avg(iff(not is_targeted, daily_spend_change, null)) as band_uplift,
        avg(iff(is_targeted_only, daily_spend_change, null))
            - avg(iff(not is_targeted, daily_spend_change, null)) as band_uplift_targeted_only,
        -- variance de l'uplift de la tranche : var(ciblés) / n_ciblés + var(témoins) / n_témoins
        variance(iff(is_targeted, daily_spend_change, null)) / nullif(count_if(is_targeted), 0)
            + variance(iff(not is_targeted, daily_spend_change, null)) / nullif(count_if(not is_targeted), 0)
            as band_uplift_variance
    from banded
    group by campaign_id, spend_band

),

flagged as (

    -- une tranche ne compte que si chaque groupe y a assez de foyers
    select
        *,
        targeted_households >= {{ min_size }} and control_households >= {{ min_size }} as is_valid_band,
        targeted_only_households >= {{ min_size }} and control_households >= {{ min_size }} as is_valid_band_targeted_only
    from by_band

),

weighted as (

    -- poids de chaque tranche valide : sa part des foyers ciblés des tranches valides
    select
        *,
        iff(is_valid_band, targeted_households, 0)
            / nullif(sum(iff(is_valid_band, targeted_households, 0)) over (partition by campaign_id), 0)
            as band_weight
    from flagged

),

final as (

    -- moyenne des tranches valides, pondérée par les foyers ciblés de chaque tranche
    -- (effet moyen sur les foyers effectivement ciblés)
    select
        campaign_id,
        sum(targeted_households) as active_targeted_households,
        sum(control_households) as active_control_households,
        count_if(is_valid_band) as valid_bands,

        sum(iff(is_valid_band, band_uplift * targeted_households, 0))
            / nullif(sum(iff(is_valid_band, targeted_households, 0)), 0) as stratified_daily_uplift,
        sum(iff(is_valid_band, targeted_households, 0))
            / nullif(sum(targeted_households), 0) as pct_targeted_in_valid_bands,

        -- erreur type de l'uplift : racine de la somme des poids² x variance de chaque tranche ;
        -- intervalle à 95 % = uplift ± 1,96 x erreur type (approximation normale)
        sqrt(sum(iff(is_valid_band, band_weight * band_weight * band_uplift_variance, 0)))
            as stratified_daily_uplift_se,

        -- contrôle de robustesse : ciblés par cette seule campagne
        sum(targeted_only_households) as active_targeted_only_households,
        sum(iff(is_valid_band_targeted_only, band_uplift_targeted_only * targeted_only_households, 0))
            / nullif(sum(iff(is_valid_band_targeted_only, targeted_only_households, 0)), 0)
            as stratified_daily_uplift_targeted_only

    from weighted
    group by campaign_id

)

select * from final
