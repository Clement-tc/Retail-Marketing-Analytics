
with source as (

    select * from {{ source('dunnhumby', 'coupon_redempt') }}

),

renamed as (

    select
        household_key as household_id,
        day as day_number,
        cast(coupon_upc as varchar) as coupon_upc,
        campaign as campaign_id,
        _loaded_at,
        _batch_id

    from source

)

select * from renamed