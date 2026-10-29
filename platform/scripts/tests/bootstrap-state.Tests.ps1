# Offline integration tests using a real native fake aws.exe. It only writes a
# local call log and returns fixture text; it cannot contact AWS or create resources.
$ErrorActionPreference = 'Stop'
$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("events bootstrap test " + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($fixtureDir)
$oldPath = $env:PATH
$fixtureVars = @('EVENTS_FAKE_AWS_LOG','EVENTS_FAKE_AWS_STDERR','EVENTS_FAKE_AWS_STDOUT','EVENTS_FAKE_AWS_EXIT')
$savedVars = @{}
foreach ($name in $fixtureVars) { $savedVars[$name] = [Environment]::GetEnvironmentVariable($name) }
$originalNativePreference = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
function Read-Host { $global:eventsBootstrapTestAnswer }
try {
    $source = @'
using System;
using System.IO;
public class FakeAws {
    public static int Main(string[] args) {
        File.AppendAllText(Environment.GetEnvironmentVariable("EVENTS_FAKE_AWS_LOG"), String.Join("|", args) + "\n");
        if (args.Length > 1 && args[0] == "sts" && args[1] == "get-caller-identity") {
            Console.WriteLine("{\"Account\":\"123456789012\"}"); return 0;
        }
        if (args.Length > 1 && args[0] == "s3api" && args[1] == "head-bucket") {
            string stdout = Environment.GetEnvironmentVariable("EVENTS_FAKE_AWS_STDOUT");
            string stderr = Environment.GetEnvironmentVariable("EVENTS_FAKE_AWS_STDERR");
            Console.Out.Write(stdout == "__LARGE__" ? new String('o', 131072) : stdout);
            Console.Error.Write(stderr == "__LARGE__" ? new String('e', 131072) : stderr);
            return Int32.Parse(Environment.GetEnvironmentVariable("EVENTS_FAKE_AWS_EXIT"));
        }
        // Bootstrap writes are LOGGED ONLY. No AWS libraries or external calls.
        return 0;
    }
}
'@
    $sourceFile = Join-Path $fixtureDir 'FakeAws.cs'
    [IO.File]::WriteAllText($sourceFile, $source)
    $fakeAws = Join-Path $fixtureDir 'aws.exe'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (!(Test-Path -LiteralPath $compiler)) { throw 'Offline fixture needs the Windows .NET Framework C# compiler.' }
    & $compiler /nologo /target:exe "/out:$fakeAws" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'Offline fake AWS compiler failed.' }
    $env:PATH = "$fixtureDir;$oldPath"
    if ((Get-Command aws | Select-Object -First 1).Source -ne $fakeAws -or (Get-Command aws -CommandType Application | Select-Object -First 1).Source -ne $fakeAws) {
        throw 'Offline isolation failed: refusing to run with any real AWS command.'
    }
    # Exercise PS7's stricter native error behavior too, when available.
    if ($PSVersionTable.PSVersion.Major -ge 7) { $PSNativeCommandUseErrorActionPreference = $true }
    $env:EVENTS_FAKE_AWS_LOG = Join-Path $fixtureDir 'calls.txt'
    $global:eventsBootstrapTestAnswer = 'BOOTSTRAP fst-events-tfstate-123456789012-us-east-1'
    $expected404 = 'An error occurred (404) when calling the HeadBucket operation: Not Found'
    $cases = @(
        @{ Name='404 exit 254'; Code=254; Err=$expected404; Out=''; Result='create' },
        @{ Name='prefixed AWS CLI 404'; Code=254; Err=("aws: [ERROR]: " + $expected404); Out=''; Result='create' },
        @{ Name='403 exit 254'; Code=254; Err='An error occurred (403) when calling the HeadBucket operation: Forbidden'; Out=''; Result='fail' },
        @{ Name='expired credentials'; Code=254; Err='An error occurred (ExpiredToken) when calling the HeadBucket operation: The provided token has expired.'; Out=''; Result='fail' },
        @{ Name='connectivity'; Code=255; Err='Could not connect to the endpoint URL: https://s3.us-east-1.amazonaws.com'; Out=''; Result='fail' },
        @{ Name='unexpected API error'; Code=254; Err='An error occurred (500) when calling the HeadBucket operation: Internal Server Error'; Out=''; Result='fail' },
        @{ Name='empty error'; Code=254; Err=''; Out=''; Result='fail' },
        @{ Name='ambiguous Not Found'; Code=254; Err='Proxy configuration Not Found (404)'; Out=''; Result='fail' },
        @{ Name='404 wrong exit'; Code=1; Err=$expected404; Out=''; Result='fail' },
        @{ Name='404 plus other error'; Code=254; Err=($expected404 + "`nExpiredToken"); Out=''; Result='fail' },
        @{ Name='404 with unexpected stdout'; Code=254; Err=$expected404; Out='ambiguous'; Result='fail' },
        @{ Name='success with stderr'; Code=0; Err='unexpected warning'; Out=''; Result='fail' },
        @{ Name='large stdout and stderr'; Code=255; Err='__LARGE__'; Out='__LARGE__'; Result='fail' },
        @{ Name='existing bucket'; Code=0; Err=''; Out='{}'; Result='configure' }
    )
    $bootstrap = Join-Path (Split-Path $PSScriptRoot -Parent) 'bootstrap-state.ps1'
    foreach ($case in $cases) {
        [IO.File]::WriteAllText($env:EVENTS_FAKE_AWS_LOG, '')
        $env:EVENTS_FAKE_AWS_EXIT = [string]$case.Code
        $env:EVENTS_FAKE_AWS_STDERR = $case.Err
        $env:EVENTS_FAKE_AWS_STDOUT = $case.Out
        $failure = $null
        try { & $bootstrap -WarningAction SilentlyContinue | Out-Null }
        catch { $failure = $_ }
        $calls = @(Get-Content -LiteralPath $env:EVENTS_FAKE_AWS_LOG)
        $writes = @($calls | Where-Object { $_ -match '^s3api\|(create-bucket|put-)' })
        if ($case.Result -eq 'fail') {
            if (!$failure -or $failure.Exception.Message -notmatch 'Bucket probe (failed|returned ambiguous)') { throw "Wrong failure for $($case.Name): $failure" }
            if ($writes.Count) { throw "Unexpected writes for $($case.Name)" }
        } else {
            if ($failure) { throw $failure }
            $creates = @($calls | Where-Object { $_ -match '^s3api\|create-bucket\|' })
            $expectedCreates = if ($case.Result -eq 'create') { 1 } else { 0 }
            if ($creates.Count -ne $expectedCreates -or $writes.Count -ne (3 + $expectedCreates)) { throw "Wrong bootstrap path for $($case.Name)" }
            foreach ($operation in @('put-bucket-versioning','put-bucket-encryption','put-public-access-block')) {
                if (!($calls | Where-Object { $_ -like "s3api|$operation|*" })) { throw "Lost $operation configuration" }
            }
        }
        if (!($calls | Where-Object { $_ -eq 's3api|head-bucket|--bucket|fst-events-tfstate-123456789012-us-east-1|--region|us-east-1|--expected-bucket-owner|123456789012|--no-cli-pager' })) { throw 'Native argument forwarding failed.' }
        Write-Host "PASS: $($case.Name)"
    }
    $global:eventsBootstrapTestAnswer = 'CANCEL'
    [IO.File]::WriteAllText($env:EVENTS_FAKE_AWS_LOG, '')
    try { & $bootstrap -WarningAction SilentlyContinue; throw 'Expected cancellation.' }
    catch { if ($_.Exception.Message -notmatch 'Cancelled') { throw } }
    if ((Get-Content -LiteralPath $env:EVENTS_FAKE_AWS_LOG) -match '^s3api\|') { throw 'Cancellation reached S3.' }
    Write-Host "PASS: cancellation; 15 offline cases passed on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    $env:PATH = $oldPath
    foreach ($name in $fixtureVars) { [Environment]::SetEnvironmentVariable($name, $savedVars[$name]) }
    if ($originalNativePreference) { $PSNativeCommandUseErrorActionPreference = $originalNativePreference.Value }
    # Flat, unique fixture directory only; never recursively remove a computed tree.
    Get-ChildItem -LiteralPath $fixtureDir -File | Remove-Item -Force
    Remove-Item -LiteralPath $fixtureDir
}
