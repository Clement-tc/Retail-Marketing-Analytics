{{ config (

    materialized = 'incremental',
    unique_key = ['basket_id','product_id'],
    incremental_strategy = 'merge'
)   }}

with transactions as (

    select * 
    from {{ ref('int_transactions__priced') }}

    {% if is_incremental() %}
    where _loaded_at > (select dateadd(day, -{{ var('incremental_lookback_days', 3) }}, max(_loaded_at)) from {{ this }})
    {% endif %}
),

final as (

    select
        -- clés
        basket_id,
        product_id,
        household_id,
        store_id,
        day_number,
        week_number,
        transaction_time_hhmm,

        -- mesures
        quantity,
        sales_value,
        loyalty_discount,
        manufacturer_coupon_discount,
        store_coupon_match_discount,
        total_discount_amount,
        gross_amount,
        customer_paid_amount,
        gross_unit_price,

        -- technique (pour l'incrémental, étape 5)
        _loaded_at

    from transactions

)

select * from final