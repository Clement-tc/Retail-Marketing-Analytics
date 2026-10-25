-- volume : chaque livraison hebdomadaire doit avoir un nombre de lignes proche de l'habituel,
-- soit la moyenne des lignes par semaine sur les 4 semaines précédentes, à ± volume_tolerance_pct.
-- une livraison incomplète ou envoyée en double passe tous les autres tests : seul ce contrôle la voit.
-- mesuré dans RAW, à l'entrée du pipeline, avant tout nettoyage
{{ config(severity = 'warn') }}

{% set tolerance = var('volume_tolerance_pct') %}

with raw_transactions as (

    select * from {{ source('dunnhumby', 'transaction_data') }}

),

deliveries as (

    -- une ligne par livraison hebdomadaire (l'historique initial n'est pas une livraison)
    select
        _batch_id,
        max(week_no) as delivered_week,
        count(*) as delivered_rows
    from raw_transactions
    where _batch_id <> 'history'
    group by _batch_id

),

rows_per_week as (

    select week_no, count(*) as week_rows
    from raw_transactions
    group by week_no

),

expected as (

    select
        deliveries._batch_id,
        deliveries.delivered_week,
        deliveries.delivered_rows,
        avg(rows_per_week.week_rows) as expected_rows
    from deliveries
    inner join rows_per_week
        on rows_per_week.week_no between deliveries.delivered_week - 4 and deliveries.delivered_week - 1
    group by all

)

select
    _batch_id,
    delivered_week,
    delivered_rows,
    round(expected_rows) as expected_rows,
    round(delivered_rows / expected_rows - 1, 3) as deviation
from expected
where abs(delivered_rows / expected_rows - 1) > {{ tolerance }}
