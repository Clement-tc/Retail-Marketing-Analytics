{% docs __overview__ %}

# Retail Marketing Analytics

Pipeline dbt + Snowflake sur deux ans de tickets de caisse d'une chaîne de supermarchés
(dunnhumby *The Complete Journey* : 2 500 foyers, 102 semaines). Les données sont rejouées
semaine par semaine par un simulateur qui injecte volontairement des défauts (doublons,
retards, valeurs invalides, changements de catégorie produit), journalisés dans
`simulator_log` pour que les tests prouvent leur traitement.

## Comment lire ce projet

| Couche | Préfixe | Rôle |
|---|---|---|
| Sources | `dunnhumby` | Données brutes de `RAW`, chargées par le simulateur |
| Staging | `stg_` | Une vue par table source : renommage, typage, dédoublonnage, lignes invalides signalées |
| Intermediate | `int_` | Logique partagée : prix, classification produits, RFM, mesure d'effet des campagnes |
| Marts | `fct_`, `dim_` | Tables lues par Power BI |
| Snapshot | `products_snapshot` | Historique SCD2 du catalogue produits |

## Par où commencer

- **`fct_transactions`** : la table de faits des ventes, incrémentale, robuste aux retards et aux doublons.
- **`fct_campaign_performance`** : l'effet de chaque campagne, par différence de différences stratifiée, avec intervalle de confiance.
- **`dim_households`** : les foyers, leur segment RFM et leur profil démographique.

Le graphe de lignage (bouton en bas à droite) montre comment chaque modèle est construit
à partir des sources.

{% enddocs %}
