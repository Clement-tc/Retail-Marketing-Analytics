with days as (

    {{ dbt_utils.generate_series(upper_bound= var('calendar_days') ) }}

),

dates as (

    select
        cast(generated_number as integer) as day_number,
        dateadd(day, generated_number - 1, '2020-01-01'::date) as pseudo_date
    from days

),

final as (

    select
        day_number,
        pseudo_date,
        cast(floor((day_number + 1) / 7) + 1 as integer) as week_number,
        year(pseudo_date) as year,
        quarter(pseudo_date) as quarter,
        month(pseudo_date) as month_number,
        monthname(pseudo_date) as month_name,
        date_trunc('month', pseudo_date) as month_start_date,
        day(pseudo_date) as day_of_month

    from dates

)

select * from final