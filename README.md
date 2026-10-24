# Branche `gitops` — état de déploiement

Branche **orpheline** du dépôt `IGL5-G2-EventsProjetcs` : elle ne partage aucun historique avec
`main`/`develop` et ne contient que l'état voulu des environnements Kubernetes.

```
envs/
├── staging/  config.json  values.yaml
├── prod/     config.json  values.yaml
└── <feature>/ ...           (créés par Jenkins au premier build d'une branche feature/*)
```

| Fichier | Rôle | Écrit par |
|---|---|---|
| `config.json` | namespace, profil Helm (`review` / `staging` / `prod`), responsable | Jenkins (étape 12 *Promotion GitOps*) |
| `values.yaml` | image (tag immuable), feature, hôte de l'ingress | Jenkins (étape 12); hôtes staging/prod par `make post-apply` |

## Fonctionnement

- L'ApplicationSet `events-environments` (sur `main`, `platform/gitops/platform/apps/40-events-environments.yaml`)
  lit `envs/*/config.json` sur cette branche : un dossier = une Application Argo CD `events-<dossier>`.
- Le chart Helm vient de `main` (`platform/gitops/charts/events-app`); cette branche fournit
  uniquement `envs/<env>/values.yaml` (source Argo CD `ref: values`).

## Pourquoi une branche séparée

Jenkins pousse ici à chaque déploiement. Si ces commits arrivaient sur `main` ou `develop`,
le webhook GitHub relancerait le pipeline, qui pousserait à nouveau : une boucle.
Cette branche ne contient **aucun Jenkinsfile** et est **exclue** du job Multibranch
(`excludes('gitops')`) : Jenkins ne la construit jamais.

## Supprimer un environnement de feature (après fusion)

```bash
git switch gitops && git pull --rebase origin gitops
git rm -r envs/<nom-feature>
git commit -m "chore(gitops): suppression de l'environnement <nom-feature>"
git push origin gitops
```

Argo CD supprime alors l'Application et ses ressources (finalizer). Ne jamais supprimer `staging` ni `prod`.
