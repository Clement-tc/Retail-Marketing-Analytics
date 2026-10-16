with households_unioned as (

    select *
    from {{ ref('int_households__unioned')}}
),

household_rfm as (

    select *
    from {{ ref('int_household_rfm')}}
),

households_info as (

    select *
    from {{ ref('stg_dunnhumby__households')}}
),

income_brackets as (

    select *
    from {{ ref('income_brackets')}}
),


final as (

    select
        -- clé : la liste complète, jamais null
        households_unioned.household_id,

        -- segmentation RFM (renseignée pour tous les foyers)
        -- un foyer sans achat de marchandise n'est pas dans le calcul RFM
        coalesce(household_rfm.rfm_segment, 'no_merchandise_purchase') as rfm_segment,
        household_rfm.recency_score,
        household_rfm.frequency_score,
        household_rfm.monetary_score,
        household_rfm.value_score,

        -- comportement d'achat (marchandise uniquement)
        household_rfm.last_visit_day,
        household_rfm.days_since_last_visit,
        household_rfm.number_of_visits,
        household_rfm.average_basket,
        household_rfm.total_customer_paid_amount,
        household_rfm.average_coupon_amount,
        household_rfm.total_customer_coupon_amount,

        -- profil démographique (801 foyers sur 2 499, null pour les autres)
        households_info.household_id is not null as has_demographics,
        households_info.age_range,
        households_info.marital_status_code,
        households_info.marital_status,
        households_info.income_bracket,
        
        -- income brackets sort tools
        income_brackets.sort_order as income_sort_order,
        income_brackets.min_income,

        households_info.ownership_status,
        households_info.household_composition,
        households_info.household_band,
        households_info.kids_band


    from households_unioned
    left join household_rfm
        on households_unioned.household_id = household_rfm.household_id
    left join households_info
        on households_unioned.household_id = households_info.household_id
    left join income_brackets
        on households_info.income_bracket=income_brackets.income_bracket
)

select *
from final