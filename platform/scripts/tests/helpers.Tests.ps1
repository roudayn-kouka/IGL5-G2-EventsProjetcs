# Standalone offline tests. All Terraform/AWS/kubectl commands are functions below;
# no external CLI, network, deployment state or infrastructure is used.
$ErrorActionPreference = 'Stop'
$global:eventsHelperTestCalls = [Collections.Generic.List[string]]::new()
$global:eventsHelperTestAnswer = ''
function terraform {
    $global:eventsHelperTestCalls.Add('terraform ' + ($args -join ' '))
    $global:LASTEXITCODE = 0
    if ($args -contains 'workspace') { 'default' }
    if ($args -contains 'output') { '{"region":{"value":"us-east-1"},"eks_cluster_name":{"value":"fst-events"},"vpc_id":{"value":"vpc-0123456789abcdef0"}}' }
}
function aws {
    $global:eventsHelperTestCalls.Add('aws ' + ($args -join ' '))
    $global:LASTEXITCODE = 0
    if ($args -contains 'get-caller-identity') { '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:role/mock"}'; return }
    if ($args -contains 'describe-cluster') { '{"cluster":{"arn":"arn:aws:eks:us-east-1:123456789012:cluster/fst-events","resourcesVpcConfig":{"vpcId":"vpc-0123456789abcdef0"}}}'; return }
}
function kubectl {
    $global:eventsHelperTestCalls.Add('kubectl ' + ($args -join ' '))
    $global:LASTEXITCODE = 0
    if ($args -contains 'patch' -or $args -contains 'delete') { throw 'Unexpected destructive call in offline cancellation test.' }
}
function Read-Host { $global:eventsHelperTestAnswer }
foreach ($name in @('aws','terraform','kubectl')) {
    if ((Get-Command $name).CommandType -ne 'Function') { throw 'Offline mock isolation failed.' }
}
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'academy.ps1') -Action Plan
if (!($global:eventsHelperTestCalls | Where-Object { $_ -like '* plan -input=false -lock-timeout=5m -out=platform.tfplan' })) { throw 'Plan argument forwarding failed.' }
& (Join-Path $root 'academy.ps1') -Action PreviewDestroy
if (!($global:eventsHelperTestCalls | Where-Object { $_ -like '* plan -destroy -input=false -lock-timeout=5m -out=destroy.tfplan' })) { throw 'Preview argument forwarding failed.' }
if ($global:eventsHelperTestCalls | Where-Object { $_ -match 'terraform .* apply' }) { throw 'Preview applied a plan.' }

$global:eventsHelperTestCalls.Clear()
$global:eventsHelperTestAnswer = 'CANCEL'
try { & (Join-Path $root 'academy.ps1') -Action Destroy; throw 'Expected destroy cancellation.' }
catch { if ($_.Exception.Message -notmatch 'Cancelled; no destructive operation') { throw } }
if ($global:eventsHelperTestCalls | Where-Object { $_ -match ' patch | delete |terraform .* apply' }) { throw 'Destroy mutated resources before confirmation.' }

# Bootstrap has dedicated native-process tests: PowerShell function mocks cannot
# reproduce Windows PowerShell's handling of a real executable's stderr.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bootstrap-state.Tests.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Native bootstrap offline tests failed.' }
Write-Host 'PASS: plan/preview forwarding and destroy cancellation; native bootstrap suite passed.'
