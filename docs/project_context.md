# Contexte du projet : Retail Marketing Analytics (dbt + Snowflake)

Document de contexte à donner à un assistant (ou à un relecteur) pour reprendre le projet
sans historique. État au 23 octobre 2026.

## Objectif

Projet portfolio pour une candidature Analytics Engineer en cabinet de conseil data/marketing
(JAKALA). Je dois pouvoir expliquer chaque choix en entretien : l'assistant doit expliquer le
pourquoi, me faire écrire le code plutôt que le livrer, et signaler les questions d'entretien.

## Données

dunnhumby « The Complete Journey » (Kaggle) : 2 ans de transactions de 2 500 foyers d'une
chaîne de supermarchés. Jours stockés en entiers (1 à 711), dates anonymisées.

Questions métier :
1. Quelles campagnes génèrent réellement des ventes supplémentaires ?
2. Quels segments clients (RFM) ont le plus de valeur, lesquels décrochent ?
3. Évolution du panier moyen et de la fréquence d'achat par profil de foyer.

## Stack

- Snowflake (compte d'essai, expire vers le 6 novembre 2026), bases `RAW` et `ANALYTICS`
- Rôles `LOADER` (simulateur), `TRANSFORMER` (dbt), `REPORTER` (Power BI), rôles secondaires désactivés
- dbt Core 1.12.5 + dbt-snowflake 1.12.1, packages dbt_utils, dbt_expectations, codegen
- Authentification par paire de clés ; secrets dans `.env` (non versionné)
- Windows : Smart App Control bloque `dbt.exe`, dbt est lancé via `python.exe` (fonction dans `load_env.ps1`)
- Dev : schémas `analytics.dbt_ctchen_<couche>` ; prod : `analytics.<couche>` (macro `generate_schema_name`)

## Simulateur (`simulator/simulate.py`)

- `load-history` : tables de référence + transactions des semaines 1 à 90 dans `RAW.DUNNHUMBY`
- `deliver-week --week N` : livre une semaine avec défauts volontaires (doublons ~1 %, retards
  ~2 % livrés 3 semaines plus tard, product_id null et quantités négatives ~0,1 %, changements
  de catégorie produit), reproductible par seed, défauts tracés dans `SIMULATOR_LOG`
- Colonnes techniques `_loaded_at`, `_batch_id` sur chaque ligne
- Livré à ce jour : historique + semaine 91

## Avancement

| Étape | État |
|---|---|
| 1. Setup Snowflake + dbt | fait |
| 2. Simulateur + chargement RAW | fait |
| 3. Staging + tests | fait |
| 4. Intermediate + marts | en cours : dernier modèle `fct_campaign_performance` |
| 5. Incrémental (fct_transactions) + snapshot SCD2 produits | à faire |
| 6. Environnements + CI GitHub Actions | à faire |
| 7. dbt docs + dashboard Power BI | à faire |
| 8. README orienté métier | à faire |

## Modèles

Staging (vues, un par table source) : `stg_dunnhumby__` campaigns, campaign_households, coupons
(dédoublonné : 5 164 doublons dans la source), coupon_redemptions, households, products,
transactions (dédoublonné sur basket_id + product_id, lignes invalides signalées par
`rejection_reason`).

Intermediate (vues) :
- `int_transactions__priced` : lignes valides + mesures de prix (gross_amount, customer_paid_amount...)
- `int_products__classified` : flags `is_fuel`, `is_non_merchandise`
- `int_households__unioned` : liste complète des foyers (union des sources)
- `int_household_rfm` : RFM sur la marchandise, scores par cume_dist, 5 segments (grille récence x valeur)
- `int_campaign_households__aggregated` : une ligne par campagne x foyer (74 970), dépense avant/pendant

Marts (tables) : `dim_date`, `dim_products`, `dim_households`, `fct_transactions`,
`fct_campaign_performance` (en cours). Seed : `income_brackets` (ordre de tri des tranches).

## Décisions clés (à pouvoir défendre)

- Remises passées en positif avec `-1 *` (et non `abs()`) pour que les anomalies restent visibles
- `sales_value` = montant reçu par le magasin, après ses remises, coupon fabricant inclus
  (vérifié sur les données : 67 % de concordance contre 1 %). `customer_paid_amount` = `sales_value - manufacturer_coupon_discount`
- Carburant (sous-catégorie GASOLINE-REG UNLEADED, 35 produits, 8 % du CA, quantités en millièmes
  de gallon) exclu des métriques de panier, fréquence et RFM
- Profils démographiques : 801 foyers sur 2 500, les plus actifs : biais à signaler
- Placeholders (`Unknown`, `NO COMMODITY DESCRIPTION`, espaces) convertis en null en staging
- Calendrier fictif (`pseudo_date`, jour 1 = 2020-01-01) : pas de jour de semaine ni de saisonnalité
- RFM : cume_dist plutôt que ntile (égalités nombreuses) ; segments champions, loyal, occasional, at_risk, hibernating
- Campagnes : différence de différences. Période « avant » de même durée juste avant la campagne ;
  groupe témoin = foyers non ciblés et non ciblés par une autre campagne chevauchant la fenêtre ;
  `is_complete` pour les campagnes dont les données ne sont pas encore livrées ; 77 % des couples
  ciblés chevauchent une autre campagne (limite principale)

## Conventions

stg_ / int_<entité>__<verbe> / fct_ / dim_ ; snake_case ; SQL en minuscules ; CTE d'import puis
`final` puis `select * from final` ; un YAML par modèle dans les marts ; préfixe `is_` pour les booléens.

## En cours : `fct_campaign_performance`

Une ligne par campagne. Fait : description, composition (foyers ciblés, % de la base, foyers
témoins, coupons distribués, taux de rédemption). À faire : moyennes de dépense journalière par
groupe (ciblés / témoins x avant / pendant), uplift par différence de différences, ventes
incrémentales, uplift « ciblés seuls » comme contrôle de robustesse, flag petit échantillon, YAML.

## En suspens avant le premier push GitHub

Nom et email des commits, lignes `Co-Authored-By: Claude` sur 3 commits, deux messages de commit à nettoyer.
