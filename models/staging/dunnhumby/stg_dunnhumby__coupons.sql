
with source as (

    select * from {{ source('dunnhumby', 'coupon') }}

),

renamed as (

    select
        cast(coupon_upc as varchar) as coupon_upc,
        product_id,
        campaign as campaign_id,
        _loaded_at,
        _batch_id

    from source

),


deduplicated as (


    select *
    from renamed
    qualify row_number() over ( 
        partition by coupon_upc , product_id , campaign_id  
        order by _loaded_at desc
    ) = 1
)


select * from deduplicated