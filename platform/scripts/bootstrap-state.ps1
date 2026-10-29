[CmdletBinding()]
param([string]$Region = 'us-east-1', [string]$Bucket)
$ErrorActionPreference = 'Stop'
$env:AWS_PAGER = ''
function Invoke-AwsJson([string[]]$Arguments) {
    $result = & aws @Arguments --region $Region --output json
    if ($LASTEXITCODE -ne 0) { throw 'AWS command failed; no further changes will be attempted.' }
    if ($result) { $result | ConvertFrom-Json }
}
function Invoke-AwsBucketProbe {
    # Use redirected OS pipes, not PowerShell's native stderr adapter. In Windows
    # PowerShell 5.1, `2>` can produce a terminating NativeCommandError under Stop.
    $awsExecutable = (Get-Command aws -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $arguments = @('s3api', 'head-bucket', '--bucket', $Bucket, '--region', $Region,
        '--expected-bucket-owner', [string]$identity.Account, '--no-cli-pager')
    # ProcessStartInfo.ArgumentList is unavailable on .NET Framework / PS 5.1.
    # Quote every argument using the Windows native argv escaping convention.
    $quotedArguments = foreach ($argument in $arguments) {
        '"' + ([regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $awsExecutable
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (!$process.Start()) { throw 'Unable to start AWS CLI bucket probe.' }
        # Drain both pipes concurrently so either stream can exceed its buffer.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout   = $stdoutTask.GetAwaiter().GetResult()
            Stderr   = $stderrTask.GetAwaiter().GetResult()
        }
    } finally { $process.Dispose() }
}
$identity = Invoke-AwsJson -Arguments @('sts', 'get-caller-identity')
if (!$Bucket) { $Bucket = "fst-events-tfstate-$($identity.Account)-$Region" }
if ($Bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw 'Invalid bucket name.' }
Write-Warning "Bootstrap may CREATE/CONFIGURE bucket $Bucket in account $($identity.Account), region $Region. It never writes state objects or migrates state. No DynamoDB table is needed."
if ((Read-Host "Type BOOTSTRAP $Bucket to continue") -cne "BOOTSTRAP $Bucket") { throw 'Cancelled; nothing changed.' }
$probe = Invoke-AwsBucketProbe
# AWS CLI exit 254 means an API error, NOT specifically a missing bucket. Only
# the complete, expected HeadBucket HTTP 404 diagnostic authorizes creation.
$missingBucket = $probe.ExitCode -eq 254 -and
    [string]::IsNullOrWhiteSpace($probe.Stdout) -and
    $probe.Stderr.Trim() -cmatch '^(?:aws: \[ERROR\]: )?An error occurred \(404\) when calling the HeadBucket operation: (Not Found|NotFound|NoSuchBucket)\.?$'
if ($probe.ExitCode -ne 0 -and !$missingBucket) {
    throw "Bucket probe failed (AWS CLI exit $($probe.ExitCode)); no creation or configuration was attempted. Check permissions, session credentials and connectivity."
}
if ($probe.ExitCode -eq 0 -and ![string]::IsNullOrWhiteSpace($probe.Stderr)) {
    throw 'Bucket probe returned ambiguous stderr despite success; no creation or configuration was attempted.'
}
if ($missingBucket) {
    $create = @('s3api', 'create-bucket', '--bucket', $Bucket)
    if ($Region -ne 'us-east-1') { $create += @('--create-bucket-configuration', "LocationConstraint=$Region") }
    Invoke-AwsJson -Arguments $create | Out-Null
}
Invoke-AwsJson -Arguments @('s3api', 'put-bucket-versioning', '--bucket', $Bucket, '--expected-bucket-owner', $identity.Account, '--versioning-configuration', 'Status=Enabled') | Out-Null
# file:// avoids native Windows command-line JSON quoting issues.
$tempConfig = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($tempConfig, '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}')
    Invoke-AwsJson -Arguments @('s3api', 'put-bucket-encryption', '--bucket', $Bucket, '--expected-bucket-owner', $identity.Account, '--server-side-encryption-configuration', "file://$tempConfig") | Out-Null
} finally { Remove-Item -LiteralPath $tempConfig -Force }
Invoke-AwsJson -Arguments @('s3api', 'put-public-access-block', '--bucket', $Bucket, '--expected-bucket-owner', $identity.Account, '--public-access-block-configuration', 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true') | Out-Null
Write-Host "Backend ready: $Bucket. Configure backend.hcl manually; existing state was not touched."
