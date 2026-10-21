-- la grille doit contenir exactement chaque campagne x chaque foyer :
-- une ligne en moins = un foyer perdu, une ligne en plus = une jointure qui duplique
with expected as (

    select
        (select count(*) from {{ ref('stg_dunnhumby__campaigns') }})
        * (select count(*) from {{ ref('int_households__unioned') }}) as expected_rows

),

actual as (

    select count(*) as actual_rows
    from {{ ref('int_campaign_households__aggregated') }}

)

select expected.expected_rows, actual.actual_rows
from expected
cross join actual
where expected.expected_rows <> actual.actual_rows
