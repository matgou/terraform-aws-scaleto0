
# Scale to 0 avec AWS et ECS-Fargate

## Introduction :

AWS Fargate est un service Serverless permettant de lancer des containers docker dans le cloud public d’AWS.
Grace a ce service on peut héberger facilement un site web sans se préoccuper des hyperviseurs hébergement ces containers. Pour un exploitant cela signifie qu’il ne faut se soucier de la sécurité, de la tenue en charge et des mises a jours uniquement des containers.

Cependant AWS Fargate est facturé à l’heure d’utilisation, du coup avoir dans son compte AWS des tâches Fargate démarrées plus longtemps qu’elles ne sont utilisées entraînera une sur-facturation inutile.

Dans le cadre d’une démarche fin-ops, nous connaissons differentes possibilités pour alligner l’utilisation de services avec leurs arrets/démarages :

| Possibilités | Avantages | Inconvénients |
| ------------ | --------- | ------------- |
| Arrêt/Démarrage à heure fixe | Adapté pour les application d’entreprise (exemple ouverture de 8h à 18h) | Si le service n’est pas utilisé pendant les horaires d’ouvertures il sera quand même actif et facturé |
| ScaleTo0 (ce projet) | Démarrage du service aligné sur les horaires d’utilisations | Temps de démarrage à la première utilisation |


## Notre architecture de départ :

On va partir de l’hébergement d’un service simple sous ECS (le service d’orchestration de container d’AWS). Par exemple un blog wordpress, pour des raison de simplicité ce service est déployé dans un « subnet public », cela permet notamment de ne pas avoir a déployer d’endpoint sur ce réseau. C’est à dire que les container utiliseront internet pour accèder aux services AWS (Centralisation des logs, registry de containers, …). Mais l'implémentation dans un subnet privé (non connecté à internet) est parfaitement similaire.

Voici la liste des composants pré-requis au module a déployer :

| Composant | Description | 
| --------- | ----------- |
| Un VPC | Il porte les composants réseaux du projet |
| Un ou plusieurs subnets publiques | Rattachés au VPC ils fournissent les adresses Ips aux composants |
| Une gateway-internet | Elle permet les échanges internet-subnets |
| Un Application Load Ballancer | Il distribue les requêtes applicatives (http et https) vers les services |
| Un cluster ECS | Il porte les composants ECS du projet |
| Un service ECS | Il décrit le container et son environnement d’execution |
| Un target-group | Il enregistre les tâches du service ECS actives ou non pour leurs router des requêtes |
| Une règle sur le lb | Elle porte la configuration de redirection des requêtes du loadballancer vers le target-group |

Voici un schéma d’architecture du fonctionnement initial.

![SC0_architecture_d_origine](docs/SC0_architecture_d_origine.drawio.png)

## Problématique :

Avec cette architecture il y’a une capacité s’adapter à la charge (auto-scalling) managé par AWS. C'est à dire qu'en cas de surcharge de nouveaux containers sont lancés pour absorber cette dernière. Cependant il y a une limite « basse », il y aura toujours au moins un container lancé.

En effet nativement AWS ne permet pas de couper tous les containers et de les relancer lorsque le trafic arrivera. C'est ce qui est proposé d'implémenter en utilisant des solutions AWS-natives. 

## Principe du scaling to 0 :

L’idée est de couper tous les containers Fargate et de rediriger les nouvelles requêtes HTTP/HTTPs vers une fonction lambda dont le rôle sera de relancer l’architecture.

![SC0_architecture_scalle_to_0_off](docs/SC0_architecture_scalle_to_0_off.drawio.png)

### Démarrage du service :

Lorsque la lambda est appelé via le loadballancer effectue les actions suivantes : 
* Modification du « desiredCount » du service ECS à 1
* Attente que le « runningCount » du service ECS passe à 1
* Modification de l’ALB pour ne plus utiliser la règle qui redirige vers la lambda mais la règle redirigeant vers le target-group associé au service ECS
* Renvoi d’un ordre 302 de refresh de la page par le client pour qu'il arrive sur le "vrai" site

Une fois le service lancé voici son schéma d’architecture avec le container lancé et la route entre l’ALB et le container relancé.

![SC0_architecture_scalle_to_0_on](docs/SC0_architecture_scalle_to_0_on.drawio.png)

### Arrêt du service :

L’arrêt du service se fait via la surveillance cloudwatch du target-group. Si il n’y a pas d’accès pendant 20minutes (4 points à 0 consécutif) on envoi un ordre de mise en veille à la lambda.
Lorsque la lambda est appelé par sns/cloudwatch, elle effectue les actions suivante :
* Modification du « desiredCount » du service ECS à 0
* Modification de l’ALB pour utiliser la règle qui redirige vers la lambda
   
Ainsi les prochains accès au services déclencherons le lancement du container.

![SC0_architecture_scalle_to_0_onoff](docs/SC0_architecture_scalle_to_0_onoff.drawio.png)

## Utilisation avec terraform :

L’utilisation avec terraform :

```
###########################################################################
# Création de la lambda de start stop
###########################################################################
module "scaleTo0" {
  source    = "["github.com/matgou/terraform-aws-scaleto0"]
  stackname  = "mon_site_wordpress_recette"
  alb_listener_arn = module.alb.alb_listener_arn

  # For lambda
  rule_arn = module.service.rule_arn
  rule_priority = module.service.rule_priority
  ecs_cluster_name = module.service.ecs_cluster_name
  ecs_service_name = module.service.ecs_service_name

  # For monitoring
  alb_arn_suffix = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.service.target_group_arn_suffix
}
```
Description des arguments du module :
| Argument | Description |
| -------- | ----------- |
| stackname | Nom du projet qui sera repris pour la création des objets |
| alb_listener_arn | ARN du listener du loadballancer |
| rule_arn | ARN de la règle pilotant le service dans le loadballancer |
| rule_priority | priorité de la règles (doit être inférieur à 50) |
| ecs_cluster_name | Nom du cluster ECS portant le service |
| ecs_service_name | Nom du service ECS portant l'application |
| alb_arn_suffix | Suffix ARN de l'alb |
| target_group_arn_suffix | Suffix ARN du target-group |
