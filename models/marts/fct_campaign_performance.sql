with campaign_households_agg as (

    select * from {{ ref('int_campaign_households__aggregated') }}

),

stratified_uplift as (

    select * from {{ ref('int_campaign_uplift__stratified') }}

),

household_count as (

    select count(*) as household_count
    from {{ ref('int_households__unioned') }}

),

coupons as (

    -- une ligne par campagne
    select
        campaign_id,
        count(distinct coupon_upc) as coupons_distributed
    from {{ ref('stg_dunnhumby__coupons') }}
    group by campaign_id

),

coupon_redemptions as (

    -- une ligne par campagne
    select
        campaign_id,
        count(distinct household_id) as redeeming_households,
        count(*) as coupons_redeemed
    from {{ ref('stg_dunnhumby__coupon_redemptions') }}
    group by campaign_id

),

campaign_stats as (

    -- une ligne par campagne ; dépenses journalières moyennes des foyers actifs avant
    select
        campaign_id,
        days_in_period,
        is_complete,
        count_if(is_targeted) as targeted_households,
        count_if(not is_targeted and not is_in_other_campaign) as control_households,

        avg(iff(is_targeted and spend_before > 0, daily_spend_before, null)) as targeted_daily_spend_before,
        avg(iff(is_targeted and spend_before > 0, daily_spend_during, null)) as targeted_daily_spend_during,
        avg(iff(not is_targeted and not is_in_other_campaign and spend_before > 0, daily_spend_before, null)) as control_daily_spend_before,
        avg(iff(not is_targeted and not is_in_other_campaign and spend_before > 0, daily_spend_during, null)) as control_daily_spend_during,

        avg(iff(is_targeted and is_in_other_campaign and spend_before > 0, daily_spend_before, null)) as overlap_daily_spend_before,
        avg(iff(is_targeted and is_in_other_campaign and spend_before > 0, daily_spend_during, null)) as overlap_daily_spend_during,
        avg(iff(is_targeted and not is_in_other_campaign and spend_before > 0, daily_spend_before, null)) as targeted_only_daily_spend_before,
        avg(iff(is_targeted and not is_in_other_campaign and spend_before > 0, daily_spend_during, null)) as targeted_only_daily_spend_during,
        avg(iff(not is_targeted and is_in_other_campaign and spend_before > 0, daily_spend_before, null)) as excluded_daily_spend_before,
        avg(iff(not is_targeted and is_in_other_campaign and spend_before > 0, daily_spend_during, null)) as excluded_daily_spend_during,

        count_if(is_targeted and is_in_other_campaign) / nullif(count_if(is_targeted), 0) as pct_targeted_in_other_campaign

    from campaign_households_agg
    group by all

),

final as (

    select
        -- description de la campagne
        campaigns.campaign_id,
        campaigns.campaign_type,
        campaigns.start_day,
        campaigns.end_day,
        campaign_stats.days_in_period,
        campaign_stats.is_complete,

        -- précision fixée dans le modèle (taux : 4 décimales, euros par jour : 4, totaux en euros : 2) ;
        -- l'arrondi d'affichage se fait dans Power BI, pour ne pas cumuler d'erreurs d'arrondi

        -- composition et portée
        campaign_stats.targeted_households,
        cast(campaign_stats.targeted_households / household_count.household_count as number(6, 4)) as reach_pct,
        campaign_stats.control_households,
        cast(campaign_stats.pct_targeted_in_other_campaign as number(6, 4)) as overlap_pct,
        coalesce(coupons.coupons_distributed, 0) as coupons_distributed,
        coalesce(coupon_redemptions.redeeming_households, 0) as redeeming_households,
        coalesce(coupon_redemptions.coupons_redeemed, 0) as coupons_redeemed,
        cast(coalesce(coupon_redemptions.redeeming_households, 0)
            / nullif(campaign_stats.targeted_households, 0) as number(6, 4)) as redemption_rate,

        -- dépense journalière moyenne par foyer actif (ciblés et témoins propres)
        cast(campaign_stats.targeted_daily_spend_before as number(10, 4)) as targeted_spend_before,
        cast(campaign_stats.targeted_daily_spend_during as number(10, 4)) as targeted_spend_during,
        cast(campaign_stats.control_daily_spend_before as number(10, 4)) as control_spend_before,
        cast(campaign_stats.control_daily_spend_during as number(10, 4)) as control_spend_during,

        -- effet de la campagne, null tant que la campagne n'est pas complète
        -- mesure principale : comparaison à dépense égale avant campagne (stratifiée)
        stratified_uplift.active_targeted_households,
        cast(stratified_uplift.stratified_daily_uplift as number(10, 4)) as uplift_per_day,
        cast(stratified_uplift.stratified_daily_uplift
            / nullif(campaign_stats.targeted_daily_spend_before, 0) as number(6, 4)) as uplift_pct,
        cast(stratified_uplift.stratified_daily_uplift
            * stratified_uplift.active_targeted_households
            * campaign_stats.days_in_period as number(12, 2)) as incremental_sales,
        -- intervalle de confiance à 95 % : uplift ± 1,96 x erreur type
        cast(stratified_uplift.stratified_daily_uplift - 1.96 * stratified_uplift.stratified_daily_uplift_se
            as number(10, 4)) as uplift_per_day_ci_low,
        cast(stratified_uplift.stratified_daily_uplift + 1.96 * stratified_uplift.stratified_daily_uplift_se
            as number(10, 4)) as uplift_per_day_ci_high,
        -- effet démontré si l'intervalle exclut 0 (null si non mesurable)
        stratified_uplift.stratified_daily_uplift - 1.96 * stratified_uplift.stratified_daily_uplift_se > 0
            as is_significant,
        cast(stratified_uplift.pct_targeted_in_valid_bands as number(6, 4)) as uplift_coverage_pct,
        coalesce(stratified_uplift.active_targeted_households, 0) < 50 as is_low_sample,
        -- contrôle de robustesse : foyers ciblés par cette seule campagne
        stratified_uplift.active_targeted_only_households,
        cast(stratified_uplift.stratified_daily_uplift_targeted_only as number(10, 4)) as uplift_per_day_no_overlap,
        -- méthode naïve : ciblés contre tous les témoins, biaisée par la sélection des ciblés
        cast(iff(
            campaign_stats.is_complete,
            (campaign_stats.targeted_daily_spend_during - campaign_stats.targeted_daily_spend_before)
                - (campaign_stats.control_daily_spend_during - campaign_stats.control_daily_spend_before),
            null
        ) as number(10, 4)) as uplift_per_day_naive,

        -- détail des groupes, pour l'analyse
        cast(campaign_stats.overlap_daily_spend_before as number(10, 4)) as overlap_spend_before,
        cast(campaign_stats.overlap_daily_spend_during as number(10, 4)) as overlap_spend_during,
        cast(campaign_stats.targeted_only_daily_spend_before as number(10, 4)) as targeted_only_spend_before,
        cast(campaign_stats.targeted_only_daily_spend_during as number(10, 4)) as targeted_only_spend_during,
        cast(campaign_stats.excluded_daily_spend_before as number(10, 4)) as excluded_spend_before,
        cast(campaign_stats.excluded_daily_spend_during as number(10, 4)) as excluded_spend_during

    from {{ ref('stg_dunnhumby__campaigns') }} as campaigns
    inner join campaign_stats
        on campaigns.campaign_id = campaign_stats.campaign_id
    cross join household_count
    left join coupons
        on campaigns.campaign_id = coupons.campaign_id
    left join coupon_redemptions
        on campaigns.campaign_id = coupon_redemptions.campaign_id
    left join stratified_uplift
        on campaigns.campaign_id = stratified_uplift.campaign_id

)

select * from final
