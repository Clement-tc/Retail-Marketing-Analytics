with campaign_info as (
    select *
    from {{ ref('stg_dunnhumby__campaigns')}}
),

campaign_household as (

    select *
    from {{ ref('stg_dunnhumby__campaign_households')}}

),

household as (

    select *
    from {{ ref('int_households__unioned')}}

),

reference_day as (
    select max(day_number) as as_of_day
    from {{ ref('int_transactions__priced') }}
),



transactions as(
    select 
    household_id,
    day_number,
    sum(iff(products.is_non_merchandise, 0, sales_value)) as daily_sales_value
    from {{ ref('int_transactions__priced') }} as transac
    left join {{ ref('int_products__classified') }} as products on transac.product_id = products.product_id
    group by household_id, day_number
),

campaign_windows as (

    -- une ligne par campagne, avec sa fenêtre complète (avant + pendant)
    select
        campaign_id,
        start_day,
        end_day,
        end_day - start_day + 1 as days_in_period,
        start_day - (end_day - start_day + 1) as window_start_day
    from campaign_info

),

grid as (

    select
        campaign_windows.campaign_id,
        household.household_id,
        campaign_windows.start_day,
        campaign_windows.end_day,
        campaign_windows.days_in_period,
        campaign_windows.window_start_day,
        campaign_household.household_id is not null as is_targeted,

        -- le foyer est-il ciblé par une AUTRE campagne qui chevauche
        -- la fenêtre de celle-ci (avant + pendant) ?
        exists (
            select 1
            from campaign_household as ch2
            inner join campaign_windows as cw2
                on ch2.campaign_id = cw2.campaign_id
            where ch2.household_id = household.household_id
              and ch2.campaign_id <> campaign_windows.campaign_id
              and (
                  -- l'autre campagne commence dans la fenêtre
                  cw2.start_day between campaign_windows.window_start_day and campaign_windows.end_day
                  -- ou elle se termine dans la fenêtre
                  or cw2.end_day between campaign_windows.window_start_day and campaign_windows.end_day
                  -- ou elle englobe toute la fenêtre
                  or (cw2.start_day < campaign_windows.window_start_day and cw2.end_day > campaign_windows.end_day)
              )
        ) as is_in_other_campaign,

        campaign_windows.end_day <= reference_day.as_of_day as is_complete

    from household
    cross join campaign_windows
    cross join reference_day
    left join campaign_household
        on household.household_id = campaign_household.household_id
        and campaign_windows.campaign_id = campaign_household.campaign_id

),

final as (

    select
        grid.campaign_id,
        grid.household_id,
        grid.days_in_period,
        grid.is_targeted,
        grid.is_in_other_campaign,
        grid.is_complete,
        -- la jointure ne ramène que les jours de la fenêtre :
        -- avant start_day = période avant, à partir de start_day = pendant
        coalesce(sum(iff(transactions.day_number < grid.start_day, transactions.daily_sales_value, 0)), 0) as spend_before,
        coalesce(sum(iff(transactions.day_number >= grid.start_day, transactions.daily_sales_value, 0)), 0) as spend_during
    from grid
    left join transactions
        on grid.household_id = transactions.household_id
        and transactions.day_number between grid.window_start_day and grid.end_day
    group by all

),

daily as (

    select
        *,
        spend_before / days_in_period as daily_spend_before,
        spend_during / days_in_period as daily_spend_during
    from final

)

select * from daily
