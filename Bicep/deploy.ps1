# set global locaiton for resources deployed in this bicep template
[string] $location = "eastus"
[string] $environment = "prod"
[string] $workspaceName = "dave8364"
[string] $approverEmail = "dcampman@go-planet.com"
[string] $deploymentTime = Get-Date -AsUTC -Format "yyyyMMddThhmmssZ"

# Using a parameters object avoids the issue of parameters supplied twice
[hashtable] $Parameters = @{
	deploymentTime = $deploymentTime
	location       = $location
	environment    = $environment
	workspaceName  = $workspaceName
	approverEmail  = $approverEmail
}

Measure-Command -Expression {
	Write-Output "`nDeploying Environment"
	New-AzDeployment -TemplateFile ../root_modules/main.bicep -Location $location -Name  "tre-$deploymentTime" -TemplateParameterObject $Parameters
}
