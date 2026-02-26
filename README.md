# genereator_ms_java
Generate micro services based on java, faster.

1) 
# ms-gen.ps1 
Genera la estrucura de archivos del micro servicio.
Ejemplo de uso en linea de comandos:
Utiliza el nombre del microservicio para generar el nombre del directorio a ubicar la estrucutra del mismo.

.\ms-gen.ps1 -Name ms_clientes -GroupId com.tuorg -Db mysql -Build maven -OutputDir .

2) 
# entity-gen.ps1 
Genera la entidad, dentro del directorio del microservicio, es decir,
genera la API de la entidad, del microservicio generado.

Ejemplo de uso en linea de comandos, mysql:
* 
.\entity-gen.ps1 `
  -ProjectDir C:\dev\ms-clientes `
  -BasePackage com.tuorg.msclientes `
  -Entity Cliente `
  -Db mysql `
  -IdType Long `
  -Fields "nombre:String,email:String,edad:Integer"

Ejemplo de uso en linea de comandos, mongo:
* 
.\entity-gen.ps1 `
  -ProjectDir C:\dev\ms-notas `
  -BasePackage com.tuorg.msnotas `
  -Entity Nota `
  -Db mongo `
  -IdType String `
  -Fields "title:String,contenido:String"

3) 
cd C:\dev\ms-clientes
mvn spring-boot:run