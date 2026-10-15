with products as (

    select *
    from {{ ref('stg_dunnhumby__products') }}
),


final as (

        select
        product_id,
        manufacturer_id,
        department,
        brand,
        commodity_description,
        sub_commodity_description,
        size_of_product,

        coalesce(sub_commodity_description = 'GASOLINE-REG UNLEADED', false) as is_fuel,
        -- le carburant n'est pas de la marchandise, quelle que soit sa catégorie
        is_fuel
            or coalesce(commodity_description in ('COUPON/MISC ITEMS', 'COUPONS/STORE & MFG', 'COUPON'), false)
            as is_non_merchandise

        from products
)

select *
from final