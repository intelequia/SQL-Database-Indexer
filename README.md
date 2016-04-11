# SQL-Database-Indexer
Script en PowerShell para Azure Automation que nos permite indexar las tablas de una base de datos dependiendo del porcentaje de fragmentación, además de modificar el tier de la base de datos para que se ejecute de forma más rápida y fluida, y el envió de un log al finalizar la tarea.

## Parámetros
1.	SqlServerName
Nombre del servidor de la base de datos, el propio script añade la ruta completa al nombre.
2.	DatabaseName
Nombre de la base de datos a indexar.
3.	SQLCredentialName
Identificador de las credenciales que debemos haber creado previamente con los datos de acceso a la base de datos.
4.	Edition
Edición de Azure SQL Database para realizar el indexado (Basic, Standard, Premium)
5.	PerfLevel
Nivel de rendimiento de Azure SQL Database para realizar el indexado (Basic, S0, S1, S2, P1, P2, P3)
6.	FinalEdition
Edición de Azure SQL Database para reestablecer después de realizar el indexado (Basic, Standard, Premium)
7.	FinalPerfLevel
Nivel de rendimiento de Azure SQL Database para reestablecer después de realizar el indexado (Basic, S0, S1, S2, P1, P2, P3)
8.	FragPercentage -Opcional
Porcentaje de fragmentación que comprobamos en las tablas para realizar el indexado. Por defecto un 10%
9.	SqlServerPort -Opcional
Puerto de la conexión al SQL Server. Por defecto 1433
10.	RebuiltOffline -Opcional
Parámetro para especificar si falla el indexado de forma online lo intente offline. Por defecto falso
11.	Table –Opcional
Si queremos indexar solo una tabla especifica. Por defecto indexa todas las tablas.
12.	SMTPServer –Opcional –Obligatorio si queremos enviar la notificación.
Dirección del servidor de SMTP para realizar el envío de la notificación. Por defecto no se envía ningún email si este campo no tiene contenido.
13.	SMTPCredentials –Opcional –Obligatorio si queremos enviar la notificación.
Identificador de las credenciales que debemos haber creado previamente con los datos de acceso al servidor SMTP.
14.	FromMail –Opcional –Obligatorio si queremos enviar la notificación.
Email del emisor.
15.	ToMail –Opcional –Obligatorio si queremos enviar la notificación.
Email que va a recibir la notificación.

##Instalación
Para realizar el despliegue de este script en Azure Automation os remito al blog de [David Rodiguez Hernández](http://davidjrh.intelequia.com/2015/10/rebuilding-sql-database-indexes-using.html)
