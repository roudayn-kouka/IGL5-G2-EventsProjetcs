[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Init','PlanInfrastructure','ApplyInfrastructure','Plan','Apply','Outputs','PreviewDestroy','Destroy','Verify')][string]$Action
)
$ErrorActionPreference = 'Stop'
$env:AWS_PAGER = ''
$tfDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../terraform'))
function Invoke-Terraform([string[]]$Arguments) {
    & terraform "-chdir=$tfDir" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Terraform failed during $($Arguments[0]). Stop and inspect; do not discard state." }
}
function Get-Outputs {
    $raw = & terraform "-chdir=$tfDir" output -json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read configured backend outputs.' }
    $raw | ConvertFrom-Json
}
function Invoke-Aws([string[]]$Arguments) {
    $raw = & aws @Arguments --region $script:region --output json
    if ($LASTEXITCODE -ne 0) { throw 'AWS read failed; cleanup stopped without deleting AWS resources directly.' }
    if ($raw) { $raw | ConvertFrom-Json }
}
function Invoke-Kube([string[]]$Arguments) {
    & kubectl --context $script:clusterArn @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Kubernetes operation failed. State and backend are preserved; investigate before retrying.' }
}
function Get-ProjectLoadBalancers {
    # Only the state-owned VPC and cluster ownership tags qualify. Include legacy ELBs.
    $v2 = Invoke-Aws -Arguments @('elbv2','describe-load-balancers')
    foreach ($lb in @($v2.LoadBalancers | Where-Object VpcId -eq $script:vpcId)) {
        $tags = (Invoke-Aws -Arguments @('elbv2','describe-tags','--resource-arns',$lb.LoadBalancerArn)).TagDescriptions[0].Tags
        if ($tags | Where-Object { ($_.Key -eq "kubernetes.io/cluster/$script:clusterName" -and $_.Value -in @('owned','shared')) -or ($_.Key -eq 'elbv2.k8s.aws/cluster' -and $_.Value -eq $script:clusterName) }) { $lb.LoadBalancerArn }
    }
    $v1 = Invoke-Aws -Arguments @('elb','describe-load-balancers')
    foreach ($lb in @($v1.LoadBalancerDescriptions | Where-Object VPCId -eq $script:vpcId)) {
        $tags = (Invoke-Aws -Arguments @('elb','describe-tags','--load-balancer-names',$lb.LoadBalancerName)).TagDescriptions[0].Tags
        if ($tags | Where-Object { $_.Key -eq "kubernetes.io/cluster/$script:clusterName" -and $_.Value -in @('owned','shared') }) { $lb.LoadBalancerName }
    }
}
$workspace = & terraform "-chdir=$tfDir" workspace show
if ($LASTEXITCODE -ne 0 -and $Action -ne 'Init') { throw 'Initialize the approved backend first.' }
if ($workspace -and ($workspace -join '').Trim() -ne 'default') { throw 'Shared infrastructure must use the default workspace, never a feature workspace.' }
switch ($Action) {
    'Init' {
        if (!(Test-Path (Join-Path $tfDir 'backend.hcl'))) { throw 'Prepare the approved backend.hcl first. This helper never bootstraps or migrates state.' }
        Invoke-Terraform -Arguments @('init','-input=false','-lockfile=readonly','-backend-config=backend.hcl')
    }
    'PlanInfrastructure' {
        # First bootstrap only: establish EKS before configuring Kubernetes providers.
        Invoke-Terraform -Arguments @('validate')
        Invoke-Terraform -Arguments @('plan','-input=false','-lock-timeout=5m','-target=module.eks','-target=aws_ecr_repository.events_app','-target=aws_ecr_lifecycle_policy.events_app','-out=infrastructure.tfplan')
    }
    'ApplyInfrastructure' {
        Write-Warning 'Creates billable infrastructure from the reviewed bootstrap plan. Full Plan/Apply MUST follow.'
        if ((Read-Host 'Type APPLY INFRASTRUCTURE') -cne 'APPLY INFRASTRUCTURE') { throw 'Cancelled.' }
        Invoke-Terraform -Arguments @('apply','-lock-timeout=5m','infrastructure.tfplan')
    }
    'Plan' { Invoke-Terraform -Arguments @('validate'); Invoke-Terraform -Arguments @('plan','-input=false','-lock-timeout=5m','-out=platform.tfplan') }
    'Apply' {
        if ((Read-Host 'Type APPLY PLATFORM to apply the reviewed plan') -cne 'APPLY PLATFORM') { throw 'Cancelled.' }
        Invoke-Terraform -Arguments @('apply','-lock-timeout=5m','platform.tfplan')
    }
    'Outputs' {
        $outputs = Get-Outputs
        # Only these non-secret outputs are displayed.
        foreach ($key in @('region','eks_cluster_name','vpc_id','ecr_registry','ecr_repository_url')) { Write-Host "$key=$($outputs.$key.value)" }
    }
    'PreviewDestroy' {
        Write-Warning 'PREVIEW ONLY. Plan file can contain secrets; never commit/archive it.'
        Invoke-Terraform -Arguments @('plan','-destroy','-input=false','-lock-timeout=5m','-out=destroy.tfplan')
    }
    'Destroy' {
        $outputs = Get-Outputs
        $script:region = $outputs.region.value
        $script:clusterName = $outputs.eks_cluster_name.value
        $script:vpcId = $outputs.vpc_id.value
        if (!$region -or !$clusterName -or !$vpcId) { throw 'Required ownership outputs absent. For partial bootstrap recovery, review a direct terraform plan -destroy with an operator; no Kubernetes cleanup attempted.' }
        $identity = Invoke-Aws -Arguments @('sts','get-caller-identity')
        $cluster = (Invoke-Aws -Arguments @('eks','describe-cluster','--name',$clusterName)).cluster
        $script:clusterArn = $cluster.arn
        if ($cluster.resourcesVpcConfig.vpcId -ne $vpcId -or $clusterArn -notlike "arn:aws:eks:${region}:$($identity.Account):cluster/$clusterName") { throw 'Cluster/account/VPC ownership mismatch.' }
        # Require a working, explicitly selected context BEFORE preview/confirmation.
        Invoke-Kube -Arguments @('get','namespace','argocd')
        Invoke-Terraform -Arguments @('plan','-destroy','-input=false','-lock-timeout=5m','-out=destroy.tfplan')
        Write-Warning "DESTRUCTIVE: account $($identity.Account), $region, $clusterName, $vpcId. ECR images, MySQL PVCs and optional EC2 tool data may be permanently lost. Backend bucket, lock configuration and state are retained."
        if ((Read-Host "Type DESTROY $clusterName $($identity.Account) BEFORE any deletion") -cne "DESTROY $clusterName $($identity.Account)") { throw 'Cancelled; no destructive operation started.' }
        # Parent first, then child: prevent Argo recreating ingress during cleanup.
        foreach ($app in @('platform','ingress-nginx')) {
            $patchFile = [IO.Path]::GetTempFileName()
            try {
                [IO.File]::WriteAllText($patchFile, '{"spec":{"syncPolicy":{"automated":null}}}')
                Invoke-Kube -Arguments @('-n','argocd','patch','application',$app,'--type=merge','--patch-file',$patchFile)
            } finally { Remove-Item -LiteralPath $patchFile -Force }
        }
        Invoke-Kube -Arguments @('-n','argocd','delete','applicationset','events-environments','--cascade=foreground','--wait=true','--timeout=10m','--ignore-not-found')
        Invoke-Kube -Arguments @('-n','ingress-nginx','delete','service','ingress-nginx-controller','--wait=true','--timeout=5m','--ignore-not-found')
        # The Service is part of the Terraform Helm release; deleting it also cleans up a legacy internal NLB.
        Invoke-Kube -Arguments @('-n','argocd','delete','service','argocd-server','--wait=true','--timeout=5m','--ignore-not-found')
        $deadline = (Get-Date).AddMinutes(15)
        do {
            $remaining = @(Get-ProjectLoadBalancers)
            if (!$remaining.Count) { break }
            if ((Get-Date) -gt $deadline) { throw 'Project load balancers remain; Terraform deletion stopped. Inspect controller events and AWS permissions.' }
            Write-Host "Waiting for $($remaining.Count) project load balancer(s)..."
            Start-Sleep -Seconds 10
        } while ($true)
        # Refresh/replan after Kubernetes cleanup; never apply the now-stale preview.
        Invoke-Terraform -Arguments @('plan','-destroy','-input=false','-lock-timeout=5m','-out=destroy.tfplan')
        if ((Read-Host 'Review final plan. Type APPLY DESTROY') -cne 'APPLY DESTROY') { throw 'Terraform destruction cancelled; Kubernetes cleanup has already occurred.' }
        Invoke-Terraform -Arguments @('apply','-lock-timeout=5m','destroy.tfplan')
        Write-Host "Verify removal in account $($identity.Account), region $region, VPC $vpcId. Keep backend/state and configuration for reuse."
    }
    'Verify' {
        $script:region = if ($env:AWS_REGION) { $env:AWS_REGION } else { 'us-east-1' }
        Write-Host 'Read-only inventory; inspect project tags and the recorded VPC. Do not delete unrelated resources.'
        Invoke-Aws -Arguments @('eks','list-clusters') | ConvertTo-Json -Depth 5
        foreach ($resource in @('instances','nat-gateways','addresses','volumes','network-interfaces','vpcs')) {
            Write-Host "EC2 $resource (project tag filter):"
            Invoke-Aws -Arguments @('ec2',"describe-$resource",'--filters','Name=tag:project,Values=fst-events') | ConvertTo-Json -Depth 8
        }
        Write-Host 'Load balancers: check the recorded VPC, including Kubernetes-created resources.'
        Invoke-Aws -Arguments @('elbv2','describe-load-balancers') | ConvertTo-Json -Depth 5
        Invoke-Aws -Arguments @('elb','describe-load-balancers') | ConvertTo-Json -Depth 5
    }
}
