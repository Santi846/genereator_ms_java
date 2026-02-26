param(
  [Parameter(Mandatory=$true)][string]$Name,            # ms_clientes
  [Parameter(Mandatory=$true)][string]$GroupId,         # com.tuorg
  [Parameter(Mandatory=$false)][string]$ArtifactId = "",# ms-clientes
  [Parameter(Mandatory=$false)][ValidateSet("mysql","mongo")][string]$Bd = "mysql",
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

function Sanitize-Artifact([string]$artifactIdParam, [string]$nameParam){
  if($artifactIdParam -and $artifactIdParam.Trim().Length -gt 0){
    return $artifactIdParam.Trim()
  }
  if($nameParam -and $nameParam.Trim().Length -gt 0){
    return ($nameParam.Trim()).ToLower()
  }
  throw "Name y ArtifactId están vacíos. No se puede generar el microservicio."
}


$Artifact = Sanitize-Artifact $ArtifactId $Name

if([string]::IsNullOrWhiteSpace($Artifact)){
  throw "Artifact quedó vacío. Revisá parámetros -Name/-ArtifactId."
}

$Package = "$GroupId.$(($Name).ToLower())".Replace("_","")

# Dependencias base
$deps = @("web","validation","actuator","lombok")
if($Bd -eq "mysql"){
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

# Paths
$zipPath = Join-Path $env:TEMP "$Artifact.zip"
$resolvedOut = (Resolve-Path -Path $OutputDir).Path
$outPath = Join-Path $resolvedOut $Artifact

Write-Host "==> Generando microservicio: $Artifact (db=$Bd, build=$Build) en $outPath"

# Descargar zip desde Spring Initializr
Invoke-WebRequest -Uri "${baseUri}?$query" -OutFile $zipPath | Out-Null

# Crear carpeta destino del microservicio (OutputDir\Artifact)
Ensure-Dir $outPath

# Extraer en tmp y mover para evitar:
# - que se ensucie OutputDir
# - carpeta duplicada Artifact\Artifact
$tmpDir = Join-Path $env:TEMP ("springinit_" + [Guid]::NewGuid().ToString("N"))
Ensure-Dir $tmpDir

Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
Remove-Item $zipPath -Force

$root = Join-Path $tmpDir $Artifact

if (Test-Path $root) {
  Get-ChildItem -Path $root -Force | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $outPath -Force
  }
} else {
  Get-ChildItem -Path $tmpDir -Force | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $outPath -Force
  }
}

Remove-Item $tmpDir -Recurse -Force

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
if($Bd -eq "mysql"){
  Add-Content -Encoding UTF8 $appYml @"

  datasource:
    url: jdbc:mysql://localhost:3306/${Artifact}?useSSL=false&serverTimezone=UTC
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
      uri: mongodb://localhost:27017/${Artifact}
"@
}

Write-Host "✅ Listo. Abrí la carpeta: $outPath"
Write-Host "DONE!, Next =>: run entity-gen.ps1 file for generate CRUD."