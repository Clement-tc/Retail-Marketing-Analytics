-- les valeurs extrêmes de l'uplift, avec ce qui permet de juger si on peut s'y fier :
-- taille de l'échantillon, couverture, chevauchement, contrôle de robustesse
-- dbt --quiet show --select check_campaign_uplift_extremes --limit 30

select
    campaign_id,
    campaign_type,
    active_targeted_households,
    round(uplift_per_day, 2) as uplift_per_day,
    round(100 * uplift_pct, 1) as uplift_pct,
    round(100 * uplift_coverage_pct, 1) as coverage_pct,
    round(100 * overlap_pct, 1) as overlap_pct,
    round(uplift_per_day_no_overlap, 2) as uplift_no_overlap,
    is_low_sample
from {{ ref('fct_campaign_performance') }}
where is_complete
order by uplift_per_day desc
