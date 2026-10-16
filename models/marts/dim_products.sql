-- la classification des produits est calculée dans int_products__classified,
-- partagée avec le calcul RFM
select * from {{ ref('int_products__classified') }}
