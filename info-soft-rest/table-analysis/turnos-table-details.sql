  SELECT
      COLUMN_NAME,
      DATA_TYPE,
      IS_NULLABLE,
      COLUMN_DEFAULT,
      ORDINAL_POSITION
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_NAME = 'turnos'
  ORDER BY ORDINAL_POSITION;

COLUMN_NAME	DATA_TYPE	IS_NULLABLE	COLUMN_DEFAULT	ORDINAL_POSITION
idturnointerno	bigint	NO	NULL	1
idturno	bigint	YES	NULL	2
fondo	money	YES	NULL	3
apertura	datetime	YES	NULL	4
cierre	datetime	YES	NULL	5
idestacion	varchar	YES	NULL	6
cajero	varchar	YES	NULL	7
efectivo	money	YES	NULL	8
tarjeta	money	YES	NULL	9
vales	money	YES	NULL	10
credito	money	YES	NULL	11
procesadoweb	bit	YES	NULL	12
idempresa	varchar	YES	NULL	13
enviadoacentral	bit	YES	NULL	14
fechaenviado	datetime	YES	(NULL)	15
usuarioenvio	varchar	YES	NULL	16
offline	bit	YES	(NULL)	17
enviadoaf	bit	NO	((0))	18
corte_enviado	bit	NO	((0))	19
eliminartemporalesencierre	bit	NO	((0))	20
idmesero	varchar	YES	(NULL)	21
fondodolares	money	YES	((0))	22
procesado	bit	NO	((0))	23
WorkspaceId	uniqueidentifier	YES	(newid())	24

  SELECT
      tc.CONSTRAINT_NAME,
      tc.CONSTRAINT_TYPE,
      ccu.COLUMN_NAME
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc       
  JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
      ON tc.CONSTRAINT_NAME = ccu.CONSTRAINT_NAME    
  WHERE tc.TABLE_NAME = 'turnos'
      AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY';   

CONSTRAINT_NAME	CONSTRAINT_TYPE	COLUMN_NAME
PK_turnos_1	PRIMARY KEY	idturnointerno



  SELECT TOP 10
      idturnointerno,
      idturno,
      apertura,
      cierre,
      cajero,
      idestacion
  FROM turnos
  ORDER BY apertura DESC;
idturnointerno	idturno	apertura	cierre	cajero	idestacion
80885	894	2025-07-25 08:17:04.000	NULL	AVOQADO	DESKTOP-1601QUU
80884	893	2025-07-24 19:34:46.000	2025-07-25 08:11:57.000	AVOQADO	DESKTOP-1601QUU
80883	892	2025-07-24 18:42:05.000	2025-07-24 19:32:10.000	AVOQADO	DESKTOP-1601QUU
80882	891	2025-07-24 18:13:13.000	2025-07-24 18:41:23.000	AVOQADO	DESKTOP-1601QUU
80881	890	2025-07-24 17:33:30.000	2025-07-24 18:12:35.000	AVOQADO	DESKTOP-1601QUU
80880	889	2025-07-24 17:29:50.000	2025-07-24 17:31:27.000	AVOQADO	DESKTOP-1601QUU
80879	888	2025-07-24 17:19:55.000	2025-07-24 17:20:51.000	AVOQADO	DESKTOP-1601QUU
80878	887	2025-07-24 17:07:21.000	2025-07-24 17:12:12.000	AVOQADO	DESKTOP-1601QUU
80877	886	2025-07-18 07:14:25.000	2025-07-24 17:06:56.000	AVOQADO	DESKTOP-1601QUU
80876	885	2025-07-16 19:22:17.000	2025-07-18 07:13:29.000	AVOQADO	DESKTOP-1601QUU

 SELECT
      'idturnointerno' as campo,
      COUNT(*) as total_registros,
      COUNT(idturnointerno) as registros_con_valor,  
      COUNT(*) - COUNT(idturnointerno) as registros_nulos
  FROM turnos
  UNION ALL
  SELECT
      'idturno' as campo,
      COUNT(*) as total_registros,
      COUNT(idturno) as registros_con_valor,
      COUNT(*) - COUNT(idturno) as registros_nulos   
  FROM turnos;

  campo	total_registros	registros_con_valor	registros_nulos
idturnointerno	624	624	0
idturno	624	624	0


  SELECT
      'Búsqueda por idturnointerno' as tipo_busqueda,
      COUNT(*) as registros_encontrados
  FROM turnos
  WHERE idturnointerno = 800
  UNION ALL
  SELECT
      'Búsqueda por idturno' as tipo_busqueda,       
      COUNT(*) as registros_encontrados
  FROM turnos
  WHERE idturno = 800;

  tipo_busqueda	registros_encontrados
Búsqueda por idturnointerno	0
Búsqueda por idturno	1

  -- Y ver los datos específicos:
  SELECT 'IDTURNOINTERNO = 800' as busqueda, * FROM turnos WHERE idturnointerno = 800;
  busqueda	idturnointerno	idturno	fondo	apertura	cierre	idestacion	cajero	efectivo	tarjeta	vales	credito	procesadoweb	idempresa	enviadoacentral	fechaenviado	usuarioenvio	offline	enviadoaf	corte_enviado	eliminartemporalesencierre	idmesero	fondodolares	procesado	WorkspaceId
  SELECT 'IDTURNO = 800' as busqueda, * FROM turnos WHERE idturno = 800;
  busqueda	idturnointerno	idturno	fondo	apertura	cierre	idestacion	cajero	efectivo	tarjeta	vales	credito	procesadoweb	idempresa	enviadoacentral	fechaenviado	usuarioenvio	offline	enviadoaf	corte_enviado	eliminartemporalesencierre	idmesero	fondodolares	procesado	WorkspaceId
IDTURNO = 800	70792	800	3000.00	2025-04-30 07:51:17.000	2025-04-30 18:36:32.000	DESKTOP-1601QUU	CAJERA 3	13575.95	3867.05	0.00	0.00	NULL	0000000001	NULL	NULL	NULL	NULL	1	1	1		0.00	1	602677B6-E519-422F-8F07-3C929AFF63C9


 SELECT
      fk.CONSTRAINT_NAME,
      fk.TABLE_NAME as tabla_origen,
      ccu1.COLUMN_NAME as columna_origen,
      ccu2.COLUMN_NAME as columna_destino
  FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc 
  JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE fk ON rc.CONSTRAINT_NAME = fk.CONSTRAINT_NAME
  JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu1 ON rc.CONSTRAINT_NAME =
  ccu1.CONSTRAINT_NAME
  JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu2 ON rc.UNIQUE_CONSTRAINT_NAME =
  ccu2.CONSTRAINT_NAME
  WHERE ccu2.TABLE_NAME = 'turnos';

  CONSTRAINT_NAME	tabla_origen	columna_origen	columna_destino

    SELECT TOP 10
      folio,
      idturno,
      mesa,
      pagado,
      cancelado,
      fecha
  FROM tempcheques
  WHERE idturno IS NOT NULL
  ORDER BY fecha DESC;

  folio	idturno	mesa	pagado	cancelado	fecha
1	894	22	1	0	2025-07-25 08:17:15.000