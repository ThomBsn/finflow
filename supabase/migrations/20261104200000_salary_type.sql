-- Le salaire créé par la clôture devient un type à part (voir migration
-- suivante) : ce n'est ni une dépense ni un revenu du mois. Valeur d'enum
-- ajoutée seule, elle n'est utilisable qu'après validation de la transaction.
alter type public.transaction_type add value if not exists 'salaire';
