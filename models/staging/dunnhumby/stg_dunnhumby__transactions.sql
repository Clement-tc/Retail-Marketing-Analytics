
with source as (

    select * from {{ source('dunnhumby', 'transaction_data') }}

),

renamed as (

    select
        household_key as household_id,
        basket_id,
        day as day_number,
        product_id,
        quantity,
        cast(sales_value as number(10,2)) as sales_value,
        store_id,
        -1 * cast(retail_disc as number(10,2)) as retail_discount,
        trans_time as transaction_time_hhmm,
        week_no as week_number,
        -1 * cast(coupon_disc as number(10,2)) as coupon_discount,
        -1 * cast(coupon_match_disc as number(10,2)) as coupon_match_discount,
        _loaded_at,
        _batch_id

    from source

)

select * from renamed