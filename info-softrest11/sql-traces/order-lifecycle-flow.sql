1	RPC Completed	25/07/2025 08:16:59.167 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
2	SQL Batch Completed	25/07/2025 08:16:59.167 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	127	8268	78	
3	SQL Batch Completed	25/07/2025 08:16:59.208 a. m.	SELECT * FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	260	8268	78	
4	SQL Batch Completed	25/07/2025 08:16:59.289 a. m.	SELECT * FROM turnos WHERE cierre is null and apertura is not null and idestacion='DESKTOP-1601QUU'  AND idempresa='0000000001' and idmesero=''	SoftRestaurant®	avov2		sa	0	31	0	1884	8268	78	
5	RPC Completed	25/07/2025 08:16:59.336 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
6	SQL Batch Completed	25/07/2025 08:16:59.337 a. m.	SELECT cajontipo,cajonascii,cajonpuerto,cajontipoconexion,cajonimpresora,usacajondedinero,impresoracheques FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	122	8268	78	
7	RPC Completed	25/07/2025 08:16:59.382 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	27	8268	78	
8	SQL Batch Completed	25/07/2025 08:16:59.383 a. m.	SELECT * FROM app_settings WHERE app_id=1 AND field='dev_cashdro_sr' and field_value='TRUE'	SoftRestaurant®	avov2		sa	0	6	0	588	8268	78	
9	RPC Completed	25/07/2025 08:16:59.469 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
10	SQL Batch Completed	25/07/2025 08:16:59.469 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	341	8268	78	
11	SQL Batch Completed	25/07/2025 08:16:59.524 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	15000	12	0	13238	8268	78	
12	RPC Completed	25/07/2025 08:16:59.602 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	66	8268	78	
13	SQL Batch Completed	25/07/2025 08:16:59.603 a. m.	SELECT fondofijocaja,monedanacional FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	113	8268	78	
14	SQL Batch Completed	25/07/2025 08:16:59.644 a. m.	SELECT * FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	287	8268	78	
15	SQL Batch Completed	25/07/2025 08:16:59.714 a. m.	SELECT * FROM turnos WHERE cierre is null and apertura is not null AND idestacion='DESKTOP-1601QUU'  AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	28	0	3310	8268	78	
16	RPC Completed	25/07/2025 08:16:59.764 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
17	SQL Batch Completed	25/07/2025 08:16:59.764 a. m.	SELECT dev_dominicana, solicitadeclaraciondecajero FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	101	8268	78	
18	RPC Completed	25/07/2025 08:17:03.727 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
19	SQL Batch Completed	25/07/2025 08:17:03.728 a. m.	SELECT fechau as fecha from parametros3	SoftRestaurant®	avov2		sa	0	3	0	122	8268	78	
20	SQL Batch Completed	25/07/2025 08:17:03.770 a. m.	select rl.tipomodulo,rl.numerocontrol,r.* from renta r inner join registro_licencias rl on r.modulo=rl.nombre WHERE r.mesaño='UTXb8gqzBrucmeMvrNRwBg==' AND rl.nombre='SOFTRESTAURANT11' AND rl.tipomodulo=1	SoftRestaurant®	avov2		sa	0	3	0	149	8268	78	
21	RPC Completed	25/07/2025 08:17:03.815 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
22	SQL Batch Completed	25/07/2025 08:17:03.816 a. m.	SELECT * FROM app_settings WHERE app_id=1 AND field='dev_cashdro_sr' and field_value='TRUE'	SoftRestaurant®	avov2		sa	0	6	0	524	8268	78	
23	RPC Completed	25/07/2025 08:17:03.860 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
24	SQL Batch Completed	25/07/2025 08:17:03.860 a. m.	SELECT * FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	16000	2	0	269	8268	78	
25	SQL Batch Completed	25/07/2025 08:17:03.930 a. m.	SELECT * FROM turnos WHERE cierre is null and apertura is not null and idestacion='DESKTOP-1601QUU' AND idempresa='0000000001' and idmesero=''	SoftRestaurant®	avov2		sa	0	16	0	358	8268	78	
26	SQL Batch Completed	25/07/2025 08:17:03.975 a. m.	SELECT * FROM turnos WHERE apertura='2025-07-25T08:17:04' AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	22	0	2992	8268	78	
27	SQL Batch Completed	25/07/2025 08:17:04.017 a. m.	SELECT * FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001' and idmesero=''	SoftRestaurant®	avov2		sa	15000	16	0	472	8268	78	
28	SQL Batch Completed	25/07/2025 08:17:04.063 a. m.	SELECT MAX(apertura) AS apertura,MAX(cierre) AS cierre  FROM turnos	SoftRestaurant®	avov2		sa	0	22	0	5385	8268	78	
29	SQL Batch Completed	25/07/2025 08:17:04.381 a. m.	SELECT cierre FROM turnos WHERE cierre is not null AND idestacion='DESKTOP-1601QUU'  AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	25	0	3574	8268	78	
30	SQL Batch Completed	25/07/2025 08:17:04.438 a. m.	SELECT cierre FROM turnos WHERE idturno IN (SELECT MAX(idturno) FROM turnos WHERE cierre is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001') AND idestacion='DESKTOP-1601QUU' AND cierre is not null AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	44	0	10387	8268	78	
31	SQL Batch Completed	25/07/2025 08:17:04.480 a. m.	select ultimoturno from parametros	SoftRestaurant®	avov2		sa	0	3	0	178	8268	78	
32	SQL Batch Completed	25/07/2025 08:17:04.520 a. m.	SELECT * FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	338	8268	78	
33	SQL Batch Completed	25/07/2025 08:17:04.590 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	27	8268	78	
34	SQL Batch Completed	25/07/2025 08:17:04.635 a. m.	INSERT INTO turnos (idturno,fondo,apertura,idestacion,cajero,idempresa,idmesero,fondodolares) VALUES(894,0.000000,'25/07/2025 08:17:04 AM','DESKTOP-1601QUU','AVOQADO','0000000001','',0.000000 )	SoftRestaurant®	avov2		sa	16000	62	0	7601	8268	78	
35	SQL Batch Completed	25/07/2025 08:17:04.673 a. m.	select field,field_value from app_settings where field = 'NSSYNC_VERSION' and app_id=1	SoftRestaurant®	avov2		sa	15000	6	0	517	8268	78	
36	SQL Batch Completed	25/07/2025 08:17:04.717 a. m.	select workspaceid as workspaceid from turnos where idturno = '894'	SoftRestaurant®	avov2		sa	0	16	0	442	8268	78	
37	SQL Batch Completed	25/07/2025 08:17:04.772 a. m.	IF NOT EXISTS(SELECT * from nsplatformcontrol where WorkspaceId = '{DCCC7821-4D3F-48D1-AAE0-47CCB37BFC9A}' and EntityType = 16)  BEGIN   INSERT INTO nsplatformcontrol (WorkspaceId,EntityType,OperationType,CreateDate) VALUES ('{DCCC7821-4D3F-48D1-AAE0-47CCB37BFC9A}',16,1,GETUTCDATE()) END ELSE   BEGIN   UPDATE nsplatformcontrol SET OperationType = 1, IsSync = 0, Attempts = 0, CreateDate=GETUTCDATE() where WorkspaceId = '{DCCC7821-4D3F-48D1-AAE0-47CCB37BFC9A}' and EntityType = 16 and IsSync = 1 and OperationType != 3 END 	SoftRestaurant®	avov2		sa	0	98	0	13841	8268	78	
38	SQL Batch Completed	25/07/2025 08:17:04.810 a. m.	INSERT INTO bitacoraenvioventas (fechaapertura) VALUES ('2025-07-25T08:17:04')	SoftRestaurant®	avov2		sa	0	2	0	440	8268	78	
39	SQL Batch Completed	25/07/2025 08:17:04.849 a. m.	update parametros set ultimoturno=894	SoftRestaurant®	avov2		sa	0	4	0	376	8268	78	
40	SQL Batch Completed	25/07/2025 08:17:04.887 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	391	8268	78	
41	RPC Completed	25/07/2025 08:17:04.949 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	85	8268	78	
42	SQL Batch Completed	25/07/2025 08:17:04.950 a. m.	SELECT tipolicencia,estaciones FROM registro_licencias WHERE tipolicencia!=1 AND LTRIM(RTRIM(nombre))='SOFTRESTAURANT11'	SoftRestaurant®	avov2		sa	0	3	0	161	8268	78	
43	RPC Completed	25/07/2025 08:17:08.905 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
44	SQL Batch Completed	25/07/2025 08:17:08.906 a. m.	select * from turnos where apertura>=dateadd(d,datediff(d,0, getdate()),-1) and apertura<dateadd(d,datediff(d,0, getdate()),0) and cierre is null  and idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	16	0	209	8268	78	
45	SQL Batch Completed	25/07/2025 08:17:08.954 a. m.	select * from turnos where cierre is null 	SoftRestaurant®	avov2		sa	0	16	0	202	8268	78	
46	SQL Batch Completed	25/07/2025 08:17:09.001 a. m.	select * from turnos where cierre is null  and idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	16	0	223	8268	78	
47	RPC Completed	25/07/2025 08:17:09.063 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
48	SQL Batch Completed	25/07/2025 08:17:09.063 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_impuestoimporte3' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	536	8268	78	
49	SQL Batch Completed	25/07/2025 08:17:09.113 a. m.	SELECT dev_impuestoimporte3 FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	137	8268	78	
50	SQL Batch Completed	25/07/2025 08:17:09.153 a. m.	SELECT prefijo_bascula from estaciones where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	147	8268	78	
51	SQL Batch Completed	25/07/2025 08:17:09.194 a. m.	SELECT * FROM usuarios	SoftRestaurant®	avov2		sa	0	2	0	129	8268	78	
52	SQL Batch Completed	25/07/2025 08:17:09.238 a. m.	SELECT * FROM folios WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	205	8268	78	
53	RPC Completed	25/07/2025 08:17:09.394 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	26	8268	78	
54	SQL Batch Completed	25/07/2025 08:17:09.394 a. m.	UPDATE ESTACIONES SET PosIsOpen=0 WHERE PosIsOpen=1 AND DATEDIFF(MINUTE,PosLastOnline,GETDATE())>2	SoftRestaurant®	avov2		sa	0	4	0	268	8268	78	
55	SQL Batch Completed	25/07/2025 08:17:09.433 a. m.	select estaciones from registro_licencias where tipomodulo=1	SoftRestaurant®	avov2		sa	0	3	0	142	8268	78	
56	SQL Batch Completed	25/07/2025 08:17:09.476 a. m.	select count(idestacion) as CountOposIsOpen from estaciones where PosIsOpen=1	SoftRestaurant®	avov2		sa	0	4	0	138	8268	78	
57	SQL Batch Completed	25/07/2025 08:17:09.521 a. m.	SELECT PosIsOpen FROM estaciones where idestacion='DESKTOP-7' and PosIsOpen=0	SoftRestaurant®	avov2		sa	0	2	0	137	8268	78	
58	SQL Batch Completed	25/07/2025 08:17:09.563 a. m.	UPDATE estaciones SET PosIsOpen=1, PosLastOnline=GETDATE() WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	574	8268	78	
59	RPC Completed	25/07/2025 08:17:09.631 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
60	SQL Batch Completed	25/07/2025 08:17:09.633 a. m.	SELECT * FROM productos WHERE usarcomedor=0 OR usardomicilio=0 OR usarrapido=0	SoftRestaurant®	avov2		sa	0	270	0	2133	8268	78	
61	SQL Batch Completed	25/07/2025 08:17:09.682 a. m.	SELECT actualizarcatalogos FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	191	8268	78	
62	RPC Completed	25/07/2025 08:17:09.733 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
63	SQL Batch Completed	25/07/2025 08:17:09.733 a. m.	SELECT folio,mesa,impreso,idmesero,seriefolio+convert(varchar,orden) as orden FROM tempcheques WHERE tipodeservicio=1  and (CAST(pagado as int)=0 OR (pagado=1 AND esalestatus=1) ) and CAST(cancelado as int)=0  and idarearestaurant='' order by mesa	SoftRestaurant®	avov2		sa	0	2	0	141	8268	78	
64	RPC Completed	25/07/2025 08:17:09.785 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
65	SQL Batch Completed	25/07/2025 08:17:09.785 a. m.	select ar.descripcion,ar.idarearestaurant from VisibilidadAreaParaVenta VAV inner join app_list AL on vav.FKapp_id = al.app_id inner join areasrestaurant AR on vav.FKidarearestaurant = ar.idarearestaurant where vav.FKidtiposervicio = 1 and vav.FKapp_id = 1 	SoftRestaurant®	avov2		sa	0	2	0	105	8268	78	
66	RPC Completed	25/07/2025 08:17:09.834 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
67	SQL Batch Completed	25/07/2025 08:17:09.835 a. m.	SELECT folio,mesa,impreso,idmesero,seriefolio+convert(varchar,orden) as orden FROM tempcheques WHERE tipodeservicio=1  and (CAST(pagado as int)=0 OR (pagado=1 AND esalestatus=1) ) and CAST(cancelado as int)=0  order by mesa	SoftRestaurant®	avov2		sa	0	2	0	130	8268	78	
68	RPC Completed	25/07/2025 08:17:10.172 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	78	
69	SQL Batch Completed	25/07/2025 08:17:10.174 a. m.	SELECT * FROM productos WHERE usarcomedor=0 OR usardomicilio=0 OR usarrapido=0	SoftRestaurant®	avov2		sa	16000	270	0	2144	8268	78	
70	SQL Batch Completed	25/07/2025 08:17:10.222 a. m.	SELECT actualizarcatalogos FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	143	8268	78	
71	RPC Completed	25/07/2025 08:17:13.179 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
72	SQL Batch Completed	25/07/2025 08:17:13.179 a. m.	select ar.descripcion,ar.idarearestaurant from VisibilidadAreaParaVenta VAV inner join app_list AL on vav.FKapp_id = al.app_id inner join areasrestaurant AR on vav.FKidarearestaurant = ar.idarearestaurant where ar.estatus=1 AND vav.FKidtiposervicio = 1 and vav.FKapp_id = 1 	SoftRestaurant®	avov2		sa	0	2	0	172	8268	78	
73	RPC Completed	25/07/2025 08:17:13.228 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
74	SQL Batch Completed	25/07/2025 08:17:13.229 a. m.	SELECT autorizausuariofacturarapido FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	107	8268	78	
75	SQL Batch Completed	25/07/2025 08:17:13.305 a. m.	SELECT forzarcapturamesa FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	103	8268	78	
76	RPC Completed	25/07/2025 08:17:13.375 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
77	SQL Batch Completed	25/07/2025 08:17:13.375 a. m.	SELECT idclientepublico FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	95	8268	78	
78	SQL Batch Completed	25/07/2025 08:17:13.417 a. m.	SELECT nombre FROM clientes WHERE idcliente='000008'	SoftRestaurant®	avov2		sa	0	2	0	141	8268	78	
79	RPC Completed	25/07/2025 08:17:15.083 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
80	SQL Batch Completed	25/07/2025 08:17:15.083 a. m.	SELECT * FROM meseros WHERE idmesero='1'	SoftRestaurant®	avov2		sa	0	5	0	270	8268	78	
81	RPC Completed	25/07/2025 08:17:15.133 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
82	SQL Batch Completed	25/07/2025 08:17:15.133 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	118	8268	78	
83	SQL Batch Completed	25/07/2025 08:17:15.174 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	112	8268	78	
84	SQL Batch Completed	25/07/2025 08:17:15.259 a. m.	SELECT * FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	16	0	511	8268	78	
85	RPC Completed	25/07/2025 08:17:15.308 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
86	SQL Batch Completed	25/07/2025 08:17:15.313 a. m.	SELECT MAX(apertura) AS apertura FROM turnos WHERE cierre is null	SoftRestaurant®	avov2		sa	0	22	0	4164	8268	78	
87	SQL Batch Completed	25/07/2025 08:17:15.366 a. m.	SELECT * FROM tempcheques WHERE CAST(pagado as INT)=0 AND CAST(cancelado as int)=0 AND tipodeservicio=1 AND UPPER(mesa)='22'	SoftRestaurant®	avov2		sa	0	2	0	6910	8268	78	
88	SQL Batch Completed	25/07/2025 08:17:15.430 a. m.	SELECT ultimaorden FROM folios WITH (TABLOCKX)  WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	196	8268	78	
89	SQL Batch Completed	25/07/2025 08:17:15.507 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	42	8268	78	
90	SQL Batch Completed	25/07/2025 08:17:15.545 a. m.	SELECT * FROM tempcheques WHERE CAST(pagado as INT)=0 AND CAST(cancelado as int)=0 AND tipodeservicio=1 AND UPPER(mesa)='22'	SoftRestaurant®	avov2		sa	0	2	0	194	8268	78	
91	SQL Batch Completed	25/07/2025 08:17:15.631 a. m.	INSERT INTO tempcheques([seriefolio],[numcheque],[fecha],[cierre],[mesa],[nopersonas],[idmesero],[pagado],[impreso],[impresiones],[cambio],[descuento],[orden],[idcliente],[idarearestaurant],[idempresa],[tipodeservicio],[idturno],[comentariodescuento],[estacion],[usuariodescuento],[idtipodescuento],[numerotarjeta],[puntosmonederogenerados],[tarjetadescuento],[usuariopago],[observaciones],[iddireccion],[telefonousadodomicilio],[cargo],[descuentoimporte],[campoadicional1],[idreservacion],[idcomisionista],[tipoventarapida],[callcenter],[codigo_unico_af],[Usuarioapertura],[desc_porc_original])VALUES('',0,'25/07/2025 08:17:15 AM',NULL,'22',1,'1',0,0,0,0,0.000000,1,'','01','0000000001',1,0,'','DESKTOP-7','','','',0,'','','','','',0,0,'','','',0,0,'','AVOQADO',0.000000)	SoftRestaurant®	avov2		sa	31000	301	0	25936	8268	78	
92	SQL Batch Completed	25/07/2025 08:17:15.668 a. m.	SELECT SCOPE_IDENTITY() as maxfolio	SoftRestaurant®	avov2		sa	0	0	0	173	8268	78	
93	SQL Batch Completed	25/07/2025 08:17:15.710 a. m.	UPDATE folios SET ultimaorden=1 WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	200	8268	78	
94	SQL Batch Completed	25/07/2025 08:17:15.748 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	91	8268	78	
95	SQL Batch Completed	25/07/2025 08:17:15.790 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	115	8268	78	
96	SQL Batch Completed	25/07/2025 08:17:15.830 a. m.	insert into cuentas (clavemesa,clavemesero,numeropersonas,clavearea,estacion,imprimir,tiposervicio,enviadosr,foliocuenta,idmesa) values('22','1','1','01   ','DESKTOP-7',0,1,1,'1','')	SoftRestaurant®	avov2		sa	0	2	0	438	8268	78	
97	SQL Batch Completed	25/07/2025 08:17:15.873 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	706	8268	78	
98	RPC Completed	25/07/2025 08:17:15.938 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
99	SQL Batch Completed	25/07/2025 08:17:15.939 a. m.	SELECT * FROM tempcheques WHERE folio=1	SoftRestaurant®	avov2		sa	16000	2	0	339	8268	78	
100	RPC Completed	25/07/2025 08:17:15.999 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
101	SQL Batch Completed	25/07/2025 08:17:15.999 a. m.	SELECT dev_listadefault FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	112	8268	78	
102	SQL Batch Completed	25/07/2025 08:17:16.040 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_impuestoimporte3' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	873	8268	78	
103	SQL Batch Completed	25/07/2025 08:17:16.086 a. m.	SELECT dev_impuestoimporte3 FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	145	8268	78	
104	SQL Batch Completed	25/07/2025 08:17:16.163 a. m.	select* from cargosareas where idarearestaurant='01'	SoftRestaurant®	avov2		sa	0	0	0	128	8268	78	
105	RPC Completed	25/07/2025 08:17:16.209 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
106	SQL Batch Completed	25/07/2025 08:17:16.209 a. m.	select idmesa from mesasasignadas where activo=1 AND folio=1	SoftRestaurant®	avov2		sa	0	2	0	157	8268	78	
107	RPC Completed	25/07/2025 08:17:16.322 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
108	SQL Batch Completed	25/07/2025 08:17:16.323 a. m.	SELECT nombre FROM meseros WHERE idmesero='1'	SoftRestaurant®	avov2		sa	0	5	0	152	8268	78	
109	SQL Batch Completed	25/07/2025 08:17:16.363 a. m.	SELECT descripcion FROM areasrestaurant WHERE idarearestaurant='01'	SoftRestaurant®	avov2		sa	0	2	0	139	8268	78	
110	RPC Completed	25/07/2025 08:17:16.450 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
111	SQL Batch Completed	25/07/2025 08:17:16.450 a. m.	Select Distinct tempcheqdet.*, productos.descripcion, productos.nombrecorto FROM tempcheqdet LEFT JOIN productos On tempcheqdet.idproducto=productos.idproducto WHERE tempcheqdet.foliodet=1                    Order By movimiento 	SoftRestaurant®	avov2		sa	0	113	0	432	8268	78	
112	RPC Completed	25/07/2025 08:17:16.614 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
113	SQL Batch Completed	25/07/2025 08:17:16.614 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	110	8268	78	
114	SQL Batch Completed	25/07/2025 08:17:16.700 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1                    AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	355	8268	78	
115	RPC Completed	25/07/2025 08:17:16.746 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
116	SQL Batch Completed	25/07/2025 08:17:16.746 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	97	8268	78	
117	RPC Completed	25/07/2025 08:17:16.796 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
118	SQL Batch Completed	25/07/2025 08:17:16.796 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	91	8268	78	
119	SQL Batch Completed	25/07/2025 08:17:16.837 a. m.	select * from tempcheqdet WHERE  foliodet=1                   	SoftRestaurant®	avov2		sa	0	113	0	557	8268	78	
120	SQL Batch Completed	25/07/2025 08:17:16.892 a. m.	select * from tempcheques where folio=1                    	SoftRestaurant®	avov2		sa	0	2	0	471	8268	78	
121	SQL Batch Completed	25/07/2025 08:17:17.036 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	146	8268	78	
122	SQL Batch Completed	25/07/2025 08:17:17.077 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	28	8268	78	
123	SQL Batch Completed	25/07/2025 08:17:17.117 a. m.	UPDATE tempcheques set  totalarticulos=0.000000,  subtotal=0.000000,  total=0.000000,  totalconpropina=0.000000,  totalsindescuento=0.000000,  totalimpuesto1=0.000000,  totalalimentos=0.000000,  totalbebidas=0.000000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=0.000000,  totalconpropinacargo=0.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=0.000000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=0.000000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=0.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=0.000000,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=0.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	36	0	1584	8268	78	
124	SQL Batch Completed	25/07/2025 08:17:17.157 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	32	0	1472	8268	78	
125	SQL Batch Completed	25/07/2025 08:17:17.202 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	206	8268	78	
126	SQL Batch Completed	25/07/2025 08:17:17.244 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	96	8268	78	
127	SQL Batch Completed	25/07/2025 08:17:17.286 a. m.	UPDATE cuentas SET total=0.000000, subtotal =0.000000, totalimpuesto1=0.000000,descuentoimporte=0.000000 where foliocuenta=1                    	SoftRestaurant®	avov2		sa	0	13	0	200	8268	78	
128	SQL Batch Completed	25/07/2025 08:17:17.325 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	342	8268	78	
129	RPC Completed	25/07/2025 08:17:17.368 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	30	8268	78	
130	SQL Batch Completed	25/07/2025 08:17:17.369 a. m.	SELECT * FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	592	8268	78	
131	RPC Completed	25/07/2025 08:17:17.471 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
132	SQL Batch Completed	25/07/2025 08:17:17.471 a. m.	SELECT folio,mesa,impreso,idmesero,seriefolio+convert(varchar,orden) as orden FROM tempcheques WHERE tipodeservicio=1  and (CAST(pagado as int)=0 OR (pagado=1 AND esalestatus=1) ) and CAST(cancelado as int)=0  order by mesa	SoftRestaurant®	avov2		sa	0	2	0	144	8268	78	
133	RPC Completed	25/07/2025 08:17:17.523 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
134	SQL Batch Completed	25/07/2025 08:17:17.523 a. m.	Select cuentaenuso FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	376	8268	78	
135	RPC Completed	25/07/2025 08:17:17.567 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
136	SQL Batch Completed	25/07/2025 08:17:17.567 a. m.	Select impreso FROM tempcheques WHERE folio='1'	SoftRestaurant®	avov2		sa	0	2	0	131	8268	78	
137	RPC Completed	25/07/2025 08:17:17.625 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
138	SQL Batch Completed	25/07/2025 08:17:17.625 a. m.	SELECT prefijo_bascula from estaciones where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	157	8268	78	
139	RPC Completed	25/07/2025 08:17:17.705 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
140	SQL Batch Completed	25/07/2025 08:17:17.706 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_impuestoimporte3' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	862	8268	78	
141	SQL Batch Completed	25/07/2025 08:17:17.753 a. m.	SELECT dev_impuestoimporte3 FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	112	8268	78	
142	SQL Batch Completed	25/07/2025 08:17:17.795 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dtomodificadores' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	1063	8268	78	
143	SQL Batch Completed	25/07/2025 08:17:17.854 a. m.	SELECT dtomodificadores FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	121	8268	78	
144	SQL Batch Completed	25/07/2025 08:17:17.895 a. m.	SELECT prefijo_bascula from estaciones where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	191	8268	78	
145	SQL Batch Completed	25/07/2025 08:17:17.963 a. m.	SELECT reducir_fuente_encabezado_captura_productos FROM pos_settings where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	126	8268	78	
146	RPC Completed	25/07/2025 08:17:18.008 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
147	SQL Batch Completed	25/07/2025 08:17:18.008 a. m.	SELECT * FROM registro_licencias	SoftRestaurant®	avov2		sa	0	3	0	104	8268	78	
148	SQL Batch Completed	25/07/2025 08:17:18.054 a. m.	SELECT sysdatabase FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	129	8268	78	
149	SQL Batch Completed	25/07/2025 08:17:18.096 a. m.	UPDATE configuracion SET sysdatabase='9CE46F85A76C74A79E966914A8187067831469FA'	SoftRestaurant®	avov2		sa	0	3	0	406	8268	78	
150	SQL Batch Completed	25/07/2025 08:17:18.134 a. m.	SELECT CAST( SERVERPROPERTY( 'MachineName' ) AS varchar( 30 ) ) AS MachineName	SoftRestaurant®	avov2		sa	0	0	0	322	8268	78	
151	RPC Completed	25/07/2025 08:17:18.215 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
152	SQL Batch Completed	25/07/2025 08:17:18.215 a. m.	SELECT formatofecha,obtenerfechahoraremota,estacionfechahora FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	148	8268	78	
153	SQL Batch Completed	25/07/2025 08:17:18.258 a. m.	SELECT idestacion,colorletrabotones FROM pos_settings WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	144	8268	78	
154	SQL Batch Completed	25/07/2025 08:17:18.301 a. m.	Select idestacion,colorbotones,colorpantallas,colorcuadrosdetexto,colorbarratitulo ,nombrepuntodeventa,serieimpresoracuentas,rutatemporal From estaciones Where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	162	8268	78	
155	SQL Batch Completed	25/07/2025 08:17:18.356 a. m.	Update estaciones Set descripcion='DESKTOP-7',serie='1085579933',ip='172.29.224.1,10.211.55.4,100.120.144.3',estado='7998F5741244A6766368F7902B90B1525618820C' Where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	599	8268	78	
156	SQL Batch Completed	25/07/2025 08:17:18.396 a. m.	Select costopromedioformula From parametros	SoftRestaurant®	avov2		sa	0	3	0	123	8268	78	
157	SQL Batch Completed	25/07/2025 08:17:18.469 a. m.	Select polizanumdivision,urlregistrosweb From configuracion 	SoftRestaurant®	avov2		sa	0	3	0	100	8268	78	
158	SQL Batch Completed	25/07/2025 08:17:18.514 a. m.	Select * From usuarios	SoftRestaurant®	avov2		sa	0	2	0	132	8268	78	
159	SQL Batch Completed	25/07/2025 08:17:18.558 a. m.	Select registrocontribuyente From configuracion 	SoftRestaurant®	avov2		sa	0	3	0	104	8268	78	
160	SQL Batch Completed	25/07/2025 08:17:18.604 a. m.	Select * From empresas 	SoftRestaurant®	avov2		sa	0	198	0	1669	8268	78	
161	RPC Completed	25/07/2025 08:17:18.769 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
162	SQL Batch Completed	25/07/2025 08:17:18.769 a. m.	SELECT tipomodulo,nombre,tipolicencia,mesanio,licencia FROM registro_licencias WHERE tipomodulo=1 AND nombre='SOFTRESTAURANT11' AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	3	0	214	8268	78	
163	RPC Completed	25/07/2025 08:17:18.818 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
164	SQL Batch Completed	25/07/2025 08:17:18.818 a. m.	SELECT fechau as fecha from parametros3	SoftRestaurant®	avov2		sa	0	3	0	101	8268	78	
165	RPC Completed	25/07/2025 08:17:18.907 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
166	SQL Batch Completed	25/07/2025 08:17:18.907 a. m.	SELECT formatofecha,obtenerfechahoraremota,estacionfechahora FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	87	8268	78	
167	RPC Completed	25/07/2025 08:17:19.412 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
168	SQL Batch Completed	25/07/2025 08:17:19.414 a. m.	SELECT * FROM empresas	SoftRestaurant®	avov2		sa	0	198	0	2022	8268	78	
169	SQL Batch Completed	25/07/2025 08:17:20.017 a. m.	SELECT * FROM Empresas	SoftRestaurant®	avov2		sa	0	198	0	158782	8268	73	
170	RPC Completed	25/07/2025 08:17:20.101 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	73	
171	SQL Batch Completed	25/07/2025 08:17:20.141 a. m.	SELECT * FROM Empresas	SoftRestaurant®	avov2		sa	0	198	0	40016	8268	73	
172	RPC Completed	25/07/2025 08:17:20.205 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	26	8268	73	
173	SQL Batch Completed	25/07/2025 08:17:20.248 a. m.	SELECT * FROM Empresas	SoftRestaurant®	avov2		sa	0	198	0	43061	8268	73	
174	RPC Completed	25/07/2025 08:17:20.302 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	73	
175	SQL Batch Completed	25/07/2025 08:17:20.303 a. m.	SELECT id,app_id,field,field_value FROM app_settings WHERE app_id=1.0000 AND field='LicLock'	SoftRestaurant®	avov2		sa	0	6	0	662	8268	73	
176	SQL Batch Completed	25/07/2025 08:17:20.461 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	16000	4	0	613	8268	78	
177	SQL Batch Completed	25/07/2025 08:17:20.516 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	0	12	0	13257	8268	78	
178	SQL Batch Completed	25/07/2025 08:17:20.579 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	16000	4	0	552	8268	78	
179	SQL Batch Completed	25/07/2025 08:17:20.636 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	15000	12	0	13414	8268	78	
180	SQL Batch Completed	25/07/2025 08:17:20.698 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	491	8268	78	
181	SQL Batch Completed	25/07/2025 08:17:20.753 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	15000	12	0	13586	8268	78	
182	RPC Completed	25/07/2025 08:17:20.843 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	79	8268	78	
183	SQL Batch Completed	25/07/2025 08:17:20.845 a. m.	SELECT * FROM productos WHERE usarcomedor=0 OR usardomicilio=0 OR usarrapido=0	SoftRestaurant®	avov2		sa	16000	270	0	2142	8268	78	
184	SQL Batch Completed	25/07/2025 08:17:20.894 a. m.	SELECT actualizarcatalogos FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	117	8268	78	
185	RPC Completed	25/07/2025 08:17:20.954 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
186	SQL Batch Completed	25/07/2025 08:17:20.955 a. m.	Update tempcheques Set cuentaenuso=1 Where folio=1                   	SoftRestaurant®	avov2		sa	15000	31	0	1517	8268	78	
187	RPC Completed	25/07/2025 08:17:21.031 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	78	
188	SQL Batch Completed	25/07/2025 08:17:21.032 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_preciocostarica' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	913	8268	78	
189	SQL Batch Completed	25/07/2025 08:17:21.077 a. m.	SELECT dev_preciocostarica FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	111	8268	78	
190	RPC Completed	25/07/2025 08:17:21.141 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
191	SQL Batch Completed	25/07/2025 08:17:21.141 a. m.	SELECT ultimospedidos,baseordenarproductos FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	116	8268	78	
192	RPC Completed	25/07/2025 08:17:21.184 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
193	SQL Batch Completed	25/07/2025 08:17:21.184 a. m.	select permventaneg from parametros3	SoftRestaurant®	avov2		sa	0	3	0	118	8268	78	
194	RPC Completed	25/07/2025 08:17:23.331 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
195	SQL Batch Completed	25/07/2025 08:17:23.332 a. m.	select * from modificadores where idproducto='03004' and idmodificador in (select idproducto from productos where usarcomedor=1)	SoftRestaurant®	avov2		sa	0	26	0	929	8268	78	
196	RPC Completed	25/07/2025 08:17:24.841 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
197	SQL Batch Completed	25/07/2025 08:17:24.841 a. m.	Select impreso FROM tempcheques WHERE folio='1'	SoftRestaurant®	avov2		sa	0	2	0	130	8268	78	
198	RPC Completed	25/07/2025 08:17:24.885 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
199	SQL Batch Completed	25/07/2025 08:17:24.885 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	102	8268	78	
200	SQL Batch Completed	25/07/2025 08:17:24.927 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	122	8268	78	
201	SQL Batch Completed	25/07/2025 08:17:25.021 a. m.	SELECT idturno FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'and idmesero=''	SoftRestaurant®	avov2		sa	0	16	0	264	8268	78	
202	RPC Completed	25/07/2025 08:17:25.073 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
203	SQL Batch Completed	25/07/2025 08:17:25.079 a. m.	SELECT * FROM tempcheques WHERE folio=1                    AND CAST(impreso as int)=0	SoftRestaurant®	avov2		sa	0	2	0	6048	8268	78	
204	SQL Batch Completed	25/07/2025 08:17:25.144 a. m.	select max(movimiento) as  maximo from tempcheqdet WHERE foliodet =1                   	SoftRestaurant®	avov2		sa	0	113	0	4449	8268	78	
205	SQL Batch Completed	25/07/2025 08:17:25.192 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	38	8268	78	
206	SQL Batch Completed	25/07/2025 08:17:25.229 a. m.	SELECT ultimofolioproduccion FROM folios WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	192	8268	78	
207	SQL Batch Completed	25/07/2025 08:17:25.328 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	153	8268	78	
208	SQL Batch Completed	25/07/2025 08:17:25.367 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	92	8268	78	
209	SQL Batch Completed	25/07/2025 08:17:25.407 a. m.	SELECT MAX(idcomanda)idcomanda FROM detallescuentas WHERE clavemesa= (SELECT TOP 1 clavemesa FROM cuentas WHERE foliocuenta =1.000000)	SoftRestaurant®	avov2		sa	0	60	0	269	8268	78	
210	SQL Batch Completed	25/07/2025 08:17:25.451 a. m.	SELECT MAX(movimiento)movimiento FROM tempcheqdet WHERE foliodet=1.000000	SoftRestaurant®	avov2		sa	0	113	0	4319	8268	78	
211	SQL Batch Completed	25/07/2025 08:17:25.492 a. m.	SELECT dev_listadefault FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	103	8268	78	
212	SQL Batch Completed	25/07/2025 08:17:25.534 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_impuestoimporte3' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	851	8268	78	
213	SQL Batch Completed	25/07/2025 08:17:25.582 a. m.	SELECT dev_impuestoimporte3 FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	92	8268	78	
214	SQL Batch Completed	25/07/2025 08:17:25.622 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	84	8268	78	
215	SQL Batch Completed	25/07/2025 08:17:25.664 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	170	8268	78	
216	SQL Batch Completed	25/07/2025 08:17:25.704 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	99	8268	78	
217	SQL Batch Completed	25/07/2025 08:17:25.750 a. m.	select mesa from tempcheques where folio = '1'	SoftRestaurant®	avov2		sa	0	2	0	2586	8268	78	
218	SQL Batch Completed	25/07/2025 08:17:25.793 a. m.	select COUNT(*) as contador from cuentas where clavemesa = '22'	SoftRestaurant®	avov2		sa	0	13	0	325	8268	78	
219	SQL Batch Completed	25/07/2025 08:17:25.836 a. m.	select descripcion from productos where idproducto = '03004'	SoftRestaurant®	avov2		sa	0	2	0	200	8268	78	
220	SQL Batch Completed	25/07/2025 08:17:25.878 a. m.	INSERT INTO detallescuentas(clavemesa, clave, descripcion, precio, cantidad, comentario, modificador, estacion, enviadosr, descuento, movimiento,tiempo, hora, idproductocompuesto,productocompuestoprincipal,nivel, comanda, idcomanda) VALUES ('22','03004','ETIQUETA NEGRA BOTELLA',1500.000000,1,'',0,'DESKTOP-7',1, 0.000000,1.000000,'','25/07/2025 08:17:25 AM', '',0,0,'',1.000000)	SoftRestaurant®	avov2		sa	0	2	0	737	8268	78	
221	SQL Batch Completed	25/07/2025 08:17:25.941 a. m.	INSERT INTO tempcheqdet (foliodet,movimiento,comanda,cantidad,idproducto,descuento,precio,preciosinimpuestos,comentario,tiempo,mitad,hora,modificador,idestacion,impuesto1,impuesto2,impuesto3,usuariodescuento,comentariodescuento,idtipodescuento,idproductocompuesto,productocompuestoprincipal,preciocatalogo,marcar,idmeseroproducto,idcortesia,numerotarjeta,folioproduccion,nivel,sistema_envio,promovolumen) VALUES (1,1.000000,'',1.000000,'03004',0.000000,1500.000000,1293.103400,'','',0.000000,'25/07/2025 08:17:25 AM',0,'DESKTOP-7',16.000000,0.000000,0.000000,'','','','',0,1500.000000,0,'1','','',1.000000,0.000000,1.000000,0)	SoftRestaurant®	avov2		sa	15000	232	0	20285	8268	78	
222	SQL Batch Completed	25/07/2025 08:17:25.980 a. m.	UPDATE folios SET ultimofolioproduccion=1.000000 WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	162	8268	78	
223	SQL Batch Completed	25/07/2025 08:17:26.019 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	52	8268	78	
224	SQL Batch Completed	25/07/2025 08:17:26.061 a. m.	select clavemesa from cuentas where foliocuenta=1                   	SoftRestaurant®	avov2		sa	0	13	0	131	8268	78	
225	SQL Batch Completed	25/07/2025 08:17:26.120 a. m.	SELECT monitornivelprioridad,monitorprioridadactual,usarsecuenciatiemposmonitor FROM parametros	SoftRestaurant®	avov2		sa	0	3	0	93	8268	78	
226	SQL Batch Completed	25/07/2025 08:17:26.168 a. m.	UPDATE parametros SET monitorprioridadactual=1	SoftRestaurant®	avov2		sa	0	3	0	171	8268	78	
227	SQL Batch Completed	25/07/2025 08:17:26.210 a. m.	SELECT * FROM monitoresproduccion ORDER BY idmonitor	SoftRestaurant®	avov2		sa	0	2	0	112	8268	78	
228	SQL Batch Completed	25/07/2025 08:17:26.255 a. m.	select movimiento,comentario from tempcheqdet WHERE foliodet=1	SoftRestaurant®	avov2		sa	0	116	0	2403	8268	78	
229	SQL Batch Completed	25/07/2025 08:17:26.308 a. m.	UPDATE tempcheqdet SET prioridadproduccion='A' WHERE foliodet=1 AND movimiento=1 AND idproducto='03004'	SoftRestaurant®	avov2		sa	0	274	0	7015	8268	78	
230	SQL Batch Completed	25/07/2025 08:17:26.347 a. m.	INSERT INTO productosenproduccion (idproducto,folio,idmonitor,movimiento,cantidad,comentario,tiempo,hora,modificador,estadomonitor,idproductocompuesto,productocompuestoprincipal,minutospreparacion,minutosalerta,idturno_cierre,prioridad,separador  ) VALUES ('03004',1,'02',1,1,'','','25/07/2025 08:17:25 AM',0,0,'',0,0,0,894,'A' ,'0')	SoftRestaurant®	avov2		sa	0	6	0	467	8268	78	
231	SQL Batch Completed	25/07/2025 08:17:26.386 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	346	8268	78	
232	SQL Batch Completed	25/07/2025 08:17:26.432 a. m.	set implicit_transactions off 	SoftRestaurant®	avov2		sa	0	0	0	39	8268	78	
233	SQL Batch Completed	25/07/2025 08:17:26.469 a. m.	select sistema_envio,estacion,foodorder,mv_room,mv_lastname  from tempcheques where folio='1'	SoftRestaurant®	avov2		sa	0	2	0	173	8268	78	
234	SQL Batch Completed	25/07/2025 08:17:26.511 a. m.	select VentasOnline from parametros3	SoftRestaurant®	avov2		sa	0	3	0	136	8268	78	
235	SQL Batch Completed	25/07/2025 08:17:26.558 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	539	8268	78	
236	SQL Batch Completed	25/07/2025 08:17:26.615 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	16000	12	0	13863	8268	78	
237	SQL Batch Completed	25/07/2025 08:17:26.683 a. m.	SELECT only_areas_fastfood FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	124	8268	78	
238	SQL Batch Completed	25/07/2025 08:17:26.726 a. m.	SELECT * FROM estacionesareas  WHERE imprimir=1 and idestacion='DESKTOP-7' and impresion=1 and comedor=1	SoftRestaurant®	avov2		sa	0	12	0	173	8268	78	
239	SQL Batch Completed	25/07/2025 08:17:26.769 a. m.	select sistema_envio,estacion,foodorder,mv_room,mv_lastname  from tempcheques where folio='1'	SoftRestaurant®	avov2		sa	0	2	0	123	8268	78	
240	SQL Batch Completed	25/07/2025 08:17:26.809 a. m.	select VentasOnline from parametros3	SoftRestaurant®	avov2		sa	0	3	0	103	8268	78	
241	SQL Batch Completed	25/07/2025 08:17:26.850 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	475	8268	78	
242	SQL Batch Completed	25/07/2025 08:17:26.899 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	0	12	0	7612	8268	78	
243	SQL Batch Completed	25/07/2025 08:17:26.962 a. m.	SELECT only_areas_fastfood FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	134	8268	78	
244	SQL Batch Completed	25/07/2025 08:17:27.003 a. m.	SELECT * FROM estacionesareas  WHERE imprimir=1 and idestacion='DESKTOP-7' and impresion=2 and comedor=1	SoftRestaurant®	avov2		sa	0	12	0	160	8268	78	
245	SQL Batch Completed	25/07/2025 08:17:27.046 a. m.	select sistema_envio,estacion,foodorder,mv_room,mv_lastname  from tempcheques where folio='1'	SoftRestaurant®	avov2		sa	0	2	0	148	8268	78	
246	SQL Batch Completed	25/07/2025 08:17:27.086 a. m.	select VentasOnline from parametros3	SoftRestaurant®	avov2		sa	0	3	0	115	8268	78	
247	SQL Batch Completed	25/07/2025 08:17:27.128 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	566	8268	78	
248	SQL Batch Completed	25/07/2025 08:17:27.182 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=1 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=1 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	0	12	0	13198	8268	78	
249	SQL Batch Completed	25/07/2025 08:17:27.245 a. m.	SELECT only_areas_fastfood FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	176	8268	78	
250	SQL Batch Completed	25/07/2025 08:17:27.285 a. m.	SELECT * FROM estacionesareas  WHERE imprimir=1 and idestacion='DESKTOP-7' and impresion=3 and comedor=1	SoftRestaurant®	avov2		sa	0	12	0	173	8268	78	
251	RPC Completed	25/07/2025 08:17:27.361 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	58	8268	78	
252	SQL Batch Completed	25/07/2025 08:17:27.362 a. m.	Update tempcheques Set cuentaenuso=0 Where folio=1                   	SoftRestaurant®	avov2		sa	0	29	0	1002	8268	78	
253	RPC Completed	25/07/2025 08:17:27.420 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
254	SQL Batch Completed	25/07/2025 08:17:27.420 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	115	8268	78	
255	SQL Batch Completed	25/07/2025 08:17:27.461 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1                    AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	116	8268	78	
256	RPC Completed	25/07/2025 08:17:27.558 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	78	
257	SQL Batch Completed	25/07/2025 08:17:27.558 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	94	8268	78	
258	RPC Completed	25/07/2025 08:17:27.604 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	17	8268	78	
259	SQL Batch Completed	25/07/2025 08:17:27.604 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	101	8268	78	
260	SQL Batch Completed	25/07/2025 08:17:27.644 a. m.	select * from tempcheqdet WHERE  foliodet=1                   	SoftRestaurant®	avov2		sa	0	113	0	367	8268	78	
261	SQL Batch Completed	25/07/2025 08:17:27.697 a. m.	select * from tempcheques where folio=1                    	SoftRestaurant®	avov2		sa	0	2	0	272	8268	78	
262	RPC Completed	25/07/2025 08:17:27.803 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
263	SQL Batch Completed	25/07/2025 08:17:27.803 a. m.	SELECT decimalespdv FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	86	8268	78	
264	SQL Batch Completed	25/07/2025 08:17:27.845 a. m.	SELECT desc_importe FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	103	8268	78	
265	SQL Batch Completed	25/07/2025 08:17:27.885 a. m.	SELECT * FROM tipodescuento where idtipodescuento= '     ' and activar_maximo_descuento=1	SoftRestaurant®	avov2		sa	0	2	0	119	8268	78	
266	SQL Batch Completed	25/07/2025 08:17:27.934 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	101	8268	78	
267	SQL Batch Completed	25/07/2025 08:17:28.004 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
268	SQL Batch Completed	25/07/2025 08:17:28.057 a. m.	UPDATE tempcheques set  totalarticulos=1.000000,  subtotal=1293.100000,  total=1500.000000,  totalconpropina=1500.000000,  totalsindescuento=1293.100000,  totalimpuesto1=206.900000,  totalalimentos=0.000000,  totalbebidas=1293.100000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=1500.000000,  totalconpropinacargo=1500.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=1293.100000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=1293.100000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=0.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=206.896552,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=1500.000000 where folio=1                    	SoftRestaurant®	avov2		sa	16000	36	0	14739	8268	78	
269	SQL Batch Completed	25/07/2025 08:17:28.097 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	29	0	847	8268	78	
270	SQL Batch Completed	25/07/2025 08:17:28.135 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	137	8268	78	
271	SQL Batch Completed	25/07/2025 08:17:28.182 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	87	8268	78	
272	SQL Batch Completed	25/07/2025 08:17:28.223 a. m.	UPDATE cuentas SET total=1500.000000, subtotal =1293.100000, totalimpuesto1=206.900000,descuentoimporte=0.000000 where foliocuenta=1                    	SoftRestaurant®	avov2		sa	0	13	0	255	8268	78	
273	SQL Batch Completed	25/07/2025 08:17:28.313 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	481	8268	78	
274	RPC Completed	25/07/2025 08:17:28.355 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
275	SQL Batch Completed	25/07/2025 08:17:28.356 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_calcpropinacostarica' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	887	8268	78	
276	SQL Batch Completed	25/07/2025 08:17:28.438 a. m.	SELECT dev_calcpropinacostarica FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	109	8268	78	
277	RPC Completed	25/07/2025 08:17:28.482 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
278	SQL Batch Completed	25/07/2025 08:17:28.482 a. m.	SELECT * FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	182	8268	78	
279	RPC Completed	25/07/2025 08:17:28.543 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
280	SQL Batch Completed	25/07/2025 08:17:28.543 a. m.	Select cuentaenuso FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	136	8268	78	
281	RPC Completed	25/07/2025 08:17:28.586 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
282	SQL Batch Completed	25/07/2025 08:17:28.586 a. m.	Select impreso FROM tempcheques WHERE folio='1'	SoftRestaurant®	avov2		sa	0	2	0	111	8268	78	
283	RPC Completed	25/07/2025 08:17:28.669 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
284	SQL Batch Completed	25/07/2025 08:17:28.671 a. m.	SELECT * FROM productos WHERE usarcomedor=0 OR usardomicilio=0 OR usarrapido=0	SoftRestaurant®	avov2		sa	0	270	0	2051	8268	78	
285	SQL Batch Completed	25/07/2025 08:17:28.717 a. m.	SELECT actualizarcatalogos FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	124	8268	78	
286	RPC Completed	25/07/2025 08:17:30.886 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
287	SQL Batch Completed	25/07/2025 08:17:30.895 a. m.	select * from movtosbillar where hrafinal is null and (estatus=4 or estatus=1) and idmovto in (select idmovtobillar from tempcheqdet where foliodet=1                   )	SoftRestaurant®	avov2		sa	0	6	0	8369	8268	78	
288	RPC Completed	25/07/2025 08:17:30.942 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
289	SQL Batch Completed	25/07/2025 08:17:30.942 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	102	8268	78	
290	SQL Batch Completed	25/07/2025 08:17:31.030 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	164	8268	78	
291	SQL Batch Completed	25/07/2025 08:17:31.071 a. m.	SELECT * FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	16	0	222	8268	78	
292	RPC Completed	25/07/2025 08:17:31.118 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
293	SQL Batch Completed	25/07/2025 08:17:31.118 a. m.	Select cuentaenuso FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	109	8268	78	
294	RPC Completed	25/07/2025 08:17:31.165 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
295	SQL Batch Completed	25/07/2025 08:17:31.165 a. m.	Select impreso FROM tempcheques WHERE folio='1'	SoftRestaurant®	avov2		sa	0	2	0	113	8268	78	
296	RPC Completed	25/07/2025 08:17:31.210 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	17	8268	78	
297	SQL Batch Completed	25/07/2025 08:17:31.212 a. m.	SELECT subtotal,idcliente,impresiones,descuento,IdReservacion FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	1425	8268	78	
298	RPC Completed	25/07/2025 08:17:31.320 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	29	8268	78	
299	SQL Batch Completed	25/07/2025 08:17:31.320 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	150	8268	78	
300	SQL Batch Completed	25/07/2025 08:17:31.363 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1                    AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	126	8268	78	
301	RPC Completed	25/07/2025 08:17:31.409 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
302	SQL Batch Completed	25/07/2025 08:17:31.409 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	119	8268	78	
303	RPC Completed	25/07/2025 08:17:31.458 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
304	SQL Batch Completed	25/07/2025 08:17:31.458 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	133	8268	78	
305	SQL Batch Completed	25/07/2025 08:17:31.499 a. m.	select * from tempcheqdet WHERE  foliodet=1                   	SoftRestaurant®	avov2		sa	0	113	0	375	8268	78	
306	SQL Batch Completed	25/07/2025 08:17:31.580 a. m.	select * from tempcheques where folio=1                    	SoftRestaurant®	avov2		sa	0	2	0	386	8268	78	
307	RPC Completed	25/07/2025 08:17:31.649 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	26	8268	78	
308	SQL Batch Completed	25/07/2025 08:17:31.649 a. m.	SELECT decimalespdv FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	152	8268	78	
309	SQL Batch Completed	25/07/2025 08:17:31.690 a. m.	SELECT desc_importe FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	96	8268	78	
310	SQL Batch Completed	25/07/2025 08:17:31.730 a. m.	SELECT * FROM tipodescuento where idtipodescuento= '     ' and activar_maximo_descuento=1	SoftRestaurant®	avov2		sa	0	2	0	140	8268	78	
311	SQL Batch Completed	25/07/2025 08:17:31.811 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	110	8268	78	
312	SQL Batch Completed	25/07/2025 08:17:31.851 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	29	8268	78	
313	SQL Batch Completed	25/07/2025 08:17:31.889 a. m.	UPDATE tempcheques set  totalarticulos=1.000000,  subtotal=1293.100000,  total=1500.000000,  totalconpropina=1500.000000,  totalsindescuento=1293.100000,  totalimpuesto1=206.900000,  totalalimentos=0.000000,  totalbebidas=1293.100000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=1500.000000,  totalconpropinacargo=1500.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=1293.100000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=1293.100000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=0.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=206.896552,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=1500.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	36	0	843	8268	78	
314	SQL Batch Completed	25/07/2025 08:17:31.927 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	31	0	461	8268	78	
315	SQL Batch Completed	25/07/2025 08:17:31.964 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	129	8268	78	
316	SQL Batch Completed	25/07/2025 08:17:32.007 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	96	8268	78	
317	SQL Batch Completed	25/07/2025 08:17:32.048 a. m.	UPDATE cuentas SET total=1500.000000, subtotal =1293.100000, totalimpuesto1=206.900000,descuentoimporte=0.000000 where foliocuenta=1                    	SoftRestaurant®	avov2		sa	0	13	0	179	8268	78	
318	SQL Batch Completed	25/07/2025 08:17:32.088 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	404	8268	78	
319	RPC Completed	25/07/2025 08:17:32.132 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
320	SQL Batch Completed	25/07/2025 08:17:32.132 a. m.	SELECT idformatocomedor,idformatodomicilio,idformatorapido,idformatomovil,idformatonotadeconsumo,impresoracheques,copiasticketcomedor,copiasticketdomicilio,copiasticketrapido,copiasnotadeconsumo,copiasticketmovil FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	152	8268	78	
321	SQL Batch Completed	25/07/2025 08:17:32.175 a. m.	SELECT * FROM tempcheques WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	267	8268	78	
322	RPC Completed	25/07/2025 08:17:32.280 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
323	SQL Batch Completed	25/07/2025 08:17:32.280 a. m.	SELECT propinaincluida,porcentajepropina,decimalespdv,redondeopropinas FROM configuracion,parametros	SoftRestaurant®	avov2		sa	0	6	0	160	8268	78	
324	SQL Batch Completed	25/07/2025 08:17:32.334 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
325	SQL Batch Completed	25/07/2025 08:17:32.385 a. m.	UPDATE tempcheques SET propinaincluida=0.000000 WHERE folio=1                   	SoftRestaurant®	avov2		sa	0	37	8	6366	8268	78	
326	SQL Batch Completed	25/07/2025 08:17:32.426 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	150	8268	78	
327	SQL Batch Completed	25/07/2025 08:17:32.499 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	86	8268	78	
328	SQL Batch Completed	25/07/2025 08:17:32.544 a. m.	UPDATE cuentas SET propinaincluida=0.000000 WHERE foliocuenta=1                   	SoftRestaurant®	avov2		sa	0	13	0	178	8268	78	
329	SQL Batch Completed	25/07/2025 08:17:32.585 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	436	8268	78	
330	RPC Completed	25/07/2025 08:17:32.630 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
331	SQL Batch Completed	25/07/2025 08:17:32.630 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	108	8268	78	
332	SQL Batch Completed	25/07/2025 08:17:32.671 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1                    AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	107	8268	78	
333	RPC Completed	25/07/2025 08:17:32.749 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
334	SQL Batch Completed	25/07/2025 08:17:32.749 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	115	8268	78	
335	RPC Completed	25/07/2025 08:17:32.794 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	17	8268	78	
336	SQL Batch Completed	25/07/2025 08:17:32.794 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	91	8268	78	
337	SQL Batch Completed	25/07/2025 08:17:32.834 a. m.	select * from tempcheqdet WHERE  foliodet=1                   	SoftRestaurant®	avov2		sa	0	113	0	349	8268	78	
338	SQL Batch Completed	25/07/2025 08:17:32.895 a. m.	select * from tempcheques where folio=1                    	SoftRestaurant®	avov2		sa	0	2	0	352	8268	78	
339	RPC Completed	25/07/2025 08:17:32.987 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
340	SQL Batch Completed	25/07/2025 08:17:32.987 a. m.	SELECT decimalespdv FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	84	8268	78	
341	SQL Batch Completed	25/07/2025 08:17:33.027 a. m.	SELECT desc_importe FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	95	8268	78	
342	SQL Batch Completed	25/07/2025 08:17:33.068 a. m.	SELECT * FROM tipodescuento where idtipodescuento= '     ' and activar_maximo_descuento=1	SoftRestaurant®	avov2		sa	0	2	0	115	8268	78	
343	SQL Batch Completed	25/07/2025 08:17:33.120 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=1 and tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	212	8268	78	
344	SQL Batch Completed	25/07/2025 08:17:33.195 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	132	8268	78	
345	SQL Batch Completed	25/07/2025 08:17:33.237 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=3 and tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	132	8268	78	
346	SQL Batch Completed	25/07/2025 08:17:33.279 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=4 and tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	170	8268	78	
347	SQL Batch Completed	25/07/2025 08:17:33.323 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propina from  tempchequespagos  where tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	172	8268	78	
348	SQL Batch Completed	25/07/2025 08:17:33.374 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propinatarjeta from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1                    	SoftRestaurant®	avov2		sa	0	11	0	156	8268	78	
349	SQL Batch Completed	25/07/2025 08:17:33.415 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	108	8268	78	
350	SQL Batch Completed	25/07/2025 08:17:33.460 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	27	8268	78	
351	SQL Batch Completed	25/07/2025 08:17:33.500 a. m.	UPDATE tempcheques set  totalarticulos=1.000000,  subtotal=1293.100000,  total=1500.000000,  totalconpropina=1500.000000,  totalsindescuento=1293.100000,  totalimpuesto1=206.900000,  totalalimentos=0.000000,  totalbebidas=1293.100000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=1500.000000,  totalconpropinacargo=1500.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=1293.100000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=1293.100000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=0.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=206.896552,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=1500.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	35	0	1208	8268	78	
352	SQL Batch Completed	25/07/2025 08:17:33.538 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1                    	SoftRestaurant®	avov2		sa	0	32	0	847	8268	78	
353	SQL Batch Completed	25/07/2025 08:17:33.578 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	143	8268	78	
354	SQL Batch Completed	25/07/2025 08:17:33.621 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	136	8268	78	
355	SQL Batch Completed	25/07/2025 08:17:33.667 a. m.	UPDATE cuentas SET total=1500.000000, subtotal =1293.100000, totalimpuesto1=206.900000,descuentoimporte=0.000000 where foliocuenta=1                    	SoftRestaurant®	avov2		sa	0	13	0	150	8268	78	
356	SQL Batch Completed	25/07/2025 08:17:33.713 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	460	8268	78	
357	RPC Completed	25/07/2025 08:17:33.766 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
358	SQL Batch Completed	25/07/2025 08:17:33.766 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	28	8268	78	
359	SQL Batch Completed	25/07/2025 08:17:33.804 a. m.	SELECT * FROM folios WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	174	8268	78	
360	SQL Batch Completed	25/07/2025 08:17:33.888 a. m.	SELECT ultimofolio FROM folios WITH (TABLOCKX)  WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	151	8268	78	
361	SQL Batch Completed	25/07/2025 08:17:33.944 a. m.	UPDATE tempcheques WITH(TABLOCK) SET impreso=1,numcheque=27212,cierre='25/07/2025 08:17:34 AM',impresiones=impresiones+1,seriefolio='',cambiorepartidor=0.000000,campoadicional1='000000000100000',codigo_unico_af='',domicilioprogramado=0,autorizacionfolio='                                                  ' WHERE folio=1                   	SoftRestaurant®	avov2		sa	16000	33	0	8547	8268	78	
362	SQL Batch Completed	25/07/2025 08:17:33.984 a. m.	UPDATE folios WITH(TABLOCK) SET ultimofolio=27212 WHERE serie=''	SoftRestaurant®	avov2		sa	0	3	0	399	8268	78	
363	SQL Batch Completed	25/07/2025 08:17:34.026 a. m.	UPDATE cuentas set imprimir = 1, procesado = 1 where foliocuenta = 1                   	SoftRestaurant®	avov2		sa	0	14	0	225	8268	78	
364	SQL Batch Completed	25/07/2025 08:17:34.063 a. m.	SELECT * FROM mesasasignadas WHERE activo=1 AND folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	151	8268	78	
365	SQL Batch Completed	25/07/2025 08:17:34.108 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	461	8268	78	
366	RPC Completed	25/07/2025 08:17:34.159 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
367	SQL Batch Completed	25/07/2025 08:17:34.159 a. m.	select iva,ivadesglosado,decimalespdv,registrocontribuyente,parametros.redondeodescuentos from configuracion,parametros	SoftRestaurant®	avov2		sa	0	6	0	152	8268	78	
368	SQL Batch Completed	25/07/2025 08:17:34.204 a. m.	SELECT * FROM formatos WHERE idformato='01'	SoftRestaurant®	avov2		sa	0	3	0	189	8268	78	
369	SQL Batch Completed	25/07/2025 08:17:34.253 a. m.	SELECT CODIGO_UNICO_AF FROM TEMPCHEQUES WHERE FOLIO=1                   	SoftRestaurant®	avov2		sa	0	2	0	2582	8268	78	
370	SQL Batch Completed	25/07/2025 08:17:34.307 a. m.	UPDATE TEMPCHEQUES SET CODIGO_UNICO_AF='78LRBC8C2' WHERE FOLIO=1                   	SoftRestaurant®	avov2		sa	0	33	0	7300	8268	78	
371	SQL Batch Completed	25/07/2025 08:17:34.404 a. m.	SELECT TEMPCHEQUES.*,TEMPCHEQUES.totalalimentos as tal,TEMPCHEQUES.totalbebidas as tbeb,TEMPCHEQUES.totalotros as totros,TEMPCHEQUES.subtotalcondescuento as subcdesc, clientes.nombre as nombrecliente,clientes.direccion as DOMICILIOCLIENTE,clientes.contacto AS contactoclientes,clientes.tarjetamonedero,clientes.telefono1,clientes.telefono2,clientes.telefono3,clientes.telefono4,clientes.telefono5,clientes.email,clientes.rfc as rfccliente, clientes.idtipocliente, clientes.curp as rtn,Meseros.nombre as nombremesero,Areasrestaurant.descripcion as descripcionarea,0 as CUENTATIENEDESCUENTOPRODUCTO,clientes.tipoclientencf,ISNULL(Usuarios.nombre, '') as nombreusuariopago FROM TEMPCHEQUES LEFT JOIN meseros ON TEMPCHEQUES.idmesero=Meseros.idmesero LEFT JOIN areasrestaurant ON Areasrestaurant.idarearestaurant=TEMPCHEQUES.idarearestaurant LEFT JOIN clientes ON clientes.idcliente=TEMPCHEQUES.idcliente LEFT JOIN Usuarios ON TEMPCHEQUES.usuariopago=Usuarios.usuario WHERE folio=1                    ORDER BY TEMPCHEQUES.folio	SoftRestaurant®	avov2		sa	16000	39	0	14762	8268	78	
372	SQL Batch Completed	25/07/2025 08:17:34.473 a. m.	SELECT folio, STUFF((SELECT DISTINCT ', ' + referencia FROM TEMPCHEQUESPAGOS WHERE folio IN (SELECT folio FROM TEMPCHEQUES WHERE folio=1                    and referencia!='') FOR XML PATH('')), 1, 2, '') AS referencia  FROM TEMPCHEQUESPAGOS WHERE folio IN (SELECT folio FROM TEMPCHEQUES WHERE folio=1                   )  GROUP BY folio 	SoftRestaurant®	avov2		sa	0	11	0	8884	8268	78	
373	SQL Batch Completed	25/07/2025 08:17:34.515 a. m.	SELECT rangoautinicio,rangoautfin,serie FROM folios where serie='               '	SoftRestaurant®	avov2		sa	0	3	0	137	8268	78	
374	SQL Batch Completed	25/07/2025 08:17:34.559 a. m.	SELECT regimen FROM empresas where idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	2	0	121	8268	78	
375	SQL Batch Completed	25/07/2025 08:17:34.613 a. m.	select isnull(sum((precio-preciosinimpuestos)*cantidad),0) total from TEMPCHEQDET c  inner join productos p on c.idproducto=p.idproducto  inner join grupos g on g.idgrupo=p.idgrupo  where foliodet=1                    and g.clasificacion=1 	SoftRestaurant®	avov2		sa	16000	137	0	9359	8268	78	
376	SQL Batch Completed	25/07/2025 08:17:34.662 a. m.	select isnull(sum((precio-preciosinimpuestos)*cantidad),0) total from TEMPCHEQDET c  inner join productos p on c.idproducto=p.idproducto  inner join grupos g on g.idgrupo=p.idgrupo  where foliodet=1                    and g.clasificacion=2 	SoftRestaurant®	avov2		sa	0	137	0	8711	8268	78	
377	SQL Batch Completed	25/07/2025 08:17:34.713 a. m.	select isnull(sum((precio-preciosinimpuestos)*cantidad),0) total from TEMPCHEQDET c  inner join productos p on c.idproducto=p.idproducto  inner join grupos g on g.idgrupo=p.idgrupo  where foliodet=1                    and g.clasificacion=3 	SoftRestaurant®	avov2		sa	0	137	0	8666	8268	78	
378	SQL Batch Completed	25/07/2025 08:17:34.766 a. m.	SELECT TEMPCHEQDET.*,productos.descripcion as productodescripcion,productos.nombrecorto,productosdetalle.idunidad from TEMPCHEQDET LEFT JOIN productos ON TEMPCHEQDET.idproducto=productos.idproducto LEFT JOIN productosdetalle ON TEMPCHEQDET.idproducto=productosdetalle.idproducto WHERE foliodet=1                    ORDER BY movimiento	SoftRestaurant®	avov2		sa	0	175	0	9227	8268	78	
379	SQL Batch Completed	25/07/2025 08:17:34.821 a. m.	SELECT folio as foliocuenta,titulartarjetamonedero, numerotarjeta, saldoanteriormonedero, puntosmonederogenerados as importe, (saldoanteriormonedero+puntosmonederogenerados) as saldoactualmonedero FROM TEMPCHEQUES WHERE puntosmonederogenerados>0 AND folio=1                   	SoftRestaurant®	avov2		sa	0	2	0	1735	8268	78	
380	SQL Batch Completed	25/07/2025 08:17:34.866 a. m.	SELECT foliocuenta,titulartarjetamonedero, numerotarjeta, saldoanteriormonedero, importe, (saldoanteriormonedero-importe) as saldoactualmonedero FROM TEMPNUMEROSTARJETAS WHERE foliocuenta = 1                   	SoftRestaurant®	avov2		sa	0	0	0	107	8268	78	
381	SQL Batch Completed	25/07/2025 08:17:34.921 a. m.	Select TEMPCHEQDET.*,productosdetalle.excentoimpuestos,tmpc.descuento AS desc_gral From TEMPCHEQDET Left Outer Join productosdetalle On TEMPCHEQDET.idproducto=productosdetalle.idproducto INNER JOIN TEMPCHEQUES AS tmpc ON tmpc.folio=TEMPCHEQDET.foliodet Where foliodet=1                   	SoftRestaurant®	avov2		sa	0	170	0	7696	8268	78	
382	RPC Completed	25/07/2025 08:17:34.981 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
383	SQL Batch Completed	25/07/2025 08:17:34.981 a. m.	SELECT vecesimprimirformatoconcuenta,ultimofolioimprimirformatoconcuenta FROM parametros	SoftRestaurant®	avov2		sa	0	3	0	102	8268	78	
384	SQL Batch Completed	25/07/2025 08:17:35.052 a. m.	UPDATE parametros SET ultimofolioimprimirformatoconcuenta=1	SoftRestaurant®	avov2		sa	0	3	0	481	8268	78	
385	SQL Batch Completed	25/07/2025 08:17:35.090 a. m.	UPDATE parametros SET ultimofolioimprimirformatoconcuenta=0	SoftRestaurant®	avov2		sa	0	3	0	477	8268	78	
386	SQL Batch Completed	25/07/2025 08:17:35.129 a. m.	select COUNT(*)cantidad from formatosvarios where idformato = 15	SoftRestaurant®	avov2		sa	0	15	0	413	8268	78	
387	SQL Batch Completed	25/07/2025 08:17:35.434 a. m.	SELECT tempchequespagos.*,descripcion as nombre_formadepago FROM tempchequespagos INNER JOIN formasdepago ON tempchequespagos.idformadepago=formasdepago.idformadepago WHERE (folio=1) AND importe > 0 AND tempchequespagos.tipodecambio <> 1	SoftRestaurant®	avov2		sa	0	11	0	194	8268	81	
388	SQL Batch Completed	25/07/2025 08:17:35.477 a. m.	SELECT tempchequespagos.* FROM tempchequespagos INNER JOIN formasdepago ON tempchequespagos.idformadepago=formasdepago.idformadepago WHERE (folio=1) AND importe > 0 AND tempchequespagos.tipodecambio=1 AND formasdepago.tipo=1	SoftRestaurant®	avov2		sa	0	11	0	153	8268	81	
389	RPC Completed	25/07/2025 08:17:35.525 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	81	
390	SQL Batch Completed	25/07/2025 08:17:35.526 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_listadefault' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	813	8268	81	
391	RPC Completed	25/07/2025 08:17:35.574 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
392	SQL Batch Completed	25/07/2025 08:17:35.574 a. m.	SELECT * FROM formatos WHERE idformato='01'	SoftRestaurant®	avov2		sa	0	3	0	160	8268	78	
393	SQL Batch Completed	25/07/2025 08:17:35.620 a. m.	SELECT field_value FROM app_settings WHERE field = 'r_handsoff' AND app_id = 1	SoftRestaurant®	avov2		sa	0	6	0	441	8268	78	
394	SQL Batch Completed	25/07/2025 08:17:35.697 a. m.	SELECT * FROM formatosdetalle WHERE idformato='01' and tipo=1 ORDER BY fila,columna	SoftRestaurant®	avov2		sa	0	29	0	861	8268	78	
395	SQL Batch Completed	25/07/2025 08:17:35.745 a. m.	SELECT * FROM formatosdetalle WHERE idformato='01' and tipo=2 ORDER BY fila,columna	SoftRestaurant®	avov2		sa	0	29	0	468	8268	78	
396	SQL Batch Completed	25/07/2025 08:17:35.790 a. m.	SELECT * FROM formatosdetalle WHERE idformato='01' and tipo=3 ORDER BY fila,columna	SoftRestaurant®	avov2		sa	0	29	0	593	8268	78	
397	SQL Batch Completed	25/07/2025 08:17:35.838 a. m.	select NOMBREIMPUESTO1 FROM parametros	SoftRestaurant®	avov2		sa	0	3	0	192	8268	78	
398	SQL Batch Completed	25/07/2025 08:17:35.879 a. m.	SELECT * FROM comandosimpresion	SoftRestaurant®	avov2		sa	0	2	0	79	8268	78	
399	SQL Batch Completed	25/07/2025 08:17:35.920 a. m.	SELECT * FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	297	8268	78	
400	SQL Batch Completed	25/07/2025 08:17:35.986 a. m.	select autofactura_enabled,archivos_CFDI_enviados,configuracion_url_personalizada,configuracion_vigencia,configuracion_cierre_mensual, configuracion_cierremensual_dias from configuracion_ws	SoftRestaurant®	avov2		sa	0	3	0	122	8268	78	
401	SQL Batch Completed	25/07/2025 08:17:36.028 a. m.	select anchopapel from formatos where idformato = '01'	SoftRestaurant®	avov2		sa	0	3	0	148	8268	78	
402	SQL Batch Completed	25/07/2025 08:17:36.069 a. m.	select anchopapel from formatos where idformato = '01'	SoftRestaurant®	avov2		sa	0	3	0	152	8268	78	
403	SQL Batch Completed	25/07/2025 08:17:36.111 a. m.	SELECT * FROM formatosdetalle WHERE RTRIM(LTRIM(idformato))='0101' and tipo=2  order by idcampo	SoftRestaurant®	avov2		sa	0	29	0	421	8268	78	
404	RPC Completed	25/07/2025 08:17:36.238 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
405	SQL Batch Completed	25/07/2025 08:17:36.238 a. m.	SELECT polizanumdivision,registrocontribuyente  FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	116	8268	78	
406	SQL Batch Completed	25/07/2025 08:17:36.279 a. m.	SELECT ciudad,estado,pais,ciudadsucursal,estadosucursal,nombre,razonsocial,direccion,rfc,telefono,idempresa,curp,sucursal,codigopostal FROM empresas WHERE idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	2	0	464	8268	78	
407	RPC Completed	25/07/2025 08:17:36.415 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
408	SQL Batch Completed	25/07/2025 08:17:36.418 a. m.	SELECT folio,seriefolio,numcheque FROM tempcheques WHERE folio=1	SoftRestaurant®	avov2		sa	0	2	0	2466	8268	78	
409	RPC Completed	25/07/2025 08:17:36.462 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
410	SQL Batch Completed	25/07/2025 08:17:36.462 a. m.	select * from estaciones where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	274	8268	78	
411	RPC Completed	25/07/2025 08:17:36.550 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
412	SQL Batch Completed	25/07/2025 08:17:36.550 a. m.	SELECT folio,mesa,impreso,idmesero,seriefolio+convert(varchar,orden) as orden FROM tempcheques WHERE tipodeservicio=1  and (CAST(pagado as int)=0 OR (pagado=1 AND esalestatus=1) ) and CAST(cancelado as int)=0  order by mesa	SoftRestaurant®	avov2		sa	0	2	0	216	8268	78	
413	RPC Completed	25/07/2025 08:17:36.655 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
414	SQL Batch Completed	25/07/2025 08:17:36.655 a. m.	SELECT *  FROM mesasasignadas WHERE folio = 1                   	SoftRestaurant®	avov2		sa	0	2	0	129	8268	78	
415	SQL Batch Completed	25/07/2025 08:17:36.704 a. m.	SELECT tempcheques.*,Comisionistas.Nombre as NombreComisionista FROM tempcheques Left Join Comisionistas on  TempCheques.IDComisionista=Comisionistas.IdComisionista WHERE folio=1                   	SoftRestaurant®	avov2		sa	16000	5	0	6990	8268	78	
416	RPC Completed	25/07/2025 08:17:36.780 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	11	8268	78	
417	SQL Batch Completed	25/07/2025 08:17:36.780 a. m.	Select Distinct tempcheqdet.*, productos.descripcion, productos.nombrecorto FROM tempcheqdet LEFT JOIN productos On tempcheqdet.idproducto=productos.idproducto WHERE tempcheqdet.foliodet=1                    Order By movimiento 	SoftRestaurant®	avov2		sa	0	115	0	331	8268	78	
418	RPC Completed	25/07/2025 08:17:36.917 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
419	SQL Batch Completed	25/07/2025 08:17:36.917 a. m.	SELECT impresorafiscal FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	120	8268	78	
420	RPC Completed	25/07/2025 08:17:37.668 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
421	SQL Batch Completed	25/07/2025 08:17:37.668 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	115	8268	78	
422	SQL Batch Completed	25/07/2025 08:17:37.709 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	122	8268	78	
423	SQL Batch Completed	25/07/2025 08:17:37.750 a. m.	SELECT * FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'	SoftRestaurant®	avov2		sa	0	16	0	228	8268	78	
424	RPC Completed	25/07/2025 08:17:37.797 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
425	SQL Batch Completed	25/07/2025 08:17:37.797 a. m.	SELECT pagarsinimprimir FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	116	8268	78	
426	RPC Completed	25/07/2025 08:17:37.879 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	78	
427	SQL Batch Completed	25/07/2025 08:17:37.879 a. m.	Select cuentaenuso FROM tempcheques WHERE folio=1	SoftRestaurant®	avov2		sa	0	2	0	153	8268	78	
428	RPC Completed	25/07/2025 08:17:37.922 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
429	SQL Batch Completed	25/07/2025 08:17:37.922 a. m.	Select impreso FROM tempcheques WHERE folio='1'	SoftRestaurant®	avov2		sa	0	2	0	101	8268	78	
430	RPC Completed	25/07/2025 08:17:37.967 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
431	SQL Batch Completed	25/07/2025 08:17:37.967 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	104	8268	78	
432	SQL Batch Completed	25/07/2025 08:17:38.007 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	132	8268	78	
433	SQL Batch Completed	25/07/2025 08:17:38.048 a. m.	SELECT idturno FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'and idmesero=''	SoftRestaurant®	avov2		sa	0	16	0	335	8268	78	
434	RPC Completed	25/07/2025 08:17:38.131 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	30	8268	78	
435	SQL Batch Completed	25/07/2025 08:17:38.132 a. m.	SELECT RequestInvoiceSequence FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	149	8268	78	
436	SQL Batch Completed	25/07/2025 08:17:38.176 a. m.	SELECT solicitarfacturacion,idclientepublico FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	97	8268	78	
437	RPC Completed	25/07/2025 08:17:38.221 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
438	SQL Batch Completed	25/07/2025 08:17:38.222 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_impuestoimporte3' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	865	8268	78	
439	SQL Batch Completed	25/07/2025 08:17:38.268 a. m.	SELECT dev_impuestoimporte3 FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	160	8268	78	
440	RPC Completed	25/07/2025 08:17:38.312 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	26	8268	78	
441	SQL Batch Completed	25/07/2025 08:17:38.312 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	93	8268	78	
442	SQL Batch Completed	25/07/2025 08:17:38.383 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1 AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	145	8268	78	
443	RPC Completed	25/07/2025 08:17:38.427 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
444	SQL Batch Completed	25/07/2025 08:17:38.427 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	104	8268	78	
445	RPC Completed	25/07/2025 08:17:38.470 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
446	SQL Batch Completed	25/07/2025 08:17:38.470 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	124	8268	78	
447	SQL Batch Completed	25/07/2025 08:17:38.511 a. m.	select * from tempcheqdet WHERE  foliodet=1	SoftRestaurant®	avov2		sa	0	113	0	241	8268	78	
448	SQL Batch Completed	25/07/2025 08:17:38.561 a. m.	select * from tempcheques where folio=1 	SoftRestaurant®	avov2		sa	0	2	0	270	8268	78	
449	RPC Completed	25/07/2025 08:17:38.662 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
450	SQL Batch Completed	25/07/2025 08:17:38.662 a. m.	SELECT decimalespdv FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	102	8268	78	
451	SQL Batch Completed	25/07/2025 08:17:38.703 a. m.	SELECT desc_importe FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	125	8268	78	
452	SQL Batch Completed	25/07/2025 08:17:38.742 a. m.	SELECT * FROM tipodescuento where idtipodescuento= '     ' and activar_maximo_descuento=1	SoftRestaurant®	avov2		sa	0	2	0	114	8268	78	
453	SQL Batch Completed	25/07/2025 08:17:38.792 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=1 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	193	8268	78	
454	SQL Batch Completed	25/07/2025 08:17:38.832 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	147	8268	78	
455	SQL Batch Completed	25/07/2025 08:17:38.909 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=3 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	147	8268	78	
456	SQL Batch Completed	25/07/2025 08:17:38.950 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=4 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	190	8268	78	
457	SQL Batch Completed	25/07/2025 08:17:38.990 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propina from  tempchequespagos  where tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	145	8268	78	
458	SQL Batch Completed	25/07/2025 08:17:39.033 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propinatarjeta from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	141	8268	78	
459	SQL Batch Completed	25/07/2025 08:17:39.074 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	100	8268	78	
460	SQL Batch Completed	25/07/2025 08:17:39.115 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	28	8268	78	
461	SQL Batch Completed	25/07/2025 08:17:39.154 a. m.	UPDATE tempcheques set  totalarticulos=1.000000,  subtotal=1293.100000,  total=1500.000000,  totalconpropina=1500.000000,  totalsindescuento=1293.100000,  totalimpuesto1=206.900000,  totalalimentos=0.000000,  totalbebidas=1293.100000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=1500.000000,  totalconpropinacargo=1500.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=1293.100000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=1293.100000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=0.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=206.896552,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=1500.000000 where folio=1 	SoftRestaurant®	avov2		sa	0	36	0	1831	8268	78	
462	SQL Batch Completed	25/07/2025 08:17:39.193 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1 	SoftRestaurant®	avov2		sa	0	32	0	1083	8268	78	
463	SQL Batch Completed	25/07/2025 08:17:39.231 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	133	8268	78	
464	SQL Batch Completed	25/07/2025 08:17:39.271 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	96	8268	78	
465	SQL Batch Completed	25/07/2025 08:17:39.312 a. m.	UPDATE cuentas SET total=1500.000000, subtotal =1293.100000, totalimpuesto1=206.900000,descuentoimporte=0.000000 where foliocuenta=1 	SoftRestaurant®	avov2		sa	0	13	0	237	8268	78	
466	SQL Batch Completed	25/07/2025 08:17:39.351 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	403	8268	78	
467	RPC Completed	25/07/2025 08:17:39.397 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	18	8268	78	
468	SQL Batch Completed	25/07/2025 08:17:39.397 a. m.	SELECT usarsalvaguarda,salvaguardalimite,salvaguardamontopredet,salvaguardamomentovalidar,salvaguardaobligar FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	93	8268	78	
469	RPC Completed	25/07/2025 08:17:39.441 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
470	SQL Batch Completed	25/07/2025 08:17:39.441 a. m.	select * from tempnumerostarjetas where foliocuenta='1' AND sistema=1	SoftRestaurant®	avov2		sa	0	0	0	104	8268	78	
471	SQL Batch Completed	25/07/2025 08:17:39.490 a. m.	SELECT * FROM tempcheqdet WHERE foliodet=1.000000	SoftRestaurant®	avov2		sa	0	116	0	2862	8268	78	
472	SQL Batch Completed	25/07/2025 08:17:39.548 a. m.	SELECT * FROM tempcheques WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	2	0	5097	8268	78	
473	RPC Completed	25/07/2025 08:17:39.668 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	28	8268	78	
474	SQL Batch Completed	25/07/2025 08:17:39.668 a. m.	select * from configuracion	SoftRestaurant®	avov2		sa	0	3	0	333	8268	78	
475	RPC Completed	25/07/2025 08:17:39.913 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
476	SQL Batch Completed	25/07/2025 08:17:39.913 a. m.	select impresorafiscal,paisimpresorafiscal from estaciones where idestacion ='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	153	8268	78	
477	RPC Completed	25/07/2025 08:17:39.965 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
478	SQL Batch Completed	25/07/2025 08:17:39.965 a. m.	SELECT * FROM sysobjects AS so WHERE so.name='app_settings'	SoftRestaurant®	avov2		sa	0	4	0	511	8268	78	
479	SQL Batch Completed	25/07/2025 08:17:40.009 a. m.	DECLARE  @columns NVARCHAR(MAX) = '', @sql     NVARCHAR(MAX) = '';   SELECT      @columns += QUOTENAME(field) + ','  FROM     app_settings WHERE app_id=2 ORDER BY      field;  SET @columns = LEFT(@columns, LEN(@columns) - 1);  SET @sql ='  SELECT * FROM (  SELECT field,field_value FROM app_settings WHERE app_id=2 ) AS result  PIVOT(     MAX (field_value)  FOR field IN ('+ @columns +') ) AS pivot_table;';  EXECUTE sp_executesql @sql;	SoftRestaurant®	avov2		sa	0	12	0	2116	8268	78	
480	RPC Completed	25/07/2025 08:17:40.060 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	80	8268	78	
481	SQL Batch Completed	25/07/2025 08:17:40.060 a. m.	select permventaneg from parametros3	SoftRestaurant®	avov2		sa	0	3	0	91	8268	78	
482	RPC Completed	25/07/2025 08:17:40.104 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	13	8268	78	
483	SQL Batch Completed	25/07/2025 08:17:40.104 a. m.	select Dev_Tokencash, TKC_Usar, TKC_Authorization,permventaneg from parametros3	SoftRestaurant®	avov2		sa	0	3	0	103	8268	78	
484	RPC Completed	25/07/2025 08:17:40.183 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	14	8268	78	
485	SQL Batch Completed	25/07/2025 08:17:40.184 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_cga' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	817	8268	78	
486	SQL Batch Completed	25/07/2025 08:17:40.230 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='contemplarpropina' AND so.name='clientes'	SoftRestaurant®	avov2		sa	0	9	0	630	8268	78	
487	RPC Completed	25/07/2025 08:17:40.284 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
488	SQL Batch Completed	25/07/2025 08:17:40.284 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_elsalvador' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	289	8268	78	
489	RPC Completed	25/07/2025 08:17:40.409 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
490	SQL Batch Completed	25/07/2025 08:17:40.409 a. m.	SELECT * FROM formasdepago_app_area WHERE FKidarearestaurant='01' AND FKapp_id=1	SoftRestaurant®	avov2		sa	0	2	0	161	8268	78	
491	SQL Batch Completed	25/07/2025 08:17:40.494 a. m.	SELECT * FROM app_settings WHERE app_id=1 AND field='dev_cashdro_sr' and field_value='TRUE'	SoftRestaurant®	avov2		sa	0	6	0	338	8268	78	
492	RPC Completed	25/07/2025 08:17:40.701 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
493	SQL Batch Completed	25/07/2025 08:17:40.701 a. m.	SELECT solicitadenominacionpagarcta FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	109	8268	78	
494	RPC Completed	25/07/2025 08:17:42.804 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	20	8268	78	
495	SQL Batch Completed	25/07/2025 08:17:42.807 a. m.	SELECT impreso FROM tempcheques WHERE folio=1                    AND CAST(impreso as int)=1	SoftRestaurant®	avov2		sa	0	2	0	2748	8268	78	
496	RPC Completed	25/07/2025 08:17:42.852 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
497	SQL Batch Completed	25/07/2025 08:17:42.852 a. m.	SELECT * FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	245	8268	78	
498	RPC Completed	25/07/2025 08:17:42.926 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
499	SQL Batch Completed	25/07/2025 08:17:42.926 a. m.	SELECT tarjetacredito, usacajondedinero, cajontiempo, posnoterminal FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	129	8268	78	
500	SQL Batch Completed	25/07/2025 08:17:42.968 a. m.	SELECT limitedecredito,limitecreditodiario FROM clientes WHERE idcliente=''	SoftRestaurant®	avov2		sa	0	2	0	107	8268	78	
501	SQL Batch Completed	25/07/2025 08:17:43.054 a. m.	SELECT c.cambiovales,c.pagoenlineatarjeta,p.impuesto1,p.impuesto2,p.impuesto3 FROM configuracion as c,parametros as p	SoftRestaurant®	avov2		sa	0	6	0	126	8268	78	
502	SQL Batch Completed	25/07/2025 08:17:43.094 a. m.	SELECT impresorafiscal,fiscalport,paridadxsegfiscal, paisimpresorafiscal FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	124	8268	78	
503	RPC Completed	25/07/2025 08:17:43.157 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
504	SQL Batch Completed	25/07/2025 08:17:43.158 a. m.	SELECT * FROM app_settings WHERE app_id=1 AND field='dev_cashdro_sr' and field_value='TRUE'	SoftRestaurant®	avov2		sa	0	6	0	561	8268	78	
505	RPC Completed	25/07/2025 08:17:43.306 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
506	SQL Batch Completed	25/07/2025 08:17:43.306 a. m.	select Dev_Tokencash, TKC_Usar from parametros3	SoftRestaurant®	avov2		sa	0	3	0	98	8268	78	
507	RPC Completed	25/07/2025 08:17:43.350 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
508	SQL Batch Completed	25/07/2025 08:17:43.350 a. m.	SELECT tipomanejoturno FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	91	8268	78	
509	SQL Batch Completed	25/07/2025 08:17:43.390 a. m.	SELECT cajacomandero,usarturnoestacion FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	136	8268	78	
510	SQL Batch Completed	25/07/2025 08:17:43.430 a. m.	SELECT idturno FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-1601QUU' AND idempresa='0000000001'and idmesero=''	SoftRestaurant®	avov2		sa	0	16	0	156	8268	78	
511	RPC Completed	25/07/2025 08:17:43.478 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
512	SQL Batch Completed	25/07/2025 08:17:43.480 a. m.	SELECT MAX(apertura) AS max_apertura FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	25	0	2264	8268	78	
513	SQL Batch Completed	25/07/2025 08:17:43.557 a. m.	SELECT * FROM turnos WHERE cierre is null AND apertura is not null AND idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	16	0	239	8268	78	
514	SQL Batch Completed	25/07/2025 08:17:43.600 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	28	8268	78	
515	SQL Batch Completed	25/07/2025 08:17:43.643 a. m.	INSERT INTO tempchequespagos (folio,idformadepago,importe,propina,tipodecambio,referencia,importe_cashdro) VALUES (1,'DEB',1500.000000,0.000000,1.000000,'',0.000000)	SoftRestaurant®	avov2		sa	0	15	0	3559	8268	78	
516	SQL Batch Completed	25/07/2025 08:17:43.681 a. m.	SELECT * FROM formasdepago	SoftRestaurant®	avov2		sa	0	36	0	500	8268	78	
517	SQL Batch Completed	25/07/2025 08:17:43.734 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='08   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	161	8268	78	
518	SQL Batch Completed	25/07/2025 08:17:43.777 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='08   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	136	8268	78	
519	SQL Batch Completed	25/07/2025 08:17:43.820 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='09   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	142	8268	78	
520	SQL Batch Completed	25/07/2025 08:17:43.868 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='09   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	151	8268	78	
521	SQL Batch Completed	25/07/2025 08:17:43.911 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='10   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	126	8268	78	
522	SQL Batch Completed	25/07/2025 08:17:43.952 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='10   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	126	8268	78	
523	SQL Batch Completed	25/07/2025 08:17:43.993 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='11   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	120	8268	78	
524	SQL Batch Completed	25/07/2025 08:17:44.034 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='11   ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	121	8268	78	
525	SQL Batch Completed	25/07/2025 08:17:44.077 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='ACASH' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	125	8268	78	
526	SQL Batch Completed	25/07/2025 08:17:44.120 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='ACASH' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	210	8268	78	
527	SQL Batch Completed	25/07/2025 08:17:44.162 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='AEF  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	131	8268	78	
528	SQL Batch Completed	25/07/2025 08:17:44.204 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='AEF  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	149	8268	78	
529	SQL Batch Completed	25/07/2025 08:17:44.247 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='CRE  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	137	8268	78	
530	SQL Batch Completed	25/07/2025 08:17:44.290 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='CRE  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	141	8268	78	
531	SQL Batch Completed	25/07/2025 08:17:44.332 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='DEB  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	207	8268	78	
532	SQL Batch Completed	25/07/2025 08:17:44.374 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='DEB  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	118	8268	78	
533	SQL Batch Completed	25/07/2025 08:17:44.418 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='MPY  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	202	8268	78	
534	SQL Batch Completed	25/07/2025 08:17:44.461 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='MPY  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	164	8268	78	
535	SQL Batch Completed	25/07/2025 08:17:44.503 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='MRW  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	142	8268	78	
536	SQL Batch Completed	25/07/2025 08:17:44.545 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='MRW  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	195	8268	78	
537	SQL Batch Completed	25/07/2025 08:17:44.587 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='SRPC ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	149	8268	78	
538	SQL Batch Completed	25/07/2025 08:17:44.630 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='SRPC ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	169	8268	78	
539	SQL Batch Completed	25/07/2025 08:17:44.673 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='SRPD ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	124	8268	78	
540	SQL Batch Completed	25/07/2025 08:17:44.717 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='SRPD ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	136	8268	78	
541	SQL Batch Completed	25/07/2025 08:17:44.759 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='TPY  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	160	8268	78	
542	SQL Batch Completed	25/07/2025 08:17:44.802 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='TPY  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	140	8268	78	
543	SQL Batch Completed	25/07/2025 08:17:44.844 a. m.	SELECT * FROM tempchequespagos WHERE sistema_envio=2 and idformadepago='TRW  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	125	8268	78	
544	SQL Batch Completed	25/07/2025 08:17:44.888 a. m.	SELECT * FROM tempchequespagos WHERE idformadepago='TRW  ' and folio=1	SoftRestaurant®	avov2		sa	0	11	0	126	8268	78	
545	SQL Batch Completed	25/07/2025 08:17:44.929 a. m.	SELECT * FROM tempchequespagos WHERE  folio=1	SoftRestaurant®	avov2		sa	0	11	0	147	8268	78	
546	SQL Batch Completed	25/07/2025 08:17:44.971 a. m.	SELECT SUM(importe*tipodecambio) as importe,SUM(propina*tipodecambio) as propina FROM tempchequespagos WHERE folio=1	SoftRestaurant®	avov2		sa	0	11	0	138	8268	78	
547	SQL Batch Completed	25/07/2025 08:17:45.013 a. m.	SELECT salerestaurantid FROM tempcheques WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	2	0	1518	8268	78	
548	SQL Batch Completed	25/07/2025 08:17:45.064 a. m.	UPDATE tempcheques SET cierre='25/07/2025 08:17:34 AM',pagado=1,impreso=1,cambio=0.000000,idturno=894.000000,numerotarjeta='',puntosmonederogenerados=0.000000,saldoanteriormonedero=0.000000,titulartarjetamonedero='',idcliente='',usuariopago='AVOQADO',numerocuenta='                                                                                                    '  WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	32	0	8880	8268	78	
549	SQL Batch Completed	25/07/2025 08:17:45.101 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	137	8268	78	
550	SQL Batch Completed	25/07/2025 08:17:45.142 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	96	8268	78	
551	SQL Batch Completed	25/07/2025 08:17:45.190 a. m.	DELETE from detallescuentas WHERE clavemesa = (SELECT mesa from tempcheques where folio = 1.000000)	SoftRestaurant®	avov2		sa	0	58	0	5822	8268	78	
552	SQL Batch Completed	25/07/2025 08:17:45.229 a. m.	DELETE from cuentas WHERE foliocuenta = 1.000000	SoftRestaurant®	avov2		sa	0	14	0	185	8268	78	
553	SQL Batch Completed	25/07/2025 08:17:45.268 a. m.	SELECT * FROM mesasasignadas WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	2	0	86	8268	78	
554	SQL Batch Completed	25/07/2025 08:17:45.312 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='dev_cga' AND so.name='parametros3'	SoftRestaurant®	avov2		sa	0	15	0	820	8268	78	
555	SQL Batch Completed	25/07/2025 08:17:45.362 a. m.	SELECT dev_cga FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	100	8268	78	
556	SQL Batch Completed	25/07/2025 08:17:45.403 a. m.	SELECT * FROM syscolumns AS sc INNER JOIN sysobjects AS so ON sc.id=so.id AND sc.name='propina' AND so.name='cuentasporcobrar'	SoftRestaurant®	avov2		sa	0	9	0	494	8268	78	
557	SQL Batch Completed	25/07/2025 08:17:45.447 a. m.	SELECT tipocalculocomision FROM parametros	SoftRestaurant®	avov2		sa	0	3	0	81	8268	78	
558	SQL Batch Completed	25/07/2025 08:17:45.492 a. m.	SELECT A.TOTAL, A.subtotal, A.nopersonas,A.idComisionista,C.descripcion,B.pagopax, b.TipoComision,B.ComisionImporte,B.ComisionPorcentaje FROM tempcheques AS A INNER JOIN  COmisionistas AS B ON A.idComisionista= B.idComisionista INNER JOIN TipoComisionistas AS C ON B.IdTipoComisionista=C.IdTipoComisionista  WHERE A.folio=1	SoftRestaurant®	avov2		sa	0	5	0	4416	8268	78	
559	SQL Batch Completed	25/07/2025 08:17:45.537 a. m.	SELECT * FROM tempcheques WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	2	0	256	8268	78	
560	SQL Batch Completed	25/07/2025 08:17:45.597 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	420	8268	78	
561	SQL Batch Completed	25/07/2025 08:17:45.635 a. m.	set implicit_transactions off 	SoftRestaurant®	avov2		sa	0	0	0	27	8268	78	
562	SQL Batch Completed	25/07/2025 08:17:45.672 a. m.	select * from estaciones where idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	231	8268	78	
563	SQL Batch Completed	25/07/2025 08:17:45.742 a. m.	SELECT dev_intelisis FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	114	8268	78	
564	RPC Completed	25/07/2025 08:17:45.789 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	86	8268	78	
565	SQL Batch Completed	25/07/2025 08:17:45.789 a. m.	SELECT VentasOnline FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	112	8268	78	
566	SQL Batch Completed	25/07/2025 08:17:45.829 a. m.	SELECT sistema_envio FROM tempcheques WHERE folio=1 AND tipodeservicio=2	SoftRestaurant®	avov2		sa	0	2	0	123	8268	78	
567	RPC Completed	25/07/2025 08:17:45.875 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	22	8268	78	
568	SQL Batch Completed	25/07/2025 08:17:45.876 a. m.	select desc_importe from parametros3 	SoftRestaurant®	avov2		sa	0	3	0	127	8268	78	
569	RPC Completed	25/07/2025 08:17:45.956 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	24	8268	78	
570	SQL Batch Completed	25/07/2025 08:17:45.956 a. m.	SELECT tipoIEPS FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	135	8268	78	
571	SQL Batch Completed	25/07/2025 08:17:45.998 a. m.	select * from tempcheqdet WHERE  foliodet=1	SoftRestaurant®	avov2		sa	0	113	0	367	8268	78	
572	SQL Batch Completed	25/07/2025 08:17:46.047 a. m.	select * from tempcheques where folio=1 	SoftRestaurant®	avov2		sa	16000	2	0	270	8268	78	
573	RPC Completed	25/07/2025 08:17:46.133 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	16	8268	78	
574	SQL Batch Completed	25/07/2025 08:17:46.133 a. m.	SELECT decimalespdv FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	83	8268	78	
575	SQL Batch Completed	25/07/2025 08:17:46.277 a. m.	SELECT desc_importe FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	111	8268	78	
576	SQL Batch Completed	25/07/2025 08:17:46.319 a. m.	SELECT * FROM tipodescuento where idtipodescuento= '     ' and activar_maximo_descuento=1	SoftRestaurant®	avov2		sa	0	2	0	112	8268	78	
577	SQL Batch Completed	25/07/2025 08:17:46.369 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=1 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	13	0	284	8268	78	
578	SQL Batch Completed	25/07/2025 08:17:46.410 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	13	0	170	8268	78	
579	SQL Batch Completed	25/07/2025 08:17:46.451 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=3 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	13	0	116	8268	78	
580	SQL Batch Completed	25/07/2025 08:17:46.492 a. m.	select SUM((importe+propina)*tempchequespagos.tipodecambio) as importe from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=4 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	13	0	181	8268	78	
581	SQL Batch Completed	25/07/2025 08:17:46.532 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propina from  tempchequespagos  where tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	11	0	149	8268	78	
582	SQL Batch Completed	25/07/2025 08:17:46.572 a. m.	select SUM(propina*tempchequespagos.tipodecambio) as propinatarjeta from  tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago  where formasdepago.tipo=2 and tempchequespagos.folio=1 	SoftRestaurant®	avov2		sa	0	13	0	218	8268	78	
583	SQL Batch Completed	25/07/2025 08:17:46.613 a. m.	SELECT CAST(FE_COL AS INT) FE_COL FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	85	8268	78	
584	SQL Batch Completed	25/07/2025 08:17:46.655 a. m.	set implicit_transactions on 	SoftRestaurant®	avov2		sa	0	0	0	23	8268	78	
585	SQL Batch Completed	25/07/2025 08:17:46.708 a. m.	UPDATE tempcheques set  totalarticulos=1.000000,  subtotal=1293.100000,  total=1500.000000,  totalconpropina=1500.000000,  totalsindescuento=1293.100000,  totalimpuesto1=206.900000,  totalalimentos=0.000000,  totalbebidas=1293.100000,  totalotros=0.000000,  totaldescuentos=0.000000,  totaldescuentoalimentos=0.000000,  totaldescuentobebidas=0.000000,  totaldescuentootros=0.000000,  totalcortesias=0.000000,  totalcortesiaalimentos=0.000000,  totalcortesiabebidas=0.000000,  totalcortesiaotros=0.000000,  totaldescuentoycortesia=0.000000,  totalconcargo=1500.000000,  totalconpropinacargo=1500.000000,  totalalimentossindescuentos=0.000000,  totalbebidassindescuentos=1293.100000,  totalotrossindescuentos=0.000000,  subtotalcondescuento=1293.100000,  descuento=0.000000,  efectivo=0.000000,  tarjeta=1500.000000,  vales=0.000000,  otros=0.000000,  propina=0.000000,  propinatarjeta=0.000000,  totalimpuestod1=206.896552,  totalimpuestod2=0.000000,  totalimpuestod3=0.000000,totalcondonativo=0.000000,totalconpropinacargodonativo=0.000000,totalsindescuentoimp=1500.000000 where folio=1 	SoftRestaurant®	avov2		sa	15000	37	0	15185	8268	78	
586	SQL Batch Completed	25/07/2025 08:17:46.747 a. m.	update tempcheques set descuentoimporte=0.000000 where folio=1 	SoftRestaurant®	avov2		sa	0	30	0	798	8268	78	
587	SQL Batch Completed	25/07/2025 08:17:46.786 a. m.	select count(*) as registro from sysobjects where id=object_id('dbo.mesasasignadas')	SoftRestaurant®	avov2		sa	0	2	0	153	8268	78	
588	SQL Batch Completed	25/07/2025 08:17:46.827 a. m.	select count(*)as registro from registro_dispositivos	SoftRestaurant®	avov2		sa	0	3	0	71	8268	78	
589	SQL Batch Completed	25/07/2025 08:17:46.869 a. m.	UPDATE cuentas SET total=1500.000000, subtotal =1293.100000, totalimpuesto1=206.900000,descuentoimporte=0.000000 where foliocuenta=1 	SoftRestaurant®	avov2		sa	0	13	0	123	8268	78	
590	SQL Batch Completed	25/07/2025 08:17:46.908 a. m.	IF @@TRANCOUNT > 0 COMMIT TRAN	SoftRestaurant®	avov2		sa	0	0	0	486	8268	78	
591	RPC Completed	25/07/2025 08:17:46.950 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	30	8268	78	
592	SQL Batch Completed	25/07/2025 08:17:46.953 a. m.	SELECT efectivo, cambio, total,  efectivo + tarjeta + vales + otros - propina - cargo as total2 FROM tempcheques WHERE folio=1.000000	SoftRestaurant®	avov2		sa	0	2	0	2815	8268	78	
593	RPC Completed	25/07/2025 08:17:46.997 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	19	8268	78	
594	SQL Batch Completed	25/07/2025 08:17:46.997 a. m.	SELECT RequestInvoiceSequence FROM parametros3	SoftRestaurant®	avov2		sa	0	3	0	89	8268	78	
595	SQL Batch Completed	25/07/2025 08:17:47.037 a. m.	SELECT solicitarfacturacion,idclientepublico FROM configuracion	SoftRestaurant®	avov2		sa	0	3	0	104	8268	78	
596	RPC Completed	25/07/2025 08:17:47.081 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
597	SQL Batch Completed	25/07/2025 08:17:47.081 a. m.	SELECT usarsalvaguarda,salvaguardalimite,salvaguardamontopredet,salvaguardamomentovalidar,salvaguardaobligar FROM parametros2	SoftRestaurant®	avov2		sa	0	3	0	94	8268	78	
598	RPC Completed	25/07/2025 08:17:47.128 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	15	8268	78	
599	SQL Batch Completed	25/07/2025 08:17:47.128 a. m.	select formasdepago.tipo,count(*) as total from tempchequespagos inner join formasdepago on tempchequespagos.idformadepago=formasdepago.idformadepago where  tempchequespagos.folio=1  group by tipo having tipo=1 or tipo=2	SoftRestaurant®	avov2		sa	0	13	0	238	8268	78	
600	RPC Completed	25/07/2025 08:17:47.214 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	17	8268	78	
601	SQL Batch Completed	25/07/2025 08:17:47.216 a. m.	SELECT workspaceid FROM tempcheques WHERE folio=1	SoftRestaurant®	avov2		sa	0	2	0	1633	8268	78	
602	RPC Completed	25/07/2025 08:17:47.300 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	25	8268	78	
603	SQL Batch Completed	25/07/2025 08:17:47.300 a. m.	SELECT folio,mesa,impreso,idmesero,seriefolio+convert(varchar,orden) as orden FROM tempcheques WHERE tipodeservicio=1  and (CAST(pagado as int)=0 OR (pagado=1 AND esalestatus=1) ) and CAST(cancelado as int)=0  order by mesa	SoftRestaurant®	avov2		sa	0	2	0	196	8268	78	
604	RPC Completed	25/07/2025 08:17:47.383 a. m.	exec sp_reset_connection	SoftRestaurant®	avov2		sa	0	0	0	21	8268	78	
605	SQL Batch Completed	25/07/2025 08:17:47.385 a. m.	SELECT * FROM productos WHERE usarcomedor=0 OR usardomicilio=0 OR usarrapido=0	SoftRestaurant®	avov2		sa	0	270	0	2048	8268	78	
606	SQL Batch Completed	25/07/2025 08:17:47.465 a. m.	SELECT actualizarcatalogos FROM estaciones WHERE idestacion='DESKTOP-7'	SoftRestaurant®	avov2		sa	0	2	0	120	8268	78	
607	Trace Stop													
