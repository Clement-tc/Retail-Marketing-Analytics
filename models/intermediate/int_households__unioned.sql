with households as (
    select household_id from {{ ref('stg_dunnhumby__households') }}
    union
    select household_id from {{ ref('stg_dunnhumby__transactions') }}
    union
    select household_id from {{ ref('stg_dunnhumby__campaign_households') }}
)

select * from households