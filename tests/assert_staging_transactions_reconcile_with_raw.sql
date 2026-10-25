-- réconciliation à l'entrée : le nettoyage ne doit perdre aucune transaction.
-- chaque couple (ticket, produit) présent dans RAW doit se retrouver une fois en staging,
-- et les lignes sans product_id doivent toutes être conservées (signalées, pas supprimées)
with raw_transactions as (

    select * from {{ source('dunnhumby', 'transaction_data') }}

),

staging as (

    select * from {{ ref('stg_dunnhumby__transactions') }}

),

comparison as (

    select
        (select count(distinct basket_id, product_id) from raw_transactions) as raw_keys,
        (select count(distinct basket_id, product_id) from staging) as staging_keys,
        (select count_if(product_id is null) from raw_transactions) as raw_rows_without_product,
        (select count_if(product_id is null) from staging) as staging_rows_without_product

)

select *
from comparison
where raw_keys <> staging_keys
   or raw_rows_without_product <> staging_rows_without_product
