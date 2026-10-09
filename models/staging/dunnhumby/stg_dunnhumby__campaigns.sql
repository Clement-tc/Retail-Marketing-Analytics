with source as (
    select * from {{source('dunnhumby','campaign_desc')}}
),

renamed as (

    select 
        campaign as campaign_id,
        description as campaign_type,
        start_day,
        end_day,
        _LOADED_AT,
        _BATCH_ID
    from source
)

select * from renamed