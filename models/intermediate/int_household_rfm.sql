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

)

select * from final
