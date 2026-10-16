with transactions as (

    select * from {{ ref('stg_dunnhumby__transactions') }}
    where rejection_reason is null

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
        loyalty_discount + manufacturer_coupon_discount + store_coupon_match_discount as total_discount_amount,
        sales_value + loyalty_discount + store_coupon_match_discount as gross_amount,
        sales_value - manufacturer_coupon_discount as customer_paid_amount,
        (sales_value + loyalty_discount + store_coupon_match_discount) / nullif(quantity, 0) as gross_unit_price,

        -- technique (pour l'incrémental, étape 5)
        _loaded_at

    from transactions

)

select * from final