-- chaque produit doit avoir exactement une version en cours dans le snapshot :
-- zéro = produit perdu, deux = une ancienne version n'a pas été fermée
select product_id, count(*) as current_versions
from {{ ref('products_snapshot') }}
where dbt_valid_to is null
group by product_id
having count(*) <> 1
