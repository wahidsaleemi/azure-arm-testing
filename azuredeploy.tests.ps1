[cmdletbinding()]
param(
[string] $ResourceGroupName,
[string]$_artifactsLocation,
[string]$_artifactsLocationSasToken
)
#Tempoarary function to get ARM error
function New-DeploymentResultException([Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceManagerError]$error)
{
    $errorMessage = "$($error.Message) ($($error.Code)) [Target: $($error.Target)]"

    if ($error.Details)
    {
        $innerExceptions =  $error.Details | ForEach-Object { New-DeploymentResultException $_ }
        return New-Object System.AggregateException $errorMessage, $innerExceptions
    }
    else 
    { 
        return New-Object System.Configuration.ConfigurationErrorsException $errorMessage
    }
}

Function Test-AzureJson {
    Param(
      [string]$FilePath,
      [string]$ParameterFilePath
    )
  
    Context "json_structure" {
      
      $templateProperties = (get-content "$FilePath" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)
  
      It "should be less than 1 Mb" {
        Get-Item $FilePath | Select-Object -ExpandProperty Length | Should -BeLessOrEqual 1073741824
      }
  
      It "Converts from JSON" {
        $templateProperties | Should -Not -BeNullOrEmpty
      }
  
      It "should have a `$schema section" {
        $templateProperties."`$schema" | Should -Not -BeNullOrEmpty
      }
  
      It "should have a contentVersion section" {
        $templateProperties.contentVersion | Should -Not -BeNullOrEmpty
      }
  
      It "should have a parameters section" {
        $templateProperties.parameters | Should -Not -BeNullOrEmpty
      }
  
      It "should have less than 256 parameters" {
        $templateProperties.parameters.Length | Should -BeLessOrEqual 256
      }
  
      It "might have a variables section" {
        $result = $null -eq $templateProperties.variables
  
        if($result){
          $result | Should -Be $true
        }
        else {
          #Set-TestInconclusive -Message "Section isn't mandatory, however it's a group practice to have it defined"
          Set-ItResult -Inconclusive -Because "Section isn't mandatory, however it's a group practice to have it defined"
        }
      }
      
      It "must have a resources section" {
        $templateProperties.resources | Should -Not -BeNullOrEmpty
      }
  
      It "might have an outputs section" {
        $result = $null -eq $templateProperties.outputs
  
        if($result){
          $result | Should -Be $true
        }
        else {
          #Set-TestInconclusive -Message "Section isn't mandatory, however it's a group practice to have it defined"
          Set-ItResult -Inconclusive -Because "Section isn't mandatory, however it's a group practice to have it defined"
        }
      }
    }
  
    $jsonMainTemplate = Get-Content "$FilePath"
    $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
  
    $parametersUsage = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "parameters(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
    Context "referenced_parameters" {
      ForEach($parameterUsage In $parametersUsage)
      {
        $parameterUsage = $parameterUsage.SubString($parameterUsage.IndexOf("'") + 1).Replace("')","")
      
        It "should have a parameter called $parameterUsage" {
          $objMainTemplate.parameters.$parameterUsage | Should -Not -Be $null
        }
      }
    }
  
    $variablesUsage = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "variables(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
    Context "referenced_variables" {
      ForEach($variableUsage In $variablesUsage)
      {
        $variableUsage = $variableUsage.SubString($variableUsage.IndexOf("'") + 1).Replace("')","")
        
        It "should have a variable called $variableUsage" {
          $objMainTemplate.variables.$variableUsage | Should -Not -Be $null
        }
      }
    }
  
    Context "missing_opening_or_closing_square_brackets" {
      For($i=0;$i -lt $jsonMainTemplate.Length;$i++) {
        $Matches = [System.Text.RegularExpressions.Regex]::Matches($jsonMainTemplate[$i],"\"".*\""")
  
        ForEach($Match In $Matches) {
          $PairCharNumber = ($Match.Value.Length - $Match.Value.Replace("[","").Replace("]","").Length) % 2
  
          if($PairCharNumber -ne 0) {
            Write-Host $Match.Value
            It "should have same amount of opening and closing square brackets (Line $($i + 1))" {
              $PairCharNumber | Should -Be 0
            }
  
            break
          }
        }
      }
    }
  
    Context "missing_opening_or_closing_parenthesis" {
      For($i=0;$i -lt $jsonMainTemplate.Length;$i++) {
        $Matches = [System.Text.RegularExpressions.Regex]::Matches($jsonMainTemplate[$i],"\"".*\""")
  
        ForEach($Match In $Matches) {
          $PairCharNumber = ($Match.Value.Length - $Match.Value.Replace("(","").Replace(")","").Length) % 2
  
          if($PairCharNumber -ne 0) {
            It "should have same amount of opening and closing parenthesis (Line $($i + 1))" {
              $PairCharNumber | Should -Be 0
            }
  
            break
          }
        }
      }
    }
  
    Context "azure_api_validation" {
      $context = $null
      try {$context = Get-AzContext} catch {}
      if($null -ne $context.Subscription.Id) {
        $Parameters = $objMainTemplate.parameters | Get-Member | Where-Object -Property MemberType -eq -Value "NoteProperty" | Select-Object -ExpandProperty Name
        $TemplateParameters = @{}

        # As a last resort use defaultValue, the first allowedValue, or dummy value (in that order)
        if ($null -eq $ParameterFilePath)
        {
          ForEach($Parameter In $Parameters) {
            if(!($objMainTemplate.parameters.$Parameter.defaultValue)) {
              if($objMainTemplate.parameters.$Parameter.allowedValues) {
                $TemplateParameters.Add($Parameter, $objMainTemplate.parameters.$Parameter.allowedValues[0])
              }
              else {
                switch ($objMainTemplate.parameters.$Parameter.type) {
                  "bool" {
                    $TemplateParameters.Add($Parameter, $true)
                  }
    
                  "int" {
                    if($objMainTemplate.parameters.$Parameter.minValue) {
                      $TemplateParameters.Add($Parameter, $objMainTemplate.parameters.$Parameter.minValue)
                    }
                    else {
                      $TemplateParameters.Add($Parameter, 1)
                    }
                  }
    
                  "string" {
                    if($objMainTemplate.parameters.$Parameter.minValue) {
                      $TemplateParameters.Add($Parameter, "a" * $objMainTemplate.parameters.$Parameter.minLength)
                    }
                    else {
                      $TemplateParameters.Add($Parameter, "dummystring")
                    }
                  }
    
                  "securestring" {
                    $TemplateParameters.Add($Parameter, (ConvertTo-SecureString "dummystring" -AsPlainText -Force))
                  }
    
                  "array" {
                    $TemplateParameters.Add($Parameter, @('Array1', 'Array2', 'Array3'))
                  }
    
                  "object" {
                    $TemplateParameters.Add($Parameter, (@{"DummyProperty"="DummyValue"}))
                  }
    
                  "secureobject" {
                    $TemplateParameters.Add($Parameter, (New-Object -TypeName psobject -Property @{"DummyProperty"="DummyValue"}))
                  }
                }
              }
            }
          }
        }
        # Check if Resource Group exists
        It "Resource Group should exist" {
          Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        # Use $ParameterFilePath if it exists
        if ($ParameterFilePath)
          {
            #quick test, this will have to account for non-linked templates. Perhaps search for _artifactslOcation and add to it if it doesn't exist.
            $TemplateParameters.Add('_artifactsLocation', $_artifactsLocation)
            $TemplateParameters.Add('_artifactsLocationSasToken', (ConvertTo-SecureString $_artifactsLocationSasToken -AsPlainText -Force))
            $output = (Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $armTemplate.FullName -TemplateParameterFile $ParameterFilePath @TemplateParameters)
            # Verbose version below.
            #$output = $(Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $armTemplate.FullName -TemplateParameterFile $ParameterFilePath @TemplateParameters -Verbose) 4>&1
          }
          # otherwise use @TemplateParameters
          else 
            {
              $output = Test-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $armTemplate.FullName @TemplateParameters
            }
          
          #Write-Verbose $output | ForEach-Object {$_}

          It "should be a valid template" {
            $output | Should -BeNullOrEmpty
          }
  
          ForEach($ValidationError In $output) {
            It ("shouldn't have {0}" -f $ValidationError.Code) {
              $ValidationError.Message | Should -BeNullOrEmpty
            }
          }

          If ($output) 
          {
            Write-Verbose "Getting detailed error"
            $output2 = New-DeploymentResultException -error $output[0]
            It "should give a proper error" {
              $output2 | Should -BeNullOrEmpty -Verbose
          }
        }
      }
      else {
        It "should be a valid template" {
          Set-ItResult -Inconclusive -Because "Not logged to Azure for which Test-AzResourceGroupDeployment cannot be executed."
          
        }
      }
    }
    

    $nestedTemplates = $objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments"
    
    if($null -ne $nestedTemplates)
    {
      ForEach($nestedTemplate In $nestedTemplates)
      {
        If($null -ne $nestedTemplate.properties.templateLink.uri)
        {
            #First check if we are referencing a variable (this is common) instead of directly in the resources section
            If (
              #Match "[variables("
              $nestedTemplate.properties.templateLink.uri -match "(?:^\[)variables(?:\()"
            )
            {
              Write-Host "    Testing linked templates..."
              $pattern = "(\w*\.json*)"
              #Get the name of the variable
              $linkedTemplateVariable = ($nestedTemplate.properties.templateLink.uri).Split("'")[1]
              Write-Host "    Found variable reference for linked template:  $linkedtemplateVariable"
              #Get the value of the variable
              $linkedTemplateVariableValue = $objMainTemplate.variables.$linkedTemplateVariable

              #Get the filename
              $nestedTemplateFileName = [System.Text.RegularExpressions.RegEx]::Matches($linkedTemplateVariableValue, $pattern).Value
              Write-Host "    Found filename of linked template: $nestedTemplateFileName"
              #Remove single quotes
              if ($nestedTemplateFileName -match "'")
                {
                  Write-Host "      Removing single quotes from $nestedTemplateFileName"
                  $nestedTemplateFileName = $nestedTemplateFileName.SubString($nestedTemplateFileName.IndexOf("'") + 1).Replace("'","")
                }
              
              #Remove question mark (needs to be escaped)
              if ($nestedTemplateFileName -match "\?")
                {
                  Write-Host "      Removing question mark from $nestedTemplateFileName"
                  $nestedTemplateFileName = $nestedTemplateFileName.Replace('?','')
                }
            }
            #Else use regex to get any 'word' ending in .json
            else 
            {
              #Debug line
              Write-Host "Using templateLink from resources section"
              $nestedTemplateFileName = [System.Text.RegularExpressions.RegEx]::Matches($nestedTemplate.properties.templateLink.uri, "\w*\.json(\?)?").Value
              $nestedTemplateFileName = $nestedTemplateFileName.SubString($nestedTemplateFileName.IndexOf("'") + 1).Replace("'","").Replace('?','')
            }
          }

          Context "Nested Template: $nestedTemplateFileName" {
            It "should exist the nested template at $WorkingFolder\Deployment\nestedtemplates\$nestedTemplateFileName" {
              "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplateFileName" | Should -Exist
            }
  
            if(Test-Path "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplateFileName")
            {
              #Debug line
              Write-Host "  Working on:  $WorkingFolder\Deployment\nestedtemplates\$nestedTemplateFileName"
              $nestedParameters = (Get-Content "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplateFileName" | ConvertFrom-Json).parameters
              $requiredNestedParameters = $nestedParameters | Get-Member -MemberType NoteProperty | Where-Object -FilterScript {$null -eq $nestedParameters.$($_.Name).defaultValue} | ForEach-Object -Process {$_.Name}
  
              
              ForEach($requiredNestedParameter In $requiredNestedParameters)
              {
                
                It "should define the parameter: $requiredNestedParameter" {
                  $nestedTemplate.properties.parameters.$requiredNestedParameter | Should -Not -BeNullOrEmpty
                }
                
                #Passwords will use a Key Vault reference and fail this test since they appear to have no "value"
                if ($requiredNestedParameter -like "*password*")
                  {
                    It "should set a Key Vault reference for $requiredNestedParameter" {
                      $nestedTemplate.properties.parameters.$requiredNestedParameter.reference.keyVault.id | Should -Not -BeNullOrEmpty
                    }
                  }
                else 
                  {
                    It "should set a value for $requiredNestedParameter" {
                      $nestedTemplate.properties.parameters.$requiredNestedParameter.Value | Should -Not -BeNullOrEmpty
                    }
                  }
              }
            }
          }
        }
      }
    }
  
Function Test-PowershellScript {
  Param(
    [string]$FilePath
  )

  It "is a valid Powershell Code"{
    $psFile = Get-Content -Path $FilePath -ErrorAction Stop
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($psFile, [ref]$errors)
    $errors.Count | Should -Be 0
  }
}
  
#region Set file paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkingFolder = Split-Path -Parent $scriptPath

$armTemplates = Get-ChildItem -Path "$WorkingFolder" -Filter "*.json" -recurse -File | Where-Object {$_.Directory.Name -notcontains "nestedtemplates"} | Where-Object -FilterScript {(Get-Content -Path $_.FullName -Raw) -ilike "*schema.management.azure.com/*/deploymentTemplate.json*"}
$armParameters = Get-ChildItem -Path "$WorkingFolder" -Filter "*.json" -recurse -File | Where-Object -FilterScript {(Get-Content -Path $_.FullName -Raw) -ilike "*schema.management.azure.com/*/deploymentParameters.json*"}
$powershellScripts = Get-ChildItem -Path "$WorkingFolder" -Filter "*.ps1" -Exclude "*.tests.*" -Recurse -File
#endregion

#region ARM Template
$ParameterFilePath = $null
If ($armParameters -match "\w*\.(dev)+")
    {
        $ParameterFilePath = $armParameters | Where-Object -Property Name -Match -value "\w*\.(dev)+"
    }
if ($null -eq $ParameterFilePath)
    {
        $ParameterFilePath = $armParameters | Where-Object -Property Name -Match -value "\w*\.(prd)+"
    }
if ($null -eq $ParameterFilePath)
    {
        $ParameterFilePath = $armParameters | Where-Object -Property Name -Match -value "\w*\.(json)+" | Select-Object -First 1
    }

ForEach($armTemplate In $armTemplates)
{
  Describe $armTemplate.FullName.Replace($WorkingFolder,"") {
    Test-AzureJson -FilePath $armTemplate.FullName -ParameterFilePath $ParameterFilePath.FullName
  }
  $jsonMainTemplate = Get-Content $armTemplate.FullName
  $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
  $mainNestedTemplates = $null
  
  #START Work on nested templates
  If($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments")
  {
    $mainNestedTemplates = [System.Text.RegularExpressions.RegEx]::Matches($($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments" | ForEach-Object -Process {$_.properties.templateLink.uri}), "\'\w*\.json\??\'") | Select-Object -ExpandProperty Value -Unique
  }

  ForEach($nestedTemplate In $mainNestedTemplates)
  {
    $nestedTemplate = $nestedTemplate.SubString($nestedTemplate.IndexOf("'") + 1).Replace("'","").Replace('?','')
    
    Describe "Nested: $WorkingFolder\Deployment\nestedtemplates\$nestedTemplate" {
      It "Should exist" {
        "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplate" | Should -Exist
      }

      if(Test-Path "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplate")
      {
        Test-AzureJson -FilePath "$WorkingFolder\Deployment\nestedtemplates\$nestedTemplate"
      }
    }
  }
  #STOP Work on nested templates
}
#endregion

#region ARM Template parameters
$ParameterFileTestCases = @()
ForEach($armParameter In $armParameters)
{
  $ParameterFileTestCases += @{ ParameterFile = $armParameter.FullName }

}
Context "parameter_file_syntax" {
  It "Parameter file contains the expected properties" -TestCases $ParameterFileTestCases {
      Param( $ParameterFile )
      $expectedProperties = '$schema',
                            'contentVersion',
                            'parameters' | Sort-Object
      $templateFileProperties = (Get-content "$ParameterFile" | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | ForEach-Object Name | Sort-Object
      $templateFileProperties | Should Be $expectedProperties
  }
}
#endregion


#region Powershell Scripts
ForEach($powershellScript In $powershellScripts) {
  Describe $powershellScript.FullName.Replace($WorkingFolder,"") {
    Test-PowershellScript -FilePath $powershellScript.FullName
  }
}
#endregion