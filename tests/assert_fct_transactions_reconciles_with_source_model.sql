-- réconciliation à la sortie : le modèle incrémental doit donner le même résultat qu'une
-- reconstruction complète. un écart signale une dérive (ligne manquée par le filtre
-- incrémental, ligne comptée deux fois) : relancer avec dbt run --full-refresh
with incremental_table as (

    select count(*) as n_rows, sum(sales_value) as total_sales
    from {{ ref('fct_transactions') }}

),

full_rebuild as (

    select count(*) as n_rows, sum(sales_value) as total_sales
    from {{ ref('int_transactions__priced') }}

)

select
    incremental_table.n_rows as incremental_rows,
    full_rebuild.n_rows as full_rebuild_rows,
    incremental_table.total_sales as incremental_sales,
    full_rebuild.total_sales as full_rebuild_sales
from incremental_table
cross join full_rebuild
where incremental_table.n_rows <> full_rebuild.n_rows
   or abs(incremental_table.total_sales - full_rebuild.total_sales) > 0.01
