with source as (

    select * from {{ source('dunnhumby', 'product') }}

),

renamed as (

    select
        product_id,
        manufacturer as manufacturer_id,
        nullif(trim(department), '') as department,
        brand,
        
        case 
            when commodity_desc like 'NO %' then null 
            else nullif(trim(commodity_desc), '') 
        end as commodity_description,

        case 
            when sub_commodity_desc like 'NO %' then null 
            else nullif(trim(sub_commodity_desc), '') 
        end as sub_commodity_description,

        nullif(trim(curr_size_of_product), '') as size_of_product,
        _loaded_at,
        _batch_id

    from source


)

select * from renamed