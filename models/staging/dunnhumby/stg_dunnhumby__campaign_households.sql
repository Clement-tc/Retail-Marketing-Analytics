with source as (

    select * from {{source('dunnhumby', 'campaign_table')}}
),

renamed as (

    select 
        household_key as household_id,
        campaign as campaign_id,
        description as campaign_type, 
        _LOADED_AT,
        _BATCH_ID
    from source
)

select *
from renamed
