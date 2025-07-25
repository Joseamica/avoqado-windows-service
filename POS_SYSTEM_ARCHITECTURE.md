# Análisis Técnico del Flujo Operativo de SoftRestaurant POS

## Filosofía Central: El Ciclo de Vida Transaccional

El POS opera bajo un principio fundamental: un ciclo de vida transaccional basado en tablas temporales para operaciones activas y tablas permanentes para el histórico. La entidad principal, una orden o "cheque", no existe en un único estado, sino que transita por fases bien definidas, dejando una traza clara en la base de datos.

### Tablas Clave en este Ciclo

- **`tempcheques`**: Contiene las órdenes activas del turno actual. Es una tabla de alta transaccionalidad, constantemente leída y actualizada.
- **`cheques`**: Es el archivo histórico. Contiene una copia exacta de las órdenes una vez que han sido cerradas (pagadas o canceladas) y el turno finaliza.
- **`turnos`**: Gestiona el contexto temporal de las operaciones. Una orden siempre pertenece a un turno.

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
- **`turnos`**: Gestión de turnos
  - `idturno`: ID del turno
  - `apertura`: Fecha/hora de apertura
  - `cierre`: Fecha/hora de cierre (NULL si activo)

## Estados Críticos para Monitoreo

1. **Orden Creada**: INSERT en `tempcheques` con `pagado=0`, `cancelado=0`, `impreso=0`
2. **Orden Modificada**: UPDATE en `tempcheques` o cambios en `tempcheqdet`
3. **Cuenta Impresa**: UPDATE `impreso=1` en `tempcheques`
4. **Orden Pagada**: INSERT en `tempchequespagos` + UPDATE `pagado=1` en `tempcheques`
5. **Orden Cancelada**: UPDATE `cancelado=1` en `tempcheques`
6. **Turno Cerrado**: UPDATE `cierre` en `turnos` + purga de temp*