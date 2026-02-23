param(
  [Parameter(Mandatory=$true)][string]$ProjectDir,                 # C:\dev\ms-clientes
  [Parameter(Mandatory=$true)][string]$BasePackage,                # com.tuorg.msclientes
  [Parameter(Mandatory=$true)][string]$Entity,                     # Cliente
  [Parameter(Mandatory=$true)][ValidateSet("mysql","mongo")][string]$Db,
  [Parameter(Mandatory=$false)][string]$IdType = "Long",           # Long | UUID | String
  [Parameter(Mandatory=$false)][string]$Fields = "nombre:String"   # "nombre:String,email:String,edad:Integer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir($p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

function Upper1([string]$s){
  if(!$s -or $s.Length -eq 0){ return $s }
  return $s.Substring(0,1).ToUpper() + $s.Substring(1)
}

function Lower1([string]$s){
  if(!$s -or $s.Length -eq 0){ return $s }
  return $s.Substring(0,1).ToLower() + $s.Substring(1)
}

# Parse fields
$fieldList = @()
foreach($f in $Fields.Split(",")){
  $p = $f.Trim()
  if($p -eq ""){ continue }
  $kv = $p.Split(":")
  if($kv.Length -ne 2){ throw "Field inválido: $p (usa nombre:Tipo)" }
  $fieldList += [pscustomobject]@{ Name=$kv[0].Trim(); Type=$kv[1].Trim() }
}

$entityName = Upper1 $Entity
$entityVar  = Lower1 $Entity
$basePkg    = $BasePackage

$srcMainJava = Join-Path $ProjectDir ("src\main\java\" + $basePkg.Replace(".","\"))
if(!(Test-Path $srcMainJava)){
  throw "No encuentro src/main/java para package $basePkg en $ProjectDir. Revisá -ProjectDir y -BasePackage."
}

# Feature packages
$featureRoot = Join-Path $srcMainJava $entityVar
$pkgApi      = "$basePkg.$entityVar.api"
$pkgApp      = "$basePkg.$entityVar.application"
$pkgDomain   = "$basePkg.$entityVar.domain"
$pkgInfra    = "$basePkg.$entityVar.infrastructure"

Ensure-Dir (Join-Path $featureRoot "api")
Ensure-Dir (Join-Path $featureRoot "application")
Ensure-Dir (Join-Path $featureRoot "domain")
Ensure-Dir (Join-Path $featureRoot "infrastructure")
Ensure-Dir (Join-Path $featureRoot "api\dto")

# ---------- DOMAIN (Entity/Document) ----------
$ann = if($Db -eq "mysql"){"@Entity`n@Table(name = `"$($entityVar)s`")"} else {"@Document(collection = `"$($entityVar)s`")"}
$imports = @(
  "import lombok.*;"
)
if($Db -eq "mysql"){
  $imports += @(
    "import jakarta.persistence.*;"
  )
} else {
  $imports += @(
    "import org.springframework.data.annotation.Id;",
    "import org.springframework.data.mongodb.core.mapping.Document;"
  )
}

# id annotation
$idDecl = if($Db -eq "mysql"){
  if($IdType -eq "Long"){
    "  @Id`n  @GeneratedValue(strategy = GenerationType.IDENTITY)`n  private Long id;"
  } else {
    "  @Id`n  private $IdType id;"
  }
} else {
  "  @Id`n  private $IdType id;"
}

$fieldsDecl = ($fieldList | ForEach-Object { "  private $($_.Type) $($_.Name);" }) -join "`n"

$entityJava = @"
package $pkgDomain;

$($imports -join "`n")

$ann
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class $entityName {

$idDecl

$fieldsDecl
}
"@

$entityPath = Join-Path $featureRoot "domain\$entityName.java"
$entityJava | Set-Content -Encoding UTF8 $entityPath

# ---------- DTOs ----------
$dtoImports = @(
  "import lombok.*;",
  "import jakarta.validation.constraints.*;"
)

$createFields = ($fieldList | ForEach-Object { "  private $($_.Type) $($_.Name);" }) -join "`n"
$updateFields = $createFields
$responseFields = "  private $IdType id;`n" + $createFields

$dtoCreate = @"
package $basePkg.$entityVar.api.dto;

$($dtoImports -join "`n")

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ${entityName}CreateRequest {
$createFields
}
"@

$dtoUpdate = @"
package $basePkg.$entityVar.api.dto;

$($dtoImports -join "`n")

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ${entityName}UpdateRequest {
$updateFields
}
"@

$dtoResp = @"
package $basePkg.$entityVar.api.dto;

import lombok.*;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ${entityName}Response {
$responseFields
}
"@

$dtoDir = Join-Path $featureRoot "api\dto"
$dtoCreate | Set-Content -Encoding UTF8 (Join-Path $dtoDir "${entityName}CreateRequest.java")
$dtoUpdate | Set-Content -Encoding UTF8 (Join-Path $dtoDir "${entityName}UpdateRequest.java")
$dtoResp   | Set-Content -Encoding UTF8 (Join-Path $dtoDir "${entityName}Response.java")

# ---------- REPOSITORY ----------
$repoImports = if($Db -eq "mysql"){
  @("import org.springframework.data.jpa.repository.JpaRepository;")
} else {
  @("import org.springframework.data.mongodb.repository.MongoRepository;")
}
$repoExtends = if($Db -eq "mysql"){"JpaRepository"} else {"MongoRepository"}

$repoJava = @"
package $pkgInfra;

import $pkgDomain.$entityName;
$($repoImports -join "`n")

public interface ${entityName}Repository extends $repoExtends<$entityName, $IdType> {
}
"@

$repoPath = Join-Path $featureRoot "infrastructure\${entityName}Repository.java"
$repoJava | Set-Content -Encoding UTF8 $repoPath

# ---------- SERVICE ----------
$svcJava = @"
package $pkgApp;

import $pkgDomain.$entityName;
import $pkgInfra.${entityName}Repository;
import $basePkg.$entityVar.api.dto.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class ${entityName}Service {

  private final ${entityName}Repository repository;

  public ${entityName}Response create(${entityName}CreateRequest req) {
    $entityName entity = $entityName.builder()
$(
  ($fieldList | ForEach-Object { "      .$($_.Name)(req.get$([string](Upper1 $_.Name))())" }) -join "`n"
)
      .build();

    $entityName saved = repository.save(entity);
    return toResponse(saved);
  }

  public List<${entityName}Response> list() {
    return repository.findAll().stream().map(this::toResponse).toList();
  }

  public ${entityName}Response get($IdType id) {
    $entityName e = repository.findById(id)
      .orElseThrow(() -> new RuntimeException("$entityName no encontrado: " + id));
    return toResponse(e);
  }

  public ${entityName}Response update($IdType id, ${entityName}UpdateRequest req) {
    $entityName e = repository.findById(id)
      .orElseThrow(() -> new RuntimeException("$entityName no encontrado: " + id));

$(
  ($fieldList | ForEach-Object { "    e.set$([string](Upper1 $_.Name))(req.get$([string](Upper1 $_.Name))());" }) -join "`n"
)

    $entityName saved = repository.save(e);
    return toResponse(saved);
  }

  public void delete($IdType id) {
    repository.deleteById(id);
  }

  private ${entityName}Response toResponse($entityName e) {
    return ${entityName}Response.builder()
      .id(e.getId())
$(
  ($fieldList | ForEach-Object { "      .$($_.Name)(e.get$([string](Upper1 $_.Name))())" }) -join "`n"
)
      .build();
  }
}
"@

$svcPath = Join-Path $featureRoot "application\${entityName}Service.java"
$svcJava | Set-Content -Encoding UTF8 $svcPath

# ---------- CONTROLLER ----------
$baseRoute = "/" + ($entityVar.ToLower() + "s")
$controllerJava = @"
package $pkgApi;

import $pkgApp.${entityName}Service;
import $basePkg.$entityVar.api.dto.*;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("$baseRoute")
@RequiredArgsConstructor
public class ${entityName}Controller {

  private final ${entityName}Service service;

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  public ${entityName}Response create(@RequestBody @Valid ${entityName}CreateRequest req) {
    return service.create(req);
  }

  @GetMapping
  public List<${entityName}Response> list() {
    return service.list();
  }

  @GetMapping("/{id}")
  public ${entityName}Response get(@PathVariable $IdType id) {
    return service.get(id);
  }

  @PutMapping("/{id}")
  public ${entityName}Response update(@PathVariable $IdType id, @RequestBody @Valid ${entityName}UpdateRequest req) {
    return service.update(id, req);
  }

  @DeleteMapping("/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(@PathVariable $IdType id) {
    service.delete(id);
  }
}
"@

$ctrlPath = Join-Path $featureRoot "api\${entityName}Controller.java"
$controllerJava | Set-Content -Encoding UTF8 $ctrlPath

Write-Host "✅ CRUD generado:"
Write-Host " - $entityPath"
Write-Host " - $repoPath"
Write-Host " - $svcPath"
Write-Host " - $ctrlPath"
Write-Host "Endpoints: $baseRoute"