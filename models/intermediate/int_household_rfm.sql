with transactions as (

    -- marchandise uniquement : le carburant et les lignes non marchandes
    -- gonfleraient la fréquence de visite et fausseraient la composition du panier
    select transactions.*
    from {{ ref('int_transactions__priced') }} as transactions
    inner join {{ ref('int_products__classified') }} as products
        on transactions.product_id = products.product_id
    where not products.is_non_merchandise

),

reference_day as (

    -- dernier jour observé dans les données, toutes lignes valides confondues :
    -- c'est une propriété de la livraison, pas des achats analysés
    select max(day_number) as as_of_day
    from {{ ref('int_transactions__priced') }}

),

grouped_transactions as (

    -- niveau panier : un ticket = une ligne
    select
        household_id,
        basket_id,
        max(day_number) as day_number,
        sum(customer_paid_amount) as basket_amount,
        sum(manufacturer_coupon_discount + store_coupon_match_discount) as basket_coupon_amount
    from transactions
    group by household_id, basket_id

),

household_stats as (

    -- niveau foyer : agrège les paniers, pas les lignes produits
    select
        household_id,
        max(day_number) as last_visit_day,
        count(basket_id) as number_of_visits,
        avg(basket_amount) as average_basket,
        sum(basket_amount) as total_customer_paid_amount,
        avg(basket_coupon_amount) as average_coupon_amount,
        sum(basket_coupon_amount) as total_customer_coupon_amount
    from grouped_transactions
    group by household_id

),

final as (

    -- seuls les foyers ayant acheté de la marchandise : dim_households
    -- complète avec les autres foyers (colonnes RFM à null)
    select
        household_stats.household_id,
        household_stats.last_visit_day,
        reference_day.as_of_day - household_stats.last_visit_day as days_since_last_visit,
        household_stats.number_of_visits,
        household_stats.average_basket,
        household_stats.total_customer_paid_amount,
        household_stats.average_coupon_amount,
        household_stats.total_customer_coupon_amount
    from household_stats
    cross join reference_day

),

scores as (

    select
        *,
        cast(ceil(5 * cume_dist() over (order by days_since_last_visit desc)) as integer) as recency_score,
        cast(ceil(5 * cume_dist() over (order by number_of_visits)) as integer) as frequency_score,
        cast(ceil(5 * cume_dist() over (order by total_customer_paid_amount)) as integer) as monetary_score,
        cast((frequency_score + monetary_score) / 2 as number(2, 1)) as value_score
    from final

),

segments as (

    select
        *,
        -- grille récence x valeur, lue dans l'ordre :
        -- actif = recency_score >= 3 (venu dans les 9 derniers jours)
        -- valeur haute >= 4,5 / moyenne 3 à 4 / basse <= 2,5
        case
            when recency_score >= 3 and value_score >= 4.5 then 'champions'
            when recency_score >= 3 and value_score >= 3 then 'loyal'
            when recency_score >= 3 then 'occasional'
            when value_score >= 3 then 'at_risk'
            else 'hibernating'
        end as rfm_segment
    from scores

)

select * from segments



