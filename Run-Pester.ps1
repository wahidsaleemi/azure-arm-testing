Param(
  [Parameter(Mandatory)]
  [string]$TestFilePattern,
  [string]$PesterVersion = "latest"
)

$deploymentPath = "$env:BUILD_SOURCESDIRECTORY\$env:DEPLOYMENTROOT"

Set-Location $deploymentPath
Write-Host "Using $(Get-Location) as root folder."
Write-Host "Received parameter: $ENV:_artifactsLocation"

#region Get test files
Write-Host "Looking for Test Files " -NoNewline
If($TestFilePattern.Contains('*')){
  Write-Host "with asterisk ($TestFilePattern)..."
  $TestFiles = Get-ChildItem -Path "$deploymentPath" -Recurse -Filter $TestFilePattern -File
}
else {
  Write-Host "without asterisk..."
  $TestFiles = Get-ChildItem -Path "$deploymentPath" -Filter $TestFilePattern -File
}

"Test Files found: {0}" -f $TestFiles.Count

If($TestFiles.Count -eq 0){
  Throw ("No Test Files found")
}
#endregion

$TestOutput = $deploymentPath
"TestOutput is now = $TestOutput"

#region check and install Pester
if($PesterVersion -eq "latest") {
  "Find Pester latest version"
  $Pester = Find-Module -Name Pester
  "Latest version is '{0}'" -f $Pester.Version
}
$Module = Get-Module -Name "Pester" -ListAvailable | Select-Object -First 1
"Pester version found is = '{0}'" -f $Module.Version

If($Module.Version -ne $PesterVersion) {
  "Installing Pester..."
  Install-Module -Name "Pester" -Scope CurrentUser -AllowClobber -Force -SkipPublisherCheck
}
#endregion

"FilePath is now = $TestFilePattern"
"PesterVersion is now = $PesterVersion"

#region Run Pester
$Return = 0

ForEach($TestFile In $TestFiles){
  "Preparing to execute: {0}" -f $TestFile.FullName
  $OutputFile = "TEST-{0}.xml" -f $TestFile.Name.SubString(0,$TestFile.Name.LastIndexOf('.'))
  "OutputFile is now = $OutputFile"

  Write-Host "Running Pester " -NoNewline
  if ($null -ne $ENV:_ARTIFACTSLOCATION)
  {
    "on nested templates..."
    $Return = $Return + (Invoke-Pester -Script @{Path = $TestFile.FullName; Parameters = @{ResourceGroupName = $env:ResourceGroupName; _artifactsLocation = $ENV:_ARTIFACTSLOCATION; _artifactsLocationSasToken = $ENV:_ARTIFACTSLOCATIONSASTOKEN; Verbose = $True}} -EnableExit -OutputFile "$TestOutput\$OutputFile" -OutputFormat NUnitXml)
  }
  else 
  {
    "on templates..."
    $Return = $Return + (Invoke-Pester -Script @{Path = $TestFile.FullName; Parameters = @{ResourceGroupName = $env:ResourceGroupName; Verbose = $True}} -EnableExit -OutputFile "$TestOutput\$OutputFile" -OutputFormat NUnitXml)
  }
}
#endregion

"Pester exited with code = $Return"
$Host.SetShouldExit($Return)
Exit