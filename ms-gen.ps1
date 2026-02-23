param(
  [Parameter(Mandatory=$true)][string]$Name,            # ms_clientes
  [Parameter(Mandatory=$true)][string]$GroupId,         # com.tuorg
  [Parameter(Mandatory=$false)][string]$ArtifactId = "",# ms-clientes
  [Parameter(Mandatory=$false)][ValidateSet("mysql","mongo")][string]$Db = "mysql",
  [Parameter(Mandatory=$false)][ValidateSet("maven","gradle")][string]$Build = "maven",
  [Parameter(Mandatory=$false)][string]$BootVersion = "3.5.0",  # podés cambiar a 4.x cuando quieras
  [Parameter(Mandatory=$false)][string]$JavaVersion = "21",
  [Parameter(Mandatory=$false)][string]$OutputDir = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir($p){
  if(!(Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null }
}

function Sanitize-Artifact([string]$name){
  if($name -and $name.Trim().Length -gt 0){ return $name }
  return ($Name -replace "_","-").ToLower()
}

$Artifact = Sanitize-Artifact $ArtifactId
$Package = "$GroupId.$(($Name -replace "-","_").ToLower())".Replace("_","")

# Dependencias base
$deps = @("web","validation","actuator","lombok")
if($Db -eq "mysql"){
  $deps += @("data-jpa","mysql")
} else {
  $deps += @("data-mongodb")
}

# Parámetros Spring Initializr
$baseUri = "https://start.spring.io/starter.zip"
$params = @{
  type = if($Build -eq "maven"){"maven-project"} else {"gradle-project"}
  language = "java"
  bootVersion = $BootVersion
  baseDir = $Artifact
  groupId = $GroupId
  artifactId = $Artifact
  name = $Artifact
  packageName = $Package
  javaVersion = $JavaVersion
  dependencies = ($deps -join ",")
}

# Construir query string
$query = ($params.GetEnumerator() | ForEach-Object {
  "$([uri]::EscapeDataString($_.Key))=$([uri]::EscapeDataString([string]$_.Value))"
}) -join "&"

$zipPath = Join-Path $env:TEMP "$Artifact.zip"
$outPath = Join-Path (Resolve-Path $OutputDir) $Artifact

Write-Host "==> Generando microservicio: $Artifact (db=$Db, build=$Build) en $outPath"

Invoke-WebRequest -Uri "$baseUri?$query" -OutFile $zipPath | Out-Null

Ensure-Dir $outPath
Expand-Archive -Path $zipPath -DestinationPath $outPath -Force
Remove-Item $zipPath -Force

# Crear estructura base extra
$srcMain = Join-Path $outPath "src\main\java\$($Package.Replace('.','\'))"
$srcRes  = Join-Path $outPath "src\main\resources"
Ensure-Dir (Join-Path $srcMain "common")
Ensure-Dir (Join-Path $srcMain "config")

# application.yml básico (si no existe)
$appYml = Join-Path $srcRes "application.yml"
if(!(Test-Path $appYml)){
  @"
server:
  port: 8080

spring:
  application:
    name: $Artifact
"@ | Set-Content -Encoding UTF8 $appYml
}

# Agregar config DB mínima
if($Db -eq "mysql"){
  Add-Content -Encoding UTF8 $appYml @"

  datasource:
    url: jdbc:mysql://localhost:3306/$Artifact?useSSL=false&serverTimezone=UTC
    username: root
    password: root
  jpa:
    hibernate:
      ddl-auto: update
    open-in-view: false
"@
} else {
  Add-Content -Encoding UTF8 $appYml @"

  data:
    mongodb:
      uri: mongodb://localhost:27017/$Artifact
"@
}

Write-Host "✅ Listo. Abrí la carpeta: $outPath"
Write-Host "Siguiente: ejecutá entity-gen.ps1 para generar un CRUD."