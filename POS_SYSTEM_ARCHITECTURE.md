# Arquitectura Técnica del Sistema POS SoftRestaurant v11

## Información Crítica del Sistema

### Versión SQL Server
**CRÍTICO:** Este sistema POS ejecuta **Microsoft SQL Server 2014 Express Edition (32-bit)** - Versión 12.0.4100.1 Intel X86. Todas las operaciones de base de datos, triggers y procedimientos almacenados deben ser compatibles con la sintaxis y características de SQL Server 2014.

### Esquema de Base de Datos Completo
La base de datos SoftRestaurant v11 contiene **366 tablas** con una arquitectura multi-tenant sofisticada:
- **366 tablas totales** incluyendo lógica de negocio central, configuración, y tablas de integración
- **189 relaciones de foreign key** asegurando integridad referencial
- **Soporte multi-tenant** a través de columnas `WorkspaceId` (uniqueidentifier)
- **Tablas de integración Avoqado** ya instaladas para sincronización en tiempo real

## Filosofía Central: El Ciclo de Vida Transaccional

El POS opera bajo un principio fundamental: un ciclo de vida transaccional basado en tablas temporales para operaciones activas y tablas permanentes para el histórico. La entidad principal, una orden o "cheque", no existe en un único estado, sino que transita por fases bien definidas, dejando una traza clara en la base de datos.

### Tablas Clave en este Ciclo

- **`tempcheques`**: Contiene las órdenes activas del turno actual. Tabla de alta transaccionalidad con **194 columnas** incluyendo totales, pagos, información del cliente, e integración Avoqado
- **`cheques`**: Es el archivo histórico. Contiene una copia exacta de las órdenes una vez cerradas (pagadas o canceladas) y el turno finaliza
- **`turnos`**: Gestiona el contexto temporal de las operaciones. Una orden siempre pertenece a un turno
- **`tempcheqdet`**: Items de orden (productos, cantidades, precios, modificaciones)
- **`tempchequespagos`**: Registros de pago para órdenes activas

### Campos Críticos en Tabla tempcheques (194 columnas totales):
- **Clave Primaria**: `folio` (bigint) - Identificador único de orden
- **Campos de Estado**: `pagado` (bit), `cancelado` (bit), `impreso` (bit) - Compuertas del ciclo de vida
- **Campos de Negocio**: `total` (money), `subtotal` (money), `idturno` (bigint), `mesa` (varchar)
- **Multi-tenant**: `WorkspaceId` (uniqueidentifier) - Para soporte multi-ubicación
- **Integración Avoqado**: `AvoqadoLastModifiedAt` (datetime2) - Timestamp de seguimiento de cambios

## Las 4 Fases del Ciclo de Vida de una Orden

### Fase 1: Orden Abierta y en Modificación 📝

**Tabla Principal**: `tempcheques` y `tempcheqdet` (detalle de items).

**Proceso**: Cuando un mesero abre una nueva mesa o cuenta, se crea un registro en `tempcheques` con `pagado=0`, `cancelado=0` e `impreso=0`. Cada vez que se añade, modifica o elimina un producto, se realizan operaciones INSERT, UPDATE o DELETE en la tabla `tempcheqdet`.

**Lógica Clave**: Durante esta fase, la orden es "volátil". Los totales (`subtotal`, `totalimpuesto1`, `total`) en `tempcheques` son recalculados y actualizados constantemente por la aplicación del POS después de cada modificación de sus items.

### Fase 2: Consolidación y Presentación (Imprimir Cuenta) 🖨️

**Tabla Principal**: `tempcheques`.

**Disparador**: El usuario presiona "Imprimir Cuenta".

**Proceso**: Este no es un simple acto de impresión. Es un paso de consolidación de negocio. Las trazas del profiler muestran que antes de imprimir, el sistema:

1. Recalcula una vez más todos los totales de la orden y los actualiza en `tempcheques` y `cuentas` para asegurar la consistencia.
2. Ejecuta la acción más importante: dentro de una transacción, bloquea la tabla `folios` para obtener un número de cheque secuencial único (`numcheque`).
3. Actualiza la fila en `tempcheques` estableciendo la bandera `impreso=1`.

**Lógica Clave**: La bandera `impreso=1` actúa como un "gatekeeper" o guardián. Una orden no puede ser pagada si este campo no es 1. Es el sello que indica que la cuenta ha sido presentada al cliente y está lista para ser saldada.

### Fase 3: Liquidación (Pagar Cuenta) 💳

**Tablas Principales**: `tempchequespagos`, `tempcheques`.

**Disparador**: El usuario selecciona un método de pago y liquida la cuenta.

**Proceso**:

1. El sistema verifica que `impreso` sea 1. Si no, el pago es rechazado.
2. Se inserta un nuevo registro en la tabla `tempchequespagos`. Este registro es la evidencia del pago y contiene el folio de la orden, el `idformadepago` (ej. 'CRE' para crédito), el importe y la propina. Se pueden insertar múltiples registros si la cuenta se divide.
3. Finalmente, se actualiza el registro principal en `tempcheques`, estableciendo la bandera `pagado=1` y registrando la fecha/hora de cierre y el `usuariopago`.

**Lógica Clave**: La inserción en `tempchequespagos` y la actualización de `pagado=1` en `tempcheques` son las dos acciones que finalizan la vida activa de una orden.

### Fase 4: Archivo y Purga (Cierre de Turno) 🗄️

**Tablas Principales**: Todas (temp* y sus contrapartes permanentes).

**Disparador**: El gerente o cajero ejecuta la función "Cerrar Turno".

**Proceso**: El sistema realiza una operación de archivo masivo dentro de una transacción:

1. **Copia de Datos**: Mueve toda la información de las órdenes (`tempcheques`), sus detalles (`tempcheqdet`), sus pagos (`tempchequespagos`), etc., a las tablas de histórico (`cheques`, `cheqdet`, `chequespagos`).
2. **Cierre del Turno**: Actualiza la tabla `turnos`, estableciendo una fecha y hora en la columna `cierre` para el turno activo.
3. **Purga de Temporales**: Una vez que los datos están a salvo en el histórico y el turno está oficialmente cerrado, el sistema ejecuta DELETE sobre las tablas temp* para limpiar todo lo relacionado con el turno recién cerrado.

**Lógica Clave**: Este proceso es la razón por la cual no podemos depender de `tempcheques` para consultas históricas. También es la causa del problema que identificamos: las eliminaciones de `tempcheques` al final del turno no son cancelaciones, son parte del ciclo de vida normal del sistema.

## El Papel de la Integración Avoqado en este Flujo

Nuestro servicio de Windows (`producer.ts`) y los scripts de SQL se diseñaron para "escuchar" este ciclo de vida sin ser invasivos:

- **Los Triggers** (`Trg_*`) actúan como micrófonos en las tablas temp*, reportando cada INSERT, UPDATE y DELETE a nuestra tabla-buzón `AvoqadoEntityTracking`.

- **El producer.ts** lee este buzón y, con el contexto que le hemos añadido, es lo suficientemente inteligente para:
  - Esperar a que una orden se estabilice antes de enviar una actualización (debouncing).
  - Entender que un DELETE en `tempcheques` que coincide con un UPDATE de cierre en `turnos` no es una cancelación, sino un archivo, y por lo tanto, debe ser ignorado.

## Resumen

En resumen, el sistema POS es un motor transaccional robusto y predecible. Nuestra integración respeta su ciclo de vida, observando los cambios de estado clave (`impreso=1`, `pagado=1`, cierre del turno) para mantener la plataforma Avoqado sincronizada de manera precisa y eficiente.

## Tablas y Campos Críticos

### Tablas Temporales (Turno Activo)
- **`tempcheques`**: Órdenes activas
  - `folio`: ID único de la orden
  - `pagado`: 0=abierta, 1=pagada
  - `cancelado`: 0=activa, 1=cancelada
  - `impreso`: 0=no impresa, 1=lista para pago
- **`tempcheqdet`**: Items de órdenes activas
- **`tempchequespagos`**: Pagos de órdenes activas

### Tablas Permanentes (Histórico)
- **`cheques`**: Órdenes históricas
- **`cheqdet`**: Items históricos
- **`chequespagos`**: Pagos históricos

### Tabla de Control
- **`turnos`**: Gestión de turnos con **Arquitectura Dual-Key**
  - `idturnointerno`: Primary Key técnico (bigint, auto-increment) - Valores: 80885, 80884, etc.
  - `idturno`: Business Key operativo (bigint) - Valores: 894, 893, etc. **[ESTE ES EL QUE USAN LAS APLICACIONES]**
  - `apertura`: Fecha/hora de apertura
  - `cierre`: Fecha/hora de cierre (NULL si activo)
  - **CRÍTICO**: Todas las operaciones POS usan `idturno`, no `idturnointerno`

## Estados Críticos para Monitoreo

1. **Orden Creada**: INSERT en `tempcheques` con `pagado=0`, `cancelado=0`, `impreso=0`
2. **Orden Modificada**: UPDATE en `tempcheques` o cambios en `tempcheqdet`
3. **Cuenta Impresa**: UPDATE `impreso=1` en `tempcheques`
4. **Orden Pagada**: INSERT en `tempchequespagos` + UPDATE `pagado=1` en `tempcheques`
5. **Orden Cancelada**: UPDATE `cancelado=1` en `tempcheques`
6. **Turno Cerrado**: UPDATE `cierre` en `turnos` + purga de temp*

## Arquitectura de Base de Datos Detallada

### Características Específicas de SQL Server 2014
- **Nivel de Compatibilidad**: SQL Server 2014 (versión 12.0.4100.1)
- **Tipos de Datos**: Usa `money` para monedas, `datetime2` para timestamps, `uniqueidentifier` para GUIDs
- **Indexado**: Incluye índices clustered y non-clustered para performance
- **Restricciones**: Uso extensivo de foreign keys (189 relaciones) y check constraints

### Estructura Completa de Tablas (366 Tablas)

#### Tablas de Negocio Principales:
- **`tempcheques`** (194 columnas) - Órdenes activas con lógica de negocio comprehensiva
- **`tempcheqdet`** - Items de orden con detalles de productos
- **`tempchequespagos`** - Registros de pago para órdenes activas
- **`productos`** - Catálogo de productos con precios y clasificaciones
- **`clientes`** - Datos maestros de clientes con información de contacto
- **`turnos`** - Gestión de turnos con controles de apertura/cierre
  - **Arquitectura Dual-Key**: `idturnointerno` (PK técnico) + `idturno` (business key)
  - **Uso operativo**: Las aplicaciones POS usan exclusivamente `idturno`
- **`areasrestaurant`** - Áreas de restaurante y gestión de mesas
- **`formasdepago`** - Configuración de métodos de pago

#### Tablas Históricas:
- **`cheques`** - Órdenes archivadas (espeja estructura de tempcheques)
- **`cheqdet`** - Items de orden archivados
- **`chequespagos`** - Registros de pago archivados

#### Configuración y Control:
- **`empresas`** - Configuración de empresa/sucursal
- **`estaciones`** - Configuración de terminales/estaciones POS
- **`usuarios`** - Cuentas de usuario y permisos
- **`workspace_*`** tablas - Gestión de workspaces multi-tenant

### Tablas de Integración Avoqado
- **`AvoqadoInstanceInfo`** - Almacena GUID único de instancia para soporte multi-ubicación
- **`AvoqadoEntityTracking`** - Tabla universal de seguimiento de cambios para órdenes, items, turnos
  - Clave primaria con constraint único en EntityType + EntityId
  - Indexado en LastModifiedAt + EntityType para performance
- **`AvoqadoEntitySnapshots`** - Snapshots de hash de contenido para detectar cambios reales (solo v1)
  - Constraint único en EntityType + EntityId
  - Indexado en EntityType + LastSentAt

### Tablas POS Mejoradas
El servicio agrega columnas timestamp `AvoqadoLastModifiedAt` a:
- **`tempcheques`** - Headers de orden (194 columnas incluyendo totales, cliente, pagos)
- **`tempcheqdet`** - Items de orden (productos, cantidades, precios, modificaciones)
- **`turnos`** - Información de turno (tiempos apertura/cierre, cajero, estación)

### Procedimientos Almacenados
- **`sp_TrackEntityChange`** - Registra cambios de entidad con timestamps y razones
- **`sp_GetEntityChanges`** - Obtiene cambios pendientes desde última sincronización (por lotes, máx 100)
- **`sp_UpdateEntitySnapshot`** - Actualiza snapshots de hash de contenido (solo v1)
- **`sp_CleanupStuckTracking`** - Procedimiento de mantenimiento para registros atorados

### Triggers de Base de Datos (Compatible SQL Server 2014)
- **`Trg_Avoqado_Orders`** - Rastrea creación, actualizaciones y eliminaciones de órdenes en `tempcheques`
- **`Trg_Avoqado_OrderItems`** - Rastrea cambios individuales de items dentro de órdenes en `tempcheqdet`
- **`Trg_Avoqado_Shifts`** - Rastrea eventos de apertura y cierre de turno en `turnos`

### Estrategia de Índices
**Claves Primarias:** Las 366 tablas tienen claves primarias definidas para integridad de datos
**Índices de Performance:**
- `IX_AvoqadoEntityTracking_Modified` - En LastModifiedAt + EntityType
- `IX_cheques_workspaceid` - Índice multi-columna para consultas de workspace
- `IX_cheques_fecha` - Consultas basadas en fecha para reportes
- `FYI_chequespagos_folio` - Índice de foreign key para búsquedas de pagos

### Relaciones y Integridad de Base de Datos
El sistema mantiene integridad de datos a través de **189 relaciones de foreign key**:
- **Relaciones de productos**: `productos` ← `tempcheqdet`, `cheqdet` (items de orden referencian productos)
- **Relaciones de clientes**: `clientes` ← `tempcheques` (órdenes referencian clientes)
- **Relaciones de pagos**: `formasdepago` ← `tempchequespagos` (pagos referencian métodos de pago)
- **Relaciones de área**: `areasrestaurant` ← `tempcheques` (órdenes referencian áreas de restaurante)
- **Relaciones de empresa**: `empresas` ← múltiples tablas (soporte multi-empresa)

## Formato de Entity ID
El servicio usa un sistema de ID de entidad jerárquico:
- **Órdenes**: `{InstanceId}:{IdTurno}:{Folio}` (ej., `abc123:894:1001`)
- **Items de Orden**: `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}` (ej., `abc123:894:1001:3`)
- **Turnos**: `{IdTurno}` (ej., `894`)

**NOTA IMPORTANTE**: Todos los Entity IDs usan `idturno` (business key), NO `idturnointerno` (PK técnico)

## Arquitectura Dual-Key de SoftRestaurant

### Patrón Técnico Avanzado
SoftRestaurant implementa una arquitectura dual-key sofisticada en la tabla `turnos`:

#### Capa Técnica (Base de Datos):
- **`idturnointerno`**: Primary Key técnico (bigint, auto-increment)
  - Valores secuenciales: 80885, 80884, 80883...
  - Usado para optimización de BD e integridad referencial
  - **NUNCA usado en lógica de aplicación**

#### Capa de Negocio (Aplicaciones POS):
- **`idturno`**: Business Key operativo (bigint, asignado manualmente)
  - Valores de negocio: 894, 893, 892...
  - Usado por todas las aplicaciones POS y lógica de negocio
  - Referenciado por `tempcheques.idturno` y tablas relacionadas

#### Capa de Integración (Avoqado):
- **Código correcto**: Usa `idturno` para todas las operaciones
- **Entity IDs**: Formato `{InstanceId}:{idturno}:{folio}`
- **Sincronización**: Compatible con la capa de aplicación POS

### Ejemplo Real de la Arquitectura:
```sql
-- Registro real en turnos:
idturnointerno: 80885  (PK técnico - no usar en código)
idturno: 894          (Business key - USAR en operaciones)
apertura: 2025-07-25 08:17:04.000
cajero: AVOQADO

-- Registro relacionado en tempcheques:
folio: 1
idturno: 894  (Referencia al business key, no al PK técnico)
mesa: 22
```

## Performance y Monitoreo de Base de Datos
- **Optimización SQL Server 2014**: Consultas optimizadas para características de performance de versión 12.0.4100.1
- **Uso de Índices**: Aprovecha índices del schema de 366 tablas para performance óptima de consultas
- **Connection Pooling**: Gestiona límites de conexión de SQL Server 2014 eficientemente
- **Query Batching**: Limita conjuntos de resultados para prevenir problemas de memoria con datasets grandes
- **Aislamiento Multi-tenant**: Asegura filtrado de WorkspaceId en todas las operaciones de base de datos
- **Dual-Key Optimization**: Queries usan `idturno` para compatibilidad con aplicaciones POS existentes