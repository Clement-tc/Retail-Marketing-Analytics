-- toute ligne livrée en retard par le simulateur doit arriver dans fct_transactions,
-- ou être rejetée en staging avec un motif (une ligne en retard peut aussi être abîmée).
-- c'est la preuve que le filtre incrémental sur _loaded_at rattrape les retards :
-- un filtre sur la date d'achat les aurait perdues
with late_rows as (

    select distinct
        batch_id,
        basket_id,
        product_id
    from {{ source('dunnhumby', 'simulator_log') }}
    where defect_type = 'late_arrival'

),

checked as (

    select
        late_rows.batch_id,
        late_rows.basket_id,
        late_rows.product_id,
        fct.basket_id is not null as is_in_fct,
        staging.rejection_reason
    from late_rows
    left join {{ ref('fct_transactions') }} as fct
        on late_rows.basket_id = fct.basket_id
        and late_rows.product_id = fct.product_id
    left join {{ ref('stg_dunnhumby__transactions') }} as staging
        on late_rows.basket_id = staging.basket_id
        and late_rows.product_id = staging.product_id

)

-- en échec : les lignes en retard ni chargées, ni rejetées avec un motif
select *
from checked
where not is_in_fct
  and rejection_reason is null
