# Scale to 0 avec AWS et ECS-Fargate

## Introduction :

AWS Fargate est un service Serverless permettant de lancer des containers docker dans le cloud public d’AWS.
Grace a ce service on peut hébergé facilement un site web sans se préoccuper des hyperviseurs hébergement ces containers. Pour un exploitant cela signifie qu’il ne faut se soucier de la sécurité, de la tenue en charge et des mises a jours uniquement des containers.

Cependant AWS Fargate est facturé à l’heure d’utilisation, du coup avoir dans son compte AWS des tâches Fargate démarré plus longtemps qu’elles sont utilisés entraînera une facturation inutile.
Dans le cadre d’une démarche fin-ops nous connaissons differentes possibilités pour alligner l’utilisation de service avec leurs arrets/démarage :

| Possibilités | Avantages | Inconvénients |
| ------------ | --------- | ------------- |
| Arrêt/Démarrage a heure fixe | Adapté pour les application d’entreprise (exemple ouverture de 8h à 18h) | Si le service n’est pas utilisé pendant les horaires d’ouverture il sera quand même actifs |
| ScaleTo0 | Démarrage du service aligné sur les horaires d’utilisations | Temps de démarrage a la première utilisation |


## Notre architecture de départ :

On va partir de l’hébergement d’un service simple sous ECS (le service d’orchestration de container d’AWS). Pour des raison de facilité ce service est déployé dans un « subnet public », cela permet notamment de ne pas avoir a déployer d’endpoint sur ce réseau. C’est à dire que les container utiliseront internet pour accèder aux services AWS (Centralisation des logs, registry de containers, …).
Les composants déployés dans cette architectures sont donc les suivants :

| Composant | Description | 
| --------- | ----------- |
| Un VPC | Pour porter les composants réseau du projet |
| Un ou plusieurs subnets publiques | Rattaché au VPC ils fournissent les adresses Ips aux composants |
| Une gateway-internet |Pour permettre les échanges internet-subnets |
| Un Application Load Ballancer | Pour distribuer les recettes applicatives (http et https) vers les services |
| Un cluster ECS | Pour le supports de nos services ECS |
| Un service ECS | Le service portant le container et son environnement d’execution |

Voici un schéma d’architecture du fonctionnement initiale.

## Problématique :

Avec cette architecture il y’a une capacité s’adapter a la charge (auto-scalling). En cas de surcharge de nouveaux containers sont lancé pour absorbé celle ci. Cependant il y a une limite « basse », il y aura toujours au moins un container lancé.

## Principe du scaling to 0 :

L’idée est de couper tous les containers Fargate et de rediriger les nouvelles requêtes HTTP/HTTPs vers une fonction lambda dont le rôle sera de relancer l’architecture.

### Démarrage du service :

Lorsque la lambda est appelé via le loadballancer effectue les actions suivante : 
    • Modification du « desiredCount » du service ECS à 1
    • Attente que le « runningCount » du service ECS passe à 1
    • Modification de l’ALB pour ne plus utiliser la règle qui redirige vers la lambda mais la règle redirigeant vers le target-group associé au service ECS
    • Renvoi d’un ordre 302 de refresh de la page

Une fois le service lancé voici son schéma d’architecture avec le container lancé et la route entre l’ALB et le container relancé.

### Arrêt du service :

L’arrêt du service se fait via la surveillance cloudwatch du target-group. Si il n’y a pas d’accès pendant 20minutes on envoi un ordre de mise en veille à la lambda.
Lorsque la lambda est appelé par sns/cloudwatch, elle effectue les actions suivante :
    • Modification du « desiredCount » du service ECS à 0
    • Modification de l’ALB pour utiliser la règle qui redirige vers la lambda
Ainsi les prochains accès au services déclencherons le lancement du container.

## Utilisation avec terraform :

L’utilisation avec terraform :

```
###########################################################################
# Création de la lambda de start stop
###########################################################################
module "scaleTo0" {
  source    = "./modules/kapable-alb-greenlambda"
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
