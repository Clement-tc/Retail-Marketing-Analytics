-- setup snowflake du projet : idempotent (if not exists), à exécuter en accountadmin
-- remplacer <user> par le nom d'utilisateur (entre guillemets si créé en minuscules)
-- et <public_key> par le contenu de rsa_key.pub sans les lignes begin/end

use role accountadmin;

-- warehouses : un par charge de travail, xs, suspension après 60 s
create warehouse if not exists loading_wh      warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true;
create warehouse if not exists transforming_wh warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true;
create warehouse if not exists reporting_wh    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true;

-- bases : raw (reçu) / analytics (produit par dbt)
create database if not exists raw;
create database if not exists analytics;

-- rôles fonctionnels, rattachés à sysadmin
create role if not exists loader;
create role if not exists transformer;
create role if not exists reporter;
grant role loader to role sysadmin;
grant role transformer to role sysadmin;
grant role reporter to role sysadmin;

-- loader : écrit dans raw
grant usage on warehouse loading_wh to role loader;
grant all on database raw to role loader;

-- transformer : lit raw (y compris les tables futures), possède analytics
grant usage on warehouse transforming_wh to role transformer;
grant usage on database raw to role transformer;
grant usage on all schemas in database raw to role transformer;
grant usage on future schemas in database raw to role transformer;
grant select on all tables in database raw to role transformer;
grant select on future tables in database raw to role transformer;
grant all on database analytics to role transformer;

-- reporter : lecture des marts, accordée par dbt (config grants)
grant usage on warehouse reporting_wh to role reporter;
grant usage on database analytics to role reporter;

-- utilisateur développeur : authentification par paire de clés
grant role loader to user <user>;
grant role transformer to user <user>;
grant role reporter to user <user>;
alter user <user> set
  rsa_public_key = '<public_key>'
  default_role = transformer
  default_warehouse = transforming_wh
  -- sinon tous les rôles accordés (dont accountadmin) restent actifs en secondaire
  default_secondary_roles = ();
