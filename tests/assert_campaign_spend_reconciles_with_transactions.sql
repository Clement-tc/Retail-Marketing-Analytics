-- la dépense « pendant » du modèle, sommée sur tous les foyers, doit égaler
-- les ventes de marchandise calculées directement sur les transactions.
-- garde-fou contre une condition inversée ou une jointure qui perd des lignes
with model_spend as (

    select campaign_id, sum(spend_during) as model_total
    from {{ ref('int_campaign_households__aggregated') }}
    group by campaign_id

),

direct_spend as (

    select campaigns.campaign_id, sum(transactions.sales_value) as direct_total
    from {{ ref('stg_dunnhumby__campaigns') }} as campaigns
    inner join {{ ref('int_transactions__priced') }} as transactions
        on transactions.day_number between campaigns.start_day and campaigns.end_day
    inner join {{ ref('int_products__classified') }} as products
        on transactions.product_id = products.product_id
    where not products.is_non_merchandise
    group by campaigns.campaign_id

)

select
    model_spend.campaign_id,
    model_spend.model_total,
    coalesce(direct_spend.direct_total, 0) as direct_total
from model_spend
left join direct_spend
    on model_spend.campaign_id = direct_spend.campaign_id
where abs(model_spend.model_total - coalesce(direct_spend.direct_total, 0)) > 0.01
