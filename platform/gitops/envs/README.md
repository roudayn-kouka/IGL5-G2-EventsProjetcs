# Environnements

Un dossier = un environnement = une Application Argo CD `events-<dossier>` (créée par l'ApplicationSet).

| Fichier | Rôle | Écrit par |
|---|---|---|
| `config.json` | namespace, profil Helm (review / staging / prod), responsable | Jenkins (étape *Promotion GitOps*) |
| `values.yaml` | image (tag immuable), feature, URL | Jenkins (étape *Promotion GitOps*) |

Les environnements de feature (`event-statistics`, `participant`, `logistics`, `event`, `feedback`)
apparaissent au premier build de la branche. Pour supprimer un environnement après la fusion :
supprimer son dossier et pousser — Argo CD détruit les ressources.
