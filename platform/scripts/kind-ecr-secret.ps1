param(
  [string]$Namespace = "events-logistics",
  [string]$Region    = "us-east-1",
  [string]$Registry  = "155368763737.dkr.ecr.us-east-1.amazonaws.com"
)
$ErrorActionPreference = "Stop"

$pw = aws ecr get-login-password --region $Region
if (-not $pw) { throw "Token ECR vide : credentials AWS du lab expires ?" }

kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ecr-secret -n $Namespace `
  --docker-server=$Registry --docker-username=AWS --docker-password=$pw `
  --dry-run=client -o yaml | kubectl apply -f -

'{"imagePullSecrets":[{"name":"ecr-secret"}]}' | Set-Content "$env:TEMP\sa.json" -Encoding ascii
kubectl patch serviceaccount default -n $Namespace --type merge --patch-file "$env:TEMP\sa.json"

kubectl delete pod -n $Namespace -l app=events-app --field-selector=status.phase=Pending
