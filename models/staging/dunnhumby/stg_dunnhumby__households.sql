with source as (

    select * from {{ source('dunnhumby', 'hh_demographic') }}

),

renamed as (

    select
        household_key as household_id,
        age_desc as age_range,
        marital_status_code,
        income_desc as income_bracket,
        nullif(homeowner_desc, 'Unknown') as ownership_status,
        nullif(hh_comp_desc, 'Unknown') as household_composition,
        household_size_desc as household_Band,
        case
            when kid_category_desc <> 'None/Unknown' then kid_category_desc
            when hh_comp_desc in ('2 Adults No Kids', 'Single Female', 'Single Male') then '0'
            else null
        end as kids_band,
        _loaded_at,
        _batch_id

    from source

)

select * from renamed