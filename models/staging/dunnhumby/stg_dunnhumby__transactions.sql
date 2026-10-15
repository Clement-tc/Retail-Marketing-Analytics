
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
        -1 * cast(retail_disc as number(10,2)) as loyalty_discount,
        trans_time as transaction_time_hhmm,
        week_no as week_number,
        -1 * cast(coupon_disc as number(10,2)) as manufacturer_coupon_discount,
        -1 * cast(coupon_match_disc as number(10,2)) as store_coupon_match_discount,
        case
            when product_id is null then 'missing_product_id'
            when quantity < 0 then 'negative_quantity'
        end as rejection_reason,
        _loaded_at,
        _batch_id

    from source

),



deduplicated as (

    select *
    from renamed
    qualify row_number() over( 
        partition by product_id , basket_id 
        order by _loaded_at desc
    ) = 1
    -- les lignes sans product_id ne sont pas dédoublonnées : elles seraient fusionnées entre elles
    or product_id is null
)

select * from deduplicated