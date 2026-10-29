# Récupération automatique de la suppression

Validation AWS le 29 octobre 2026, de 16:41:58 à 16:43:55 UTC, dans le compte
`573199225243`, région `eu-west-3`, avec `vitalora-deployer` et le fournisseur
Terraform AWS 5.100.0. Aucune permission de ce profil n’a été élargie.

Le banc isolé a créé six ressources : fonction Lambda, déclencheur SQS, file,
rôle d’exécution, politique du rôle et groupe de journaux. Il utilisait les mêmes
adresses Terraform du module de messagerie et un préfixe temporaire propre.
L’état de la boutique est resté vide ; son stockage distant n’a pas été modifié.

Le fournisseur a réellement renvoyé le défaut `GetEventSourceMapping` 403 après
suppression du déclencheur. Le script a obtenu deux listes AWS complètes sans
l’UUID attendu, revérifié l’état, retiré uniquement cette entrée résiduelle avec
verrouillage, puis terminé la suppression des cinq ressources restantes.
Une seconde suppression a terminé avec zéro ressource à supprimer.

Les vérifications AWS ont confirmé l’absence de la fonction, de la file, du rôle
et du groupe de journaux. Le dossier privé du banc a ensuite été retiré.
Le [résultat nettoyé](cleanup-live.json) contient les identifiants de corrélation
et les comptes de ressources, sans état brut, code déployé ni identifiants AWS.
Les [contrôles locaux](verification-locale.json) et les
[empreintes des sources](source-hashes.json) identifient le code vérifié.

La première exécution avait déjà réussi la récupération et la suppression, mais
son contrôle final échouait lorsque la CLI SQS omettait une liste vide. Le contrôle
utilise maintenant une projection JSON explicite. La seconde exécution complète
décrite ci-dessus a passé ce contrôle.

Une vérification de suppression vide sur l’état officiel a été refusée par
l’approbation automatique, faute de preuve suffisante préalable sur son contenu.
Elle n’a pas été exécutée. Cet état a été contrôlé en lecture seule : zéro
ressource applicative. L’entrée publique du script est couverte par un test
local, et le moteur de récupération par le banc AWS isolé.

Cette preuve couvre la récupération de suppression. Elle ne constitue ni un
nouveau test de la boutique française sur AWS, ni une validation multi-compte,
ni une mesure définitive de facturation.
