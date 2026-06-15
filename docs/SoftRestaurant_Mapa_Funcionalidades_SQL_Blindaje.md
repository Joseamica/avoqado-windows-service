# SoftRestaurant — Mapa de Funcionalidades, SQL y Blindaje del Sync

> Documento maestro del bridge de sincronización SoftRestaurant ↔ Avoqado (servicio Windows).
> Mapea, por cada funcionalidad del POS, **qué SQL toca las tablas POS**, **qué triggers Avoqado disparan** y **qué tan blindado está el sync** frente a pérdidas de eventos, IDs erróneos, falsas cancelaciones y descuadres de caja.
>
> Repo canónico: `C:\Dev\Avoqado\avoqado-windows-service`. Archivos clave: `src/adapters/SoftRestaurant11Adapter.ts`, `src/components/producer.ts`, `src/components/commander.ts`, `src/services/Orders/createEmptyOrder.ts`, `scripts/sql/01-COMPLETE-INSTALL.sql`.

---

## 1. Resumen ejecutivo

El bridge está **parcialmente blindado**. La columna vertebral de durabilidad (`AvoqadoTracking.ProcessedAt` + publicar-antes-de-marcar) es sólida y el polling no se solapa. Pero la auditoría adversarial encontró **un conjunto de gaps confirmados que comprometen dinero, identidad de entidades y la frontera de cierre de turno**, concentrados en la ruta **v11/v12 (WorkspaceId)** — que es la ruta de producción dominante según las notas de memoria.

**Conteo de gaps confirmados:**

- **1 CRITICAL** — Pagos parciales reescriben destructivamente `tempcheques.total` y cantidades, con drift de saldo y posible cierre/cobro incorrecto.
- **18 HIGH** confirmados (entity-id en DELETE de items v11, supresión de cierre de turno inexistente en v11, flag `AvoqadoShiftArchiving` que nadie arma, propina doble-contada, fast-payment sin WorkspaceId, `numcheque` no expuesto, eventos `payment` que se tragan en silencio, movimientos de caja sin trigger, idempotencia ausente en pagos, etc.).
- Decenas de hallazgos MEDIUM/LOW y de completitud (mapeo de payload incompleto, tax hardcodeado al 16%, código muerto, `ORDER BY Timestamp` sin desempate, catálogos no sincronizados).

### Las 5 cosas más importantes a arreglar (en orden)

1. **[CRITICAL] Pagos parciales destructivos** (`sp_ApplyPartialPayment`, `01-COMPLETE-INSTALL.sql:401-514`): cada parcial reescribe `total` y multiplica `cantidad` por una razón; el segundo parcial lee el `total` ya encogido pero `SUM(importe)` aún cuenta el anterior → el saldo deriva y el pedido puede marcarse pagado antes de cubrir el total original. **Anclar el total original** y no derivar el restante del header mutado.

2. **[HIGH] Cierre de turno NO está blindado en v11/v12.** La supresión de DELETEs en el producer solo existe para v10 (`producer.ts:246-260`); la rama v11 (`:261-266`) es un no-op que loguea. `processOrderChangeV11` devuelve `CANCELLED` incondicional en DELETE (`:581-583`). Además **nada arma `AvoqadoShiftArchiving`** (`sp_BeginShiftArchiving` no se llama desde ningún `.ts`), y el fallback de 30s falla porque `turnos.cierre` se setea *después* de los DELETEs. Resultado: un cierre lento puede republicar ventas completadas como **canceladas**.

3. **[HIGH] Item DELETE v11 emite el WorkspaceId de la ORDEN, no de la línea** (`01-COMPLETE-INSTALL.sql:704-707`): el backend no puede identificar qué línea se borró. Rompe quitar producto / quitar modificador en toda venue v11.

4. **[HIGH] Eventos de pago se tragan en silencio.** El `switch` del producer (`producer.ts:230-305`) no tiene caso `'payment'`; los renglones `EntityType='payment'` se marcan procesados sin publicar. **Los pagos parciales nunca llegan al backend** (los `payments[]` solo se leen cuando `pagado=1`).

5. **[HIGH] FastPayment no escribe WorkspaceId** en `tempcheques/tempcheqdet/tempchequespagos` (`SoftRestaurant11Adapter.ts:createFastPayment`): en v11 el entity-id cae a formato v10 con dos puntos, el producer lo enlaza como `UniqueIdentifier`, falla y **se pierde la venta**.

> **Advertencia transversal:** el repo **no contiene profiler traces reales** (`info-softrest11/sql-traces` está ausente). Todo lo marcado `needs-live`/`domain-inferred` — en especial el cierre nativo de turno, el alta nativa de cuenta, los movimientos de caja y la facturación CFDI — **debe confirmarse con captura en vivo** (Extended Events / `npm run monitor`) antes de tratarse como verdad de campo.

---

## 2. Leyenda de confianza

| Nivel | Significado |
|---|---|
| **code-confirmed** | Verificado leyendo el código/SQL del repo (adapter, producer, triggers, SPs). Es lo que el sistema realmente hace. |
| **docs-confirmed** | Confirmado en docs del repo (CLAUDE.md/AGENTS.md, PAYMENT-*.md) o en scripts `[deprecated]`. Refleja diseño/intención, no necesariamente la ruta activa. |
| **domain-inferred** | Inferido del modelo SoftRestaurant (ciclo de vida 4 fases, dual-key turnos, columnas conocidas) pero **no** verificable en el repo. Hipótesis razonable, requiere validación. |
| **needs-live** | Solo confirmable capturando SQL en una instancia real. El repo no tiene la evidencia. |

> ⚠️ **El repo NO tiene traces de SQL Server Profiler / Extended Services.** El directorio `info-softrest11/sql-traces` está ausente del árbol canónico. Por tanto, **el SQL nativo del POS** (alta de cuenta F7, pago en caja, cierre Z, movimientos de caja, timbrado CFDI) es como máximo `domain-inferred`. La columna exacta, el orden de operaciones y los límites transaccionales del POS nativo **deben capturarse en vivo** (ver §6). El SQL que SÍ es `code-confirmed` es el que escribe el *adapter* de Avoqado y lo que hacen los *triggers/SPs* instalados por `01-COMPLETE-INSTALL.sql`.

---

## 3. Mapa por área

### 3.1 Apertura de turno (Abrir turno)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Apertura iniciada por Avoqado (`Shift.OPEN` → `openShift`) | RabbitMQ `command.{posType}.{venueId}` `{entity:'Shift',action:'OPEN'}` → `commander.ts:86-97` → `adapter.openShift` | `turnos` SELECT `ISNULL(MAX(idturno),0)+1`; `meseros` SELECT nombre; `turnos` INSERT (idturno, fondo, apertura=GETDATE(), idestacion, cajero=posStaffId, idempresa='1', idmesero='', WorkspaceId=NEWID(), cierre NULL); `parametros` UPDATE ultimoturno (sin WHERE) | `Trg_Avoqado_Shifts` (INSERT cierre NULL → `shift`/`OPENED`) | code-confirmed |
| Apertura nativa del POS (solo se OBSERVA) | Terminal SoftRestaurant: Apertura de caja (fondo, estación, cajero) | `turnos` INSERT nativo (columnas exactas DESCONOCIDAS); posible `folios`/`parametros`/`cajas` | `Trg_Avoqado_Shifts` (rama open) | needs-live |
| Comportamiento del trigger de turnos (entity-id v10 vs v11) | Automático en cualquier INSERT/UPDATE de `turnos` | `AvoqadoConfig` SELECT HasWorkspaceId; `turnos` SELECT WorkspaceId WHERE idturno (v11); `AvoqadoTracking` INSERT `shift`/`OPENED` | `Trg_Avoqado_Shifts` | code-confirmed |
| Publicación `shift.created` por el producer | Polling 2s `sp_GetPendingChanges` | `turnos` SELECT * (por idturno v10 / WorkspaceId v11); `AvoqadoTracking` UPDATE ProcessedAt | ninguno (lectura) | code-confirmed |

**v10 vs v11/v12:** EntityId de turno = `turnos.WorkspaceId` (GUID) en v11/v12; `idturno` numérico (string) en true-v10. `shiftData.staffId` se lee de `turnos.idmesero`, pero `openShift` escribe `idmesero=''` (el cajero va a `cajero`) → staffId vacío en aperturas Avoqado.

---

### 3.2 Abrir cuenta/mesa (Comedor F7)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Abrir orden vía comando (`Order.CREATE` → `createEmptyOrder`) | RabbitMQ `Order.CREATE` → `commander.ts:54-57` → `createEmptyOrder.ts` | `tempcheques` SELECT (guard ocupación, fuera de tx); `folios` SELECT ultimaorden serie=''; `tempcheques` INSERT (mesa, nopersonas, idmesero, idturno=0, pagado/cancelado/impreso=0, idarearestaurant='01' **hardcode**, idempresa='1' **hardcode**, tipodeservicio=1, WorkspaceId=NEWID()); `tempcheques` SELECT folio WHERE WorkspaceId; `folios` UPDATE ultimaorden; **post-commit** `tempcheques` UPDATE totales=0 (fuera de tx) | `Trg_Avoqado_Orders` (INSERT→CREATE; UPDATE post-commit→UPDATE) | code-confirmed |
| Trg_Avoqado_Orders en el INSERT | Automático en cualquier DML de `tempcheques` | `AvoqadoShiftArchiving` SELECT (guard); `turnos` SELECT cierre<30s (guard); `AvoqadoTracking` INSERT `order`/`CREATE` | `Trg_Avoqado_Orders` | code-confirmed |
| Publicación `order.created` | Polling 2s; created se envía inmediato (sin debounce) | `tempcheques`/`meseros`/`areasrestaurant`/`turnos`(idturno=0→shift abierto más reciente)/`formasdepago` SELECT | ninguno (lectura) | code-confirmed |
| Transición idturno=0 → idturno real (en pago, no en apertura) | `Payment.APPLY` → `sp_ApplyPartialPayment` | `turnos` SELECT cierre IS NULL; `tempcheques` UPDATE idturno (solo si era 0) | `Trg_Avoqado_Orders` (UPDATE) | code-confirmed |
| Alta nativa F7 (lo que el POS REAL escribe) | Comedor → mesa libre → F7/Nueva cuenta | `tempcheques` INSERT (idturno ¿0 o real?), `folios` MULTI, `mesas` UPDATE estatus_ocupacion, `mesasasignadas` INSERT — **todo inferido** | `Trg_Avoqado_Orders` (INSERT) | needs-live |

**v10 vs v11/v12:** EntityId de orden = `WorkspaceId` (v11/v12) o `{InstanceId}:{idturno}:{folio}` (v10). Como la orden nace con `idturno=0`, en v10 el EntityId inicial es `{InstanceId}:0:{folio}` — raíz documentada del riesgo de duplicados (`SOFTRESTAURANT_ENTITY_RESOLUTION.md`). Avoqado **no** escribe `mesas`/`mesasasignadas` (la ocupación es invisible al/desde el POS nativo).

---

### 3.3 Agregar/quitar/cambiar cantidad de productos (tempcheqdet)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Agregar línea (`addItemToOrder`) | `OrderItem.CREATE` → `commander.ts:59-67` → `adapter.addItemToOrder` | `productos` SELECT (por descripcion, **fuera de tx**); `tempcheqdet` SELECT MAX(movimiento); `tempcheqdet` INSERT (precio UNITARIO, preciosinimpuestos=precio/1.16, impuesto1=16.00 **hardcode**, idestacion='AVOQADO_SYNC', **sin WorkspaceId**); `tempcheques` UPDATE totales por SUM | `Trg_Avoqado_OrderItems` (INSERT → orderitem CREATE + order UPDATE); `Trg_Avoqado_Orders` (UPDATE totales) | code-confirmed |
| Cancelar/quitar línea (`cancelOrderItem`) | **NO cableado** a ningún comando (`commander.ts` no tiene caso) | `tempcheqdet` SELECT; `productosenproduccion` UPDATE cancelado=1; `tempcheqdet` DELETE; `tempcancela` INSERT; `bitacorasistema` INSERT (**`...` placeholder inválido**). **NO recalcula totales** | `Trg_Avoqado_OrderItems` (DELETE) | code-confirmed |
| Ajuste proporcional de cantidades en pago parcial | `Payment.APPLY` → `sp_ApplyPartialPayment` (rama PARTIAL) | `tempcheqdet` UPDATE `cantidad = cantidad * @RemainingRatio` (TODAS las líneas); `tempcheques` UPDATE totales=restante | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | code-confirmed |
| Split (`splitOrderItems`/`adjustOrderItemQuantities`) | Privados, **código muerto** (sin comando) | `tempcheqdet` SELECT/INSERT(29 cols)/UPDATE escalado por ratio | `Trg_Avoqado_OrderItems` | code-confirmed |
| Línea de FastPayment | `FastPayment.CREATE` → `createFastPayment` | `tempcheqdet` INSERT (idproducto='FASTPAY', precio=preciosinimpuestos=monto, impuesto=0, **sin WorkspaceId**) | `Trg_Avoqado_OrderItems` | code-confirmed |
| Emisión multi-fila del trigger de items | Automático en INSERT/UPDATE/DELETE `tempcheqdet` | `AvoqadoShiftArchiving`/`turnos` (guards); `tempcheques` subconsultas idturno/WorkspaceId; `AvoqadoTracking` INSERT orderitem + order UPDATE por foliodet | `Trg_Avoqado_OrderItems` | code-confirmed |

**v10 vs v11/v12:** EntityId de item = WorkspaceId propio de la línea (v11) o `{InstanceId}:{idturno}:{folio}:{movimiento}` (v10). Los items se publican **inmediato** (sin debounce). En DELETE el payload v11 trae `parentOrderExternalId:null` (la fila ya no existe).

---

### 3.4 Modificadores, comentarios, tiempos, precio/desc por item

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Comentario por item (`comentario`) | Comanda → línea → Comentario | `tempcheqdet` INSERT/UPDATE comentario (Avoqado lo escribe en addItemToOrder); `tempcheques` UPDATE totales | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | code-confirmed (write) / needs-live (edit nativo) |
| Descuento por item (`descuento` + metadata) | Línea → Descuento | `tempcheqdet` UPDATE descuento/idtipodescuento/usuariodescuento/comentariodescuento; `tempcheques` UPDATE totales. **Avoqado no tiene comando de descuento** | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | code-confirmed (columnas) / needs-live (SET nativo) |
| Override de precio (`precio`/`preciocatalogo`) | Línea → Cambiar precio | `tempcheqdet` UPDATE precio, preciosinimpuestos=precio/1.16 (preciocatalogo retiene original) | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | code-confirmed (semántica) / needs-live (nativo) |
| Modificadores/guarniciones (`modificador`, `idproductocompuesto`, `productocompuestoprincipal`, `mitad`) | Diálogo Modificadores | `tempcheqdet` INSERT fila hija por modificador; `tempcheques` UPDATE totales. **Sin soporte de escritura en Avoqado** | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | domain-inferred |
| Curso/tiempo (`tiempo`, `horaproduccion`, `estadomonitor`, `marcar`) | Línea → Tiempo/Enviar | `tempcheqdet` UPDATE tiempo; posible `productosenproduccion` | `Trg_Avoqado_OrderItems` | domain-inferred |

**v10 vs v11/v12 + GAP de payload:** `modificador`, `idproductocompuesto`, `tiempo`, `preciocatalogo`, `idcliente`, `nopersonas` **NO** se exponen como campos de primer nivel — viajan **solo dentro de `posRawData`**. El backend ve un modificador como producto independiente.

---

### 3.5 Descuentos, propina, comensales, cliente, mesero (nivel cuenta)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Descuento de cuenta | Pantalla cuenta → Descuento (**no hay comando Avoqado**) | `tempcheques` UPDATE descuento/descuentoimporte/descuentocriterio + totales; `AvoqadoTracking` order/UPDATE | `Trg_Avoqado_Orders` | code-confirmed (mapeo) / needs-live (SET) |
| Propina de cuenta | Pantalla cuenta → Propina (**no hay comando**) | `tempcheques` UPDATE propina + totalconpropina; (propina de pago va a `tempchequespagos.propina`) | `Trg_Avoqado_Orders` | code-confirmed |
| Comensales (`nopersonas`) | Mesa → No. personas (Avoqado solo en creación) | `tempcheques` UPDATE nopersonas | `Trg_Avoqado_Orders` | code-confirmed |
| Asignar cliente (`idcliente`) | Cuenta → Cliente (**no hay comando**) | `tempcheques` UPDATE idcliente | `Trg_Avoqado_Orders` | code-confirmed |
| Cambiar mesero (`idmesero`) | Cambiar mesero (Avoqado solo en creación) | `tempcheques` UPDATE idmesero; producer re-resuelve nombre/PIN vía `meseros` | `Trg_Avoqado_Orders` | code-confirmed |
| Cobertura UPDATE del trigger de órdenes | Automático | **Sin guard por columna** (cualquier cambio = 1 fila `order`/`UPDATE`); debounce 2.5s coalesce | `Trg_Avoqado_Orders` | code-confirmed |

**GAP de payload:** `discountAmount`(=descuentoimporte), `tipAmount`(=propina), `staffData`(=idmesero) SÍ se mapean; **`nopersonas` (comensales) e `idcliente` (cliente) NO** — solo en `posRawData`.

---

### 3.6 Dividir / juntar / cambiar mesa, transferir items

> **Caveat de área:** Avoqado **NO ejecuta** split/merge/transfer/cambiar-mesa. No hay caso en `commander.ts` (solo Order.CREATE, OrderItem.CREATE, Payment.APPLY, Shift.OPEN, Shift.CLOSE, FastPayment.CREATE) ni método en `IPosAdapter`. Los helpers `createSplitOrder`/`splitOrderItems` del adapter son **código muerto**. Todo es nativo del POS; Avoqado solo OBSERVA vía triggers.

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Cambiar mesa | Cuenta → Cambiar mesa | `tempcheques` UPDATE mesa; `mesas`/`mesasasignadas` MULTI (no observadas) | `Trg_Avoqado_Orders` (order UPDATE) | needs-live |
| Dividir cuenta | Cuenta → Dividir/Separar | `tempcheques` INSERT hija; `tempcheqdet` MULTI (re-point o delete+insert); `tempcheques` UPDATE padre; `folios` UPDATE | `Trg_Avoqado_Orders` (CREATE hija + UPDATE padre), `Trg_Avoqado_OrderItems` | needs-live |
| Juntar cuentas | Seleccionar 2 → Juntar | `tempcheqdet` MULTI (mover a sobreviviente); `tempcheques` UPDATE sobreviviente; `tempcheques` **DELETE** absorbida | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` (DELETE→**CANCELLED**) | needs-live |
| Transferir items | Línea → Transferir | `tempcheqdet` MULTI (re-point foliodet A→B); `tempcheques` UPDATE A y B | `Trg_Avoqado_OrderItems`, `Trg_Avoqado_Orders` | needs-live |

**Riesgo v11:** en transfer por `UPDATE foliodet`, el trigger lo lee como DELETE-en-A + CREATE-en-B; si el WorkspaceId viaja con la fila, el MISMO EntityId aparece como DELETE y luego CREATE. **Merge publica la cuenta absorbida como CANCELLED** (la supresión de cierre no cubre merges).

---

### 3.7 Imprimir cuenta (impreso=1, numcheque)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Imprimir nativo (impreso=1 + numcheque) | POS → Imprimir Cuenta/Pre-cuenta (**no hay comando Avoqado**) | `folios` SELECT (TABLOCKX) ultimofolio; `tempcheques` UPDATE impreso=1, numcheque, cierre=GETDATE(), impresiones+1, seriefolio; `folios` UPDATE ultimofolio; `cuentas` UPDATE imprimir/procesado | `Trg_Avoqado_Orders` | domain-inferred |
| Impresión incluida en cierre/pago (`closeAndPayOrder`/`markOrderAsPaid`) | **Legacy/no cableado** | `folios` SELECT ultimofolio; `tempcheques` UPDATE pagado=1, impreso=1, numcheque, cierre; `folios` UPDATE; `cuentas` UPDATE procesado | `Trg_Avoqado_Orders` | code-confirmed |
| Paso de impresión en FastPayment | `FastPayment.CREATE` | `tempcheques` SELECT MAX(numcheque)+1 **por turno** (no folios); `tempcheques` UPDATE impreso=1, numcheque, impresiones=1 | `Trg_Avoqado_Orders` | code-confirmed |
| Publicación del estado impreso | Producer | `AvoqadoTracking` INSERT order/UPDATE → `order.updated` (debounce). `orderNumber=folio` (NO numcheque); impreso/numcheque **solo en posRawData** | `Trg_Avoqado_Orders` | code-confirmed |

**Nota:** la ruta de producción (`sp_ApplyPartialPayment`) **nunca** setea impreso/numcheque/cierre. No existe evento de impresión discreto.

---

### 3.8 Pago / liquidación (tempchequespagos, pagado=1)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Pago canónico (`sp_ApplyPartialPayment`) | `Payment.APPLY` → `applyIntelligentPayment` → EXEC | `tempcheques` SELECT total/WorkspaceId/idturno; `turnos` SELECT (si idturno=0); `tempcheques` UPDATE idturno; `tempchequespagos` SELECT SUM(importe); `tempchequespagos` INSERT (idformadepago=@PaymentMethod, importe, propina=@TipAmount, WorkspaceId=de la ORDEN); FULL: `tempcheques` UPDATE pagado=1; PARTIAL: `tempcheqdet` UPDATE cantidad*ratio + `tempcheques` UPDATE totales=restante; `AvoqadoTracking` INSERT payment CREATE + order UPDATE | `Trg_Avoqado_Payments`, `Trg_Avoqado_Orders`, `Trg_Avoqado_OrderItems` | code-confirmed |
| Split tender (varios métodos) | N×`Payment.APPLY` secuenciales | `tempchequespagos` MULTI (1 fila por tender); decisión partial/full por SUM acumulado | (igual que arriba, por tender) | code-confirmed |
| Propina en tarjeta | `paymentData.tip` → `@TipAmount` | `tempchequespagos` INSERT propina=@TipAmount (**NO se resta de importe**) | `Trg_Avoqado_Payments` | code-confirmed |
| Cambio/sobrepago (`cambio`) | Implícito si monto>saldo | `@Remaining` negativo → FULL; adapter reporta change=abs(remaining). **NO se escribe `tempcheques.cambio`** | `Trg_Avoqado_Payments`, `Trg_Avoqado_Orders` | code-confirmed |
| WorkspaceId-por-pago para archivado | En INSERT del pago | `tempchequespagos` INSERT WorkspaceId=de la orden; archivado join por **folio** (tolera mismatch) | `Trg_Avoqado_Payments` (suprimido en cierre) | code-confirmed |
| Trg_Avoqado_Payments | Automático en DML `tempchequespagos` | `AvoqadoShiftArchiving`/`turnos` guards; `AvoqadoTracking` INSERT payment CREATE/UPDATE/DELETE por folio | `Trg_Avoqado_Payments` | code-confirmed |
| Fast payment (`createFastPayment`) | `FastPayment.CREATE` | orden+item+impreso+pago+pagado=1 + buckets efectivo/tarjeta/vales/otros, todo en 1 tx. **Sin WorkspaceId, propina=0** | Orders, OrderItems, Payments | code-confirmed |
| Rutas legacy (`applyPayment`/`closeAndPayOrder`/`insertPaymentToPOS`) | **No cableadas** | placeholders/`...` no ejecutables | (no aplica) | code-confirmed |
| Pago nativo en caja | POS → Pagar → Cobrar | `tempcheques` UPDATE pagado=1 + buckets + propina/propinatarjeta/cambio; `tempchequespagos` INSERT (con WorkspaceId v11); `folios` numcheque | `Trg_Avoqado_Payments`, `Trg_Avoqado_Orders` | needs-live |

**v10 vs v11/v12:** EntityId de pago = `SELECT TOP 1 WorkspaceId FROM tempchequespagos WHERE folio ORDER BY WorkspaceId DESC` (v11) o `{InstanceId}:{Folio}:PAY` (v10). El producer **no tiene caso `payment`** → los eventos de pago no se publican como tales.

---

### 3.9 Pagos parciales

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Pago parcial/total canónico | `Payment.APPLY` → EXEC `sp_ApplyPartialPayment` | (ver §3.8); **PARTIAL reescribe `tempcheques.total`=restante y `tempcheqdet.cantidad`*ratio** | Orders, OrderItems, Payments | code-confirmed |
| Resolución de folio desde externalId | `extractFolioFromExternalId` | v11: `SELECT TOP 1 folio WHERE WorkspaceId ORDER BY folio DESC`; v10: parts[2] | ninguno | code-confirmed |
| Ajuste de cantidad (encogimiento proporcional) | Rama PARTIAL | `tempcheqdet` UPDATE cantidad*@RemainingRatio (DECIMAL(38,10)); recomputa subtotal/tax del ORIGINAL capturado | OrderItems, Orders | code-confirmed |
| Auditoría (`AvoqadoPartialPayments`/`AvoqadoDebugLog`) | DebugLog automático; PartialPayments solo vía `trackPartialPayment` (**no llamado**) | `AvoqadoDebugLog` INSERT (~10/llamada); `AvoqadoPartialPayments` **muerto en runtime** | ninguno | code-confirmed |
| Publicación de resultados parciales | Producer | `AvoqadoTracking` payment+order; **payments[] solo si pagado=1** → parciales no emiten pago | ninguno | code-confirmed |
| Variante deprecada (`04-Native-Payment-Flow.sql`) | Si se instaló sobre la canónica | re-resuelve idformadepago por tipo, importe=monto-tip, **sin WorkspaceId**, full=print nativo | Orders, Payments | docs-confirmed |

---

### 3.10 Cancelaciones (item, cuenta, post-impresión)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Cancelar item (detección) | POS → línea → Cancelar (**no hay comando**) | `tempcheqdet` DELETE; `cancela`/`tempcancela` INSERT (razón/usuario, **no observada**); `productosenproduccion` UPDATE; `tempcheques` UPDATE totales | `Trg_Avoqado_OrderItems` (DELETE), `Trg_Avoqado_Orders` (UPDATE) | domain-inferred |
| Cancelar item (ejecución `cancelOrderItem`) | **Definida pero no alcanzable** | (ver §3.3); `bitacorasistema` INSERT **malformado `...`** | `Trg_Avoqado_OrderItems` (DELETE) | code-confirmed |
| Cancelar cuenta completa | POS → Cancelar cuenta | `tempcheques` UPDATE cancelado=1 (fila permanece); `cancela` INSERT (inferido) | `Trg_Avoqado_Orders` (UPDATE→**CANCELLED**) | code-confirmed |
| Anular tras impresión | POS → cancelar cheque impreso | `tempcheques` UPDATE cancelado=1 (impreso queda 1) | `Trg_Avoqado_Orders` (→CANCELLED) | domain-inferred |
| Supresión DELETE-archivado vs cancelación real | Cierre Z | guards `AvoqadoShiftArchiving.IsArchiving=1` **(nadie lo arma)** + fallback 30s `turnos.cierre` | Orders/OrderItems/Payments suprimidos; Shifts emite CLOSED | code-confirmed |

**Cancelación = `cancelado=1`** (la fila NO se borra) según producer (`:546/:663`). Pero **no hay evidencia confirmada** de que el POS nativo use el flag en vez de DELETE — `needs-live`.

---

### 3.11 Retiro/depósito y cortes de caja (Caja)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Cash IN (Depósito) | Caja → Depósito (**no hay comando**) | `movimientoscaja` INSERT (nombre real SIN verificar) | **NINGUNO** | domain-inferred |
| Cash OUT (Retiro) | Caja → Retiro | `movimientoscaja` INSERT | **NINGUNO** | domain-inferred |
| Corte X (solo lectura) | Caja → Corte X | SELECTs agregados (sin INSERT/UPDATE); `turnos.cierre` queda NULL | **NINGUNO** (no dispara) | domain-inferred |
| Corte Z / Cierre de turno | Caja → Corte Z; o `Shift.CLOSE` → `closeShift` | `cheques/cheqdet/chequespagos` INSERT (archivado); DELETE temp*; `turnos` UPDATE cierre/efectivo/tarjeta/vales (**otros NO se escribe**); `folios` UPDATE reset | `Trg_Avoqado_Shifts` (CLOSED), Orders/OrderItems/Payments (DELETE) | code-confirmed |

**Blind spot mayor:** no hay trigger en ninguna tabla de movimientos de caja → retiros/depósitos invisibles. La conciliación de efectivo en Avoqado es estructuralmente incompleta.

---

### 3.12 Cierre de turno (archivado temp→permanente)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Cierre nativo del POS (ruta de producción) | Caja → Corte de caja/Cerrar turno | `cheques/cheqdet/chequespagos` INSERT (join por folio, idturno scope); aux INSERTs (cancela, foliosfacturados, etc.); `mesas` UPDATE; `PRODUCTOSENPRODUCCION` DELETE; `folios` UPDATE; **`turnos` UPDATE cierre=GETDATE() ← punto de detección**; DELETE temp* (DESPUÉS de cierre) | Shifts (CLOSED); Orders/OrderItems/Payments (DELETE, **deberían suprimirse**) | domain-inferred |
| Trg_Avoqado_Shifts emite CLOSED | Automático en `turnos.cierre` NULL→NOT NULL | `turnos` SELECT; `AvoqadoTracking` INSERT shift/CLOSED. **Sin guard de archivado** (correcto) | `Trg_Avoqado_Shifts` | code-confirmed |
| Supresión DELETE en temp* | Automático en DELETE temp* | guard1 `AvoqadoShiftArchiving.IsArchiving=1` (**dead**); guard2 fallback 30s `turnos.cierre` | Orders/OrderItems/Payments (suprimidos si guard activa) | code-confirmed |
| Supresión context-aware del producer | Poll loop | `AvoqadoTracking` SELECT; `turnos` SELECT cierre; build `closedShiftIdsInBatch`. **v10 funciona; v11 es no-op** | ninguno | code-confirmed |
| Cierre iniciado por Avoqado (`closeShift`) | `Shift.CLOSE` → `commander.ts:99-110` | archivalQueries con **`...` placeholder no ejecutable**; DELETE temp*; `turnos` UPDATE cierre/efectivo/tarjeta/vales; `folios` reset. **No llama sp_BeginShiftArchiving** | Shifts (CLOSED), Orders/OrderItems/Payments (DELETE, solo guard 30s) | code-confirmed |
| Publicación `shift.closed` | Producer | `turnos` SELECT (por WorkspaceId v11 / idturno v10) | ninguno | code-confirmed |

---

### 3.13 Venta rápida (F9) y Domicilio (F8)

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Venta rápida vía Avoqado (`createFastPayment`) | `FastPayment.CREATE` | 10 ops en 1 tx: turnos SELECT, folios, tempcheques INSERT (tipoventarapida=1/tipodeservicio=3/mesa='FAST', **sin WorkspaceId**), tempcheqdet INSERT, impreso UPDATE, tempchequespagos INSERT, pagado=1 + buckets | Orders, OrderItems, Payments | code-confirmed |
| Venta rápida nativa (F9) | Cajero → F9 | tempcheques/tempcheqdet/tempchequespagos nativos (idturno ¿0?) | Orders, OrderItems, Payments | domain-inferred |
| Domicilio (F8) | Cajero → F8 (cliente, dirección, repartidor, estados) | tempcheques (tipodeservicio=2?), driver/status/dirección — **tabla/columnas DESCONOCIDAS** | Orders/OrderItems/Payments (si en tempcheques) | domain-inferred |
| Create+add+pay (análogo ajustado) | Order.CREATE + OrderItem.CREATE + Payment.APPLY | 3 tx independientes; idturno=0 reconciliado en pago | Orders, OrderItems, Payments | code-confirmed |
| Republicación de eventos | Producer | (por WorkspaceId v11 / split v10) | ninguno | code-confirmed |

**Riesgo:** delivery (F8) **completamente sin modelar** — driver/estado/teléfono/dirección no generan evento dedicado y pueden vivir en tablas no observadas.

---

### 3.14 Facturación CFDI

| Funcionalidad | Ruta UI | SQL (tabla/op/columnas) | Triggers | Confianza |
|---|---|---|---|---|
| Generación/timbrado CFDI (nativo) | POS → Facturación → Generar Factura | `foliosfacturas` MULTI; `facturas` INSERT (UUID/RFC/uso CFDI); `cheques`/`tempcheques` UPDATE facturado=1 (**¿cuál?**) | **NINGUNO** en tablas fiscales; posible `Trg_Avoqado_Orders` si toca tempcheques activo | needs-live |
| Write-back facturado en venta activa | Facturar antes del corte | `tempcheques` UPDATE facturado (si aplica) → evento `order.updated` redundante | `Trg_Avoqado_Orders` (sin guard de columna) | needs-live |
| Gating PREMIUM CFDI | N/A (el bridge no factura) | `tempcheques` SELECT * → `posRawData` reenvía columnas fiscales sin filtro de tier | ninguno (lectura) | code-confirmed |

**El bridge no factura.** Grep en `src/` no encuentra factura/RFC/PAC/timbre. CFDI es código PREMIUM en el server; el bridge no puede filtrar tier (reenvía `posRawData` completo).

---

## 4. Cobertura de triggers — matriz blind spots

`01-COMPLETE-INSTALL.sql` instala **solo 4 triggers**: `Trg_Avoqado_Orders` (tempcheques, L631), `Trg_Avoqado_OrderItems` (tempcheqdet, L680), `Trg_Avoqado_Payments` (tempchequespagos, L737), `Trg_Avoqado_Shifts` (turnos, L786).

| Tabla POS | ¿Escrita por algún flujo? | ¿Trigger Avoqado? | Estado |
|---|---|---|---|
| `tempcheques` | Sí (orden, totales, pago, cancel, mesa) | ✅ Trg_Avoqado_Orders | **Cubierta** |
| `tempcheqdet` | Sí (items, modificadores, cantidad) | ✅ Trg_Avoqado_OrderItems | **Cubierta** |
| `tempchequespagos` | Sí (pagos, propina) | ✅ Trg_Avoqado_Payments | **Cubierta** |
| `turnos` | Sí (apertura/cierre) | ✅ Trg_Avoqado_Shifts (solo INSERT/UPDATE, **no DELETE**) | **Cubierta parcial** |
| `movimientoscaja` (o nombre real) | Sí (retiro/depósito nativo) | ❌ | 🔴 **BLIND SPOT (cash ops)** |
| `cancela` / `tempcancela` | Sí (auditoría de cancelación: razón/usuario) | ❌ | 🔴 **BLIND SPOT (motivo/auth de void)** |
| `productosenproduccion` | Sí (cocina, cancelado=1, tiempos) | ❌ | 🟠 Blind spot (cocina/KDS) |
| `bitacorasistema` | Sí (log de sistema) | ❌ | 🟠 Blind spot (auditoría) |
| `mesas` / `mesasasignadas` | Sí (ocupación, cambiar mesa) | ❌ | 🟠 Blind spot (ocupación) |
| `cheques` / `cheqdet` / `chequespagos` | Sí (archivo en cierre) | ❌ (por diseño) | ⚪ Blind spot intencional (facturar archivado no se observa) |
| `facturas` / `foliosfacturas` | Sí (CFDI) | ❌ | ⚪ Fuera de alcance (PREMIUM, server-side) |
| `productos` / `formasdepago` / `meseros` / `areasrestaurant` / `clientes` (catálogos) | Sí (edición POS) | ❌ | 🟠 Blind spot (catálogos no sincronizados POS→plataforma) |
| `cuentas` | Sí (imprimir/procesado) | ❌ | ⚪ Blind spot menor |
| `folios` | Sí (contadores) | ❌ | ⚪ Tabla contador, aceptable |

---

## 5. Gaps de blindaje confirmados

> Ordenados por severidad. Cada uno cita archivo/líneas y recomendación accionable.

### 🔴 CRITICAL

#### C-1 · Pagos parciales reescriben destructivamente el total y las cantidades → drift de saldo / cierre o cobro incorrecto
- **✅ ARREGLADO (2026-06-15):** `sp_ApplyPartialPayment` ahora computa `@Remaining = @OrderTotal - @PaymentAmount`, tomando `tempcheques.total` como el **saldo pendiente vigente** (ya no vuelve a restar `@PaidSoFar`, que doble-contaba los parciales previos). Se agregó `IF @Remaining <= 0.01` para cubrir pago exacto y sobrepago/cambio, e **idempotencia por `@Reference`** (cortocircuita si ya existe un pago con esa referencia en el folio — ver H-7). Validado en vivo sobre `avo`: 2×$7 sobre $75 → saldo $61 (no $54 del bug viejo).
- **Área:** Pagos parciales · **Categoría:** producer-logic
- **Evidencia:** `scripts/sql/01-COMPLETE-INSTALL.sql:401-403` (lee `@OrderTotal=total`), `:430-431` (`@PaidSoFar=SUM(importe)`, `@Remaining=@OrderTotal-(@PaidSoFar+@PaymentAmount)`), `:478` (`@RemainingRatio=@Remaining/@OrderTotal`), `:500-514` (`SET total=@Remaining`).
- **Problema:** la rama PARTIAL reescribe `tempcheques.total`=restante y escala `tempcheqdet.cantidad`*ratio, **perdiendo el total original del header**. En un segundo parcial, `@OrderTotal` se lee del total ya encogido (p. ej. $770 tras pagar $7 de $777) pero `@PaidSoFar` aún suma el $7 previo → `@Remaining=770-(7+7)=756` cuando el real es $763. Cada parcial doble-cuenta los anteriores; el ratio compone multiplicativamente y el pedido puede llegar a `pagado=1` antes de cubrir el total original (sub-cobro) o nunca conciliar.
- **Recomendación:** **anclar el total original una sola vez** (en `AvoqadoPartialPayments` o columna dedicada) y computar siempre `@Remaining = OriginalTotal - SUM(importe)` *después* de insertar el pago; o no reescribir `total`/`cantidad` y representar el parcial solo vía `tempchequespagos` + un `paidamount`. Test de regresión: N parciales que sumen exactamente el total original, `pagado` solo en el último. Validar en vivo con captura de dos `Payment.APPLY` consecutivos.

---

### 🟠 HIGH

#### H-1 · Item DELETE v11 emite el WorkspaceId de la ORDEN como EntityId del item
- **Área:** Modificadores/items · **Categoría:** entity-id
- **Evidencia:** `01-COMPLETE-INSTALL.sql:704-705` pasa `(SELECT WorkspaceId FROM tempcheques WHERE folio=d.foliodet)` como 5º arg; `fn_GetAvoqadoEntityIdWithWorkspace:296-313` corta el lookup si `@WorkspaceId` no es NULL y devuelve el GUID de la orden; `producer.ts:785-788` solo replica `EntityId`.
- **Problema:** CREATE/UPDATE de la línea llevan el GUID de la **línea**; el DELETE lleva el GUID de la **orden**. No coinciden → el backend no puede ubicar la línea borrada. Rompe quitar producto/modificador/curso en **toda venue v11/v12** (ruta dominante).
- **Recomendación:** en la rama DELETE pasar `d.WorkspaceId` (la propia línea borrada), no `tempcheques.WorkspaceId`. Verificar que `tempcheqdet` expone `WorkspaceId` en `deleted`. Validar en vivo: borrar una línea en avov2 y aseverar que el EntityId DELETE = `tempcheqdet.WorkspaceId` de esa línea.

#### H-2 · `numcheque` (número de cheque impreso) nunca se expone como campo de primer nivel
- **Área:** Imprimir cuenta · **Categoría:** data-fidelity
- **Evidencia:** `producer.ts:545` (V10 `orderNumber=posData.folio.toString()`), `:662` (V11 igual). `numcheque` solo en `posRawData`.
- **Problema:** `folio` (PK interno) ≠ `numcheque` (número impreso en el ticket que usa el corte). Publicar `folio` como `orderNumber` rompe conciliación, soporte y cruces fiscales. La transición impreso 0→1 también es invisible.
- **Recomendación:** agregar `posCheckNumber=posData.numcheque`, `printed=!!posData.impreso`, `printCount=posData.impresiones`. Decidir con backend si `orderNumber` debe ser `numcheque`. Confirmar en vivo que `numcheque` se puebla al imprimir y es estable hasta el pago.

#### H-3 · El producer NO tiene caso `'payment'` → eventos de pago se tragan; pagos parciales nunca llegan
- **✅ ARREGLADO (2026-06-15):** el payload de orden ahora **siempre** incluye `payments[]` (en ambas rutas `processOrderChange` v10 y `processOrderChangeV11` v11), no solo cuando `posData.pagado`; y se agregó un `case 'payment'` al `switch` del producer para no marcar procesadas las filas `payment` sin publicar. Los pagos parciales (con `pagado=0`) ya viajan al backend.
- **⚠️ Requiere además cambio en el backend (avoqado-server) para consumir `payments[]` — el producer ya los envía pero el backend no los guardaba (paidAmount=0).**
- **Área:** Pago/liquidación · **Categoría:** trigger-coverage
- **Evidencia:** `producer.ts:230-305` (switch solo order/orderitem/shift), `:308` (`succeededIds.push` para cualquier change sin handler), `:519`/`:631` (payments[] solo si `pagado`). `01-COMPLETE-INSTALL.sql:737-781` y `:525-526` emiten filas `payment`.
- **Problema:** las filas `EntityType='payment'` caen sin caso, no publican nada y se marcan `ProcessedAt`. Los pagos parciales (que dejan `pagado=0`) **nunca surfacean** un pago discreto; el `order.updated` parcial trae `total` reducido con `payments[]` vacío.
- **Recomendación:** agregar `case 'payment'` que lea `tempchequespagos` y publique `pos.{pos}.payment.{created|updated|deleted}`, **o** quitar el `if(posData.pagado)` y siempre incluir `payments[]`. No marcar procesada una fila `payment` sin handler.

#### H-4 · Supresión de DELETE de cierre de turno **inexistente en v11/v12**
> **✅ ARREGLADO (2026-06-15) — cubre H-4, H-13, H-17 (y mitiga H-5/H-12/H-16):** nueva supresión
> agnóstica de versión en `producer.ts` (helper `wasArchived` + gate antes del switch): un DELETE de
> temp* se SUPRIME si la entidad fue archivada a su tabla permanente (`cheques`/`cheqdet`/`chequespagos`
> — por WorkspaceId en v11/v12, por idturno+folio en v10). Robusto al timing: el archivo se commitea
> junto con el DELETE (misma transacción de cierre), antes de que el producer lea el tracking, así que
> NO depende del flag `AvoqadoShiftArchiving` ni de la ventana de 30s. Se eliminó el detector roto
> `closedShiftIdsInBatch` (comparaba `'UPDATE'` vs el `'CLOSED'` que emite el trigger → set siempre
> vacío). Validado en vivo en `avo`: orden archivada (en `cheques`) → DELETE **suprimido**; orden no
> archivada → DELETE **publicado**. *Pendiente opcional (no-correctitud, solo carga): optimizar el guard
> a nivel trigger para no generar miles de filas de tracking en un cierre grande (Fase 4).*
- **Área:** Pago / Cierre de turno · **Categoría:** shift-close
- **Evidencia:** `producer.ts:261-266` (rama v11 = no-op que loguea), `:581-583` (`processOrderChangeV11` DELETE→`CANCELLED` incondicional); contraste `:246-260` (v10 funciona). Único guard v11 = trigger (`01-COMPLETE-INSTALL.sql:635-647`).
- **Problema:** en v11/v12 un DELETE de `tempcheques` fuera de la ventana 30s/flag se publica como **orden CANCELADA**. Si el archivado es lento (>30s) y el POS no llamó `sp_BeginShiftArchiving`, las purgas se filtran como cancelaciones, corrompiendo ventas completadas.
- **Recomendación:** implementar la supresión v11 en `processOrderChangeV11`/pollForChanges (resolver shift de la orden y cruzar `closedShiftIdsInBatch`/turnos recién cerrados). Verificar si el cierre nativo llama `sp_BeginShiftArchiving` (probablemente no). Medir duración de archivado en vivo.

#### H-5 · `AvoqadoShiftArchiving` (guard primario) nunca se arma; solo protege el frágil fallback de 30s
- **Área:** Pago / Cierre de turno · **Categoría:** shift-close
- **Evidencia:** triggers `01-COMPLETE-INSTALL.sql:742-756/635-647/685-699`; `sp_BeginShiftArchiving` documentado como paso manual (`:853-858`); `SoftRestaurant11Adapter.ts:288-352` (`closeShift` nunca lo llama); CLAUDE.md (cierre setea `cierre` *después* del archivado). Grep: `sp_BeginShiftArchiving`/`AvoqadoShiftArchiving` no aparecen en ningún `.ts`.
- **Problema:** el cierre nativo no llama el SP; `cierre` se setea tras los DELETEs → en el momento de los DELETEs **ambos** guards están inactivos (`IsArchiving=0` y `cierre` aún NULL). Cada cierre puede filtrar DELETEs de orden/item/pago como cancelaciones.
- **Recomendación:** no depender de que el POS llame el SP. Detectar intención de cierre estructuralmente (suprimir DELETEs de órdenes `pagado=1` cuando hay `turnos` cerrándose), o tratar DELETE de orden pagada como archival por defecto exigiendo señal explícita para cancelaciones reales. Validar con captura en vivo midiendo el gap entre DELETEs y el UPDATE de `cierre`.

#### H-6 · Propina doble-contada / no separada de `importe`
- **Área:** Pago/liquidación · **Categoría:** producer-logic
- **Evidencia:** `01-COMPLETE-INSTALL.sql:430-431` (`@PaidSoFar=SUM(importe)`, restante usa importe crudo), `:443-444` (`importe=@PaymentAmount`, `propina=@TipAmount`, sin resta); contraste `04-Native-Payment-Flow.sql:223` (`importe=@PaymentAmount-@TipAmount`).
- **Problema:** si `@PaymentAmount` incluye propina, `importe` se infla, `@PaidSoFar` sobre-cuenta y el restante se subestima → cierre prematuro/subcobro en split tender. El FULL nunca escribe `propina/propinatarjeta/totalconpropina` en `tempcheques` → corte de caja descuadra para órdenes pagadas por Avoqado.
- **Recomendación:** definir el contrato (monto solo bienes vs bienes+propina) y restar propina al computar `importe`/restante si aplica. Poblar buckets de propina en el header en la rama full. Validar contra pago nativo.

#### H-7 · Escalado de cantidades en parcial es destructivo y NO idempotente
- **✅ ARREGLADO (2026-06-15):** `sp_ApplyPartialPayment` es ahora idempotente por `@Reference`: al inicio cortocircuita (sin insertar pago ni reescalar items) si ya existe un pago con esa referencia en el folio, por lo que un `Payment.APPLY` redelivered (RabbitMQ at-least-once) ya no inserta pagos fantasma ni vuelve a encoger cantidades/total. Además dejó de re-derivar el restante del total mutado (ver C-1).
- **Área:** Pago/liquidación · **Categoría:** idempotency
- **Evidencia:** `01-COMPLETE-INSTALL.sql:401-403` (re-lee `@OrderTotal` del total mutado), `:486-514` (escalado in-place), `:443` (INSERT pago sin dedupe por `@Reference`); `commander.ts:77,134` (ack tras retornar → redelivery en crash).
- **Problema:** RabbitMQ es at-least-once. Un `Payment.APPLY` redelivered inserta un SEGUNDO pago, escala items otra vez y re-deriva `total` del total ya reducido → corrompe cantidades/total y crea pagos fantasma. Un blip de red duplica la reducción.
- **Recomendación:** hacer `sp_ApplyPartialPayment` idempotente con clave única (de `@Reference` o `@PaymentExternalId`): cortocircuitar si ya existe ese pago en el folio. Nunca re-derivar `@OrderTotal` del total mutado.

#### H-8 · FastPayment no escribe WorkspaceId → venta perdida en v11
- **Área:** Venta rápida / Pago · **Categoría:** entity-id
- **Evidencia:** `SoftRestaurant11Adapter.ts:createFastPayment` (INSERTs de tempcheques/tempcheqdet/tempchequespagos sin WorkspaceId); `fn_GetAvoqadoEntityIdWithWorkspace:296-324`; `producer.ts:441-443` + `:591` (bind `sql.UniqueIdentifier`).
- **Problema:** si `WorkspaceId` es NULL (sin DEFAULT), el entity-id cae a formato v10 con dos puntos; el producer en modo v11 lo bindea como GUID, el SELECT lanza, el catch devuelve null y **la venta (dinero real) se descarta** en cada venue v11/v12. Si hay DEFAULT, item y pago obtienen GUIDs distintos sin relación documentada.
- **Recomendación:** generar y escribir `WorkspaceId` (uuidv4) explícitamente en los 3 INSERTs de `createFastPayment`, como hace `createEmptyOrder`. Verificar en v11 que se publican y resuelven order/orderitem/payment. No asumir DEFAULT.

#### H-9 · `addItemToOrder` omite WorkspaceId en el INSERT de tempcheqdet
- **Área:** Items · **Categoría:** entity-id
- **Evidencia:** `SoftRestaurant11Adapter.ts:61-77` (INSERT sin WorkspaceId); `01-COMPLETE-INSTALL.sql:302` (entity-id orderitem lee `tempcheqdet.WorkspaceId`); `producer.ts:703-707` (rechaza id no-1-parte en v11).
- **Problema:** si la línea nueva tiene WorkspaceId NULL, el evento de alta de item v11 se descarta (id "inválido"/irresoluble) aunque la fila POS se escribió. Las altas nativas (que sí setean WorkspaceId) enmascaran el bug en pruebas.
- **Recomendación:** setear `WorkspaceId=NEWID()`/uuidv4 en el INSERT de `addItemToOrder`. Capturar alta nativa para confirmar si SoftRestaurant setea `tempcheqdet.WorkspaceId` y si existe DEFAULT.

#### H-10 · `cancelOrderItem` no recalcula totales del header tras borrar la línea
- **Área:** Items · **Categoría:** producer-logic
- **Evidencia:** `SoftRestaurant11Adapter.ts:129-181` (DELETE sin UPDATE de totales; comentario erróneo L175 "el trigger los recalculó"); `01-COMPLETE-INSTALL.sql:702-717` (el trigger solo escribe tracking); `producer.ts:548-552` (payload lee totales verbatim).
- **Problema:** tras anular un item, `tempcheques` mantiene totales pre-cancel. El trigger igual encola un `order` UPDATE → el producer republica un `order.updated` con total **más alto** que la suma de los items restantes. Corrompe total/tax/reportes.
- **Recomendación:** tras el DELETE, ejecutar el mismo UPDATE de totales por SUM que usa `addItemToOrder` (manejando orden vacía → totales 0). Quitar el comentario. Capturar void nativo para espejar columnas.

#### H-11 · Movimientos de caja (retiro/depósito) son un blind spot total
- **Área:** Caja · **Categoría:** trigger-coverage
- **Evidencia:** `01-COMPLETE-INSTALL.sql` (4 triggers, ninguno en tabla de caja); grep `movimientoscaja/movcaja/retiro/deposito` = 0 hits en `src/` y `scripts/sql/`.
- **Problema:** retiros/depósitos mutan el POS invisiblemente. La conciliación de efectivo (esperado = fondo + ventas efectivo ± movimientos) es imposible: Avoqado tiene fondo y ventas pero no movimientos.
- **Recomendación:** confirmar el nombre real de la tabla en vivo (depósito 333.33, retiro 222.22 con `npm run monitor`), agregar `Trg_Avoqado_CashMovement` + EntityType `cashmovement` + caso en producer. Mientras tanto, documentar que no se sincroniza y que la conciliación depende solo de los totales declarados en `turnos`.

#### H-12 · `closeShift` no arma archivado y borra temp* ANTES de setear `cierre`
- **Área:** Cancelaciones / Cierre · **Categoría:** shift-close
- **Evidencia:** `SoftRestaurant11Adapter.ts:288-352` (DELETEs L316-329 preceden a UPDATE `cierre` L341; sin `sp_BeginShiftArchiving`); guards `01-COMPLETE-INSTALL.sql:635-647/685-699/742-756`.
- **Problema:** al ejecutar los DELETEs, `IsArchiving` no existe y `cierre` aún es NULL → ningún guard corta. Todos los items/pagos/órdenes del turno se emiten como **CANCELLED**. Si Avoqado conduce el cierre (`Shift.CLOSE`), cada venta liquidada se mis-sincroniza como cancelada.
- **Recomendación:** llamar `sp_BeginShiftArchiving` tras `begin()` y `sp_EndShiftArchiving` tras `commit()`; o setear `cierre` antes de los DELETEs. Endurecer el fallback del trigger para suprimir cuando el turno está cerrándose aun sin `cierre`.

#### H-13 · Supresión producer-side de DELETE de orden es no-op en v11 (defensa en profundidad ausente)
- **Área:** Cancelaciones / Cierre · **Categoría:** shift-close
- **Evidencia:** `producer.ts:246-267` (v10 vía split[1]; v11 solo comentario), `:575-583` (`processOrderChangeV11` DELETE→CANCELLED sin check).
- **Problema:** la segunda red de seguridad existe solo para v10 (la menos usada). En v11/v12 cualquier DELETE archival que escape al trigger se publica como cancelación real sin respaldo.
- **Recomendación:** implementar la supresión v11 espejando v10 (resolver idturno de la orden / consultar si su turno cerró en el batch). Como el id v11 es el WorkspaceId y la fila pudo borrarse, capturar idturno en el contexto de tracking.

#### H-14 · Cancelación whole-order se publica como `order.updated` (sin tipo cancelled/void) y puede coalescerse/perderse
- **Área:** Cancelaciones · **Categoría:** producer-logic
- **Evidencia:** `producer.ts:234-236` (todo UPDATE → `debounceAndSendOrderUpdate` → `order.updated`), `:546/:663` (status=CANCELLED solo en payload), `:489-491/:594-597` (re-read null → no publica).
- **Problema:** no hay routing key de cancelación; un consumidor por routing key no distingue void de edición. Peor: si el cierre/archival borra la fila dentro de los 2.5s del debounce, el re-read devuelve null y **la cancelación se descarta silenciosamente**.
- **Recomendación:** detectar transición `cancelado` y publicar evento distinto. Cuando el re-read del debounce devuelva null, publicar DELETE/CANCELLED con el último payload conocido en vez de retornar null.

#### H-15 · Tablas de auditoría de cancelación (`cancela`/`tempcancela`, `bitacorasistema`) sin trigger → razón y autorización nunca llegan
- **Área:** Cancelaciones · **Categoría:** trigger-coverage
- **Evidencia:** `01-COMPLETE-INSTALL.sql:628-828` (4 triggers; grep cancela/bitacora = 0); `SoftRestaurant11Adapter.ts:156-171` (cancelOrderItem escribe tempcancela + bitacorasistema).
- **Problema:** razón de cancelación y supervisor autorizante (señales clave de prevención de pérdidas) son **estructuralmente inalcanzables** — el payload no tiene campos razon/usuario.
- **Recomendación:** AFTER INSERT trigger en `tempcancela`/`cancela` que escriba un EntityType `cancellation` (foliocheque, movimiento, razon, usuario, cantidad, precio) + rama en producer + routing key `pos.softrestaurant.cancellation.created`. Confirmar tabla/columnas reales con captura.

#### H-16 · Cierre lento (>30s) en venue cargada filtra DELETEs como cancelaciones
- **Área:** Cierre de turno · **Categoría:** shift-close
- **Evidencia:** guards 30s en los 3 triggers; CHANGELOG-v2.5.0:58-78 (la ventana de 30s no es fiable >500 órdenes); SQL Express 32-bit lento.
- **Problema:** el flag (que cubriría archivados largos) nunca se arma → solo la ventana de 30s protege. Un cierre cuyo borrado supere 30s emite eventos `deleted` espurios para órdenes/items/pagos de un turno normal.
- **Recomendación:** ver H-5/H-13. Hacer la ventana configurable o suprimir cualquier DELETE de temp* para un turno cuyo `turnos.cierre IS NOT NULL` sin importar el elapsed. Diagnóstico que alerte cuando el archivado exceda la ventana.

#### H-17 · Items/pagos DELETE en cierre no suprimidos por el producer (solo órdenes v10)
- **Área:** Caja / Cierre · **Categoría:** edge-case
- **Evidencia:** `producer.ts:245-267` (supresión solo en caso 'order' y solo v10); caso 'orderitem' `:277-285` (siempre inmediato); `processOrderChangeV11:581-582` (DELETE→CANCELLED sin check).
- **Problema:** items y pagos no tienen red en ningún caso; órdenes v11 tampoco. En DBs v11/v12 el guard del trigger es lo ÚNICO entre un cierre lento y una ola de cancelaciones/borrados falsos.
- **Recomendación:** hacer la supresión de DELETE de temp* agnóstica de entidad y versión: antes de emitir deleted/CANCELLED, resolver idturno del padre y chequear `turnos.cierre`/flag. Preferir resolverlo en la capa de trigger (flag durable).

#### H-18 · `closeShift` archivalQueries son placeholders (`...`) → el cierre vía Avoqado no archiva
- **Área:** Caja / Cierre · **Categoría:** adapter
- **Evidencia:** `SoftRestaurant11Adapter.ts:303-308` (`INSERT INTO cheques (...) SELECT ...` literal); DELETEs L316-329; `commander.ts:99-110` (Shift.CLOSE → closeShift).
- **Problema:** el SQL no es T-SQL válido → lanza, rollback, el turno no cierra. Si los `...` se "rellenaran" mal, los DELETEs borrarían órdenes/pagos activos sin haberlos copiado a cheques. Comando alcanzable en producción.
- **Recomendación:** quitar/proteger la ruta `Shift.CLOSE→closeShift` hasta implementarla (lanzar NOT_IMPLEMENTED para que vaya a DLQ), o implementar el archivado columna-exacto contra el esquema real antes de cualquier DELETE. El POS nativo debe seguir siendo la fuente de verdad del cierre.

---

### 🟡 MEDIUM / 🔵 LOW — selección de hallazgos relevantes

**Apertura de turno**
- `openShift` calcula `idturno` con `MAX(idturno)+1` sin lock → colisión/race con el POS nativo o comandos concurrentes (idturno es clave de negocio en todos los entity-id y joins). [MEDIUM, entity-id]
- `openShift` escribe set parcial de columnas (idempresa='1' hardcode, idmesero='', sin caja/serie/numturno). [MEDIUM, adapter]
- `shiftData.staffId` se lee de `idmesero` pero `openShift` lo deja vacío → staffId vacío en aperturas Avoqado. [MEDIUM, data-fidelity]
- `parametros.ultimoturno` UPDATE sin WHERE (toca todas las filas) y puede no ser el contador que lee el POS. [MEDIUM, adapter]
- `openShift` no verifica si ya hay turno abierto antes de insertar otro (`cierre IS NULL`). [MEDIUM, edge-case]
- **Trg_Avoqado_Shifts emite OPENED espurio** en cualquier UPDATE que deje `cierre` NULL (no une `deleted`) → republica `shift.created` para un turno existente. [MEDIUM, trigger-coverage]

**Abrir cuenta / items**
- Guard de ocupación es **TOCTOU** (SELECT fuera de tx, sin lock) e inconsistente con el POS (no toca `mesas`/`mesasasignadas`). [MEDIUM, edge-case]
- UPDATE de totales=0 **post-commit fuera de tx** → fila a medio inicializar visible + segundo trigger (order.updated redundante). [MEDIUM, data-fidelity]
- `createEmptyOrder` hardcodea `idarearestaurant='01'`, `idempresa='1'`, ignora `posAreaId` → areaData/empresa erróneos en venues sin área '01'. [MEDIUM, data-fidelity]
- `addItemToOrder` hardcodea IVA 16% (`preciosinimpuestos=precio/1.16`, `impuesto1=16.00`) sin mirar config de impuestos del producto. [MEDIUM, data-fidelity]
- `cancelOrderItem` INSERT a `bitacorasistema` con `...` literal → lanzaría y haría rollback de todo el void (código muerto hoy). [LOW, adapter]
- Cursor durable (`syncCursor.ts`) se carga/guarda pero **nunca se usa** para filtrar; `sp_GetPendingChanges` solo filtra `ProcessedAt IS NULL`. La doc sobrevende "dos capas de durabilidad". [LOW, idempotency]

**Modificadores / nivel cuenta**
- `discountAmount` por item se publica pero **no se resta** del `total` de línea; ambiguo y posible doble-conteo. [MEDIUM, data-fidelity]
- `taxAmount` por item es **por unidad** (`precio-preciosinimpuestos`) pero `total` es por línea (`precio*cantidad`) → tax mal para `cantidad>1`. [MEDIUM, data-fidelity]
- `nopersonas` e `idcliente` no mapeados a campos dedicados (solo posRawData). [MEDIUM, data-fidelity]
- En v10, el entity-id de orden cambia al transicionar idturno 0→real → rompe coalescing del debounce y crea dos claves para una orden lógica. [MEDIUM, entity-id]

**Pago / parciales**
- `sp_GetPendingChanges` ordena `ORDER BY Timestamp ASC` **sin desempate por Id** → empates al milisegundo reordenan/starvan; filas con `RetryCount>=5` se excluyen para siempre sin alerta. [MEDIUM, ordering-timing]
- Rama full no escribe buckets `efectivo/tarjeta/vales/otros/propina/cambio` → descuadre de corte. [MEDIUM, data-fidelity]
- `cambio` se calcula pero no se persiste; en full el adapter reporta change undefined. [MEDIUM, data-fidelity]
- `Trg_Avoqado_Payments` usa entity-id de pago **por folio** (`TOP 1 WorkspaceId ORDER BY DESC`) → múltiples tenders colapsan a un id; DELETE puede resolver a otro pago. [MEDIUM, entity-id]
- Resolución v11 de folio `TOP 1 ... ORDER BY folio DESC` puede pagar la orden equivocada si un WorkspaceId mapea a varios folios (split). [MEDIUM/LOW, entity-id]
- `04-Native-Payment-Flow.sql` deprecado: variante divergente (mis-mapea método, omite WorkspaceId) — descartar en clientes que la corrieron. [INFO, data-fidelity]

**Imprimir / FastPayment**
- FastPayment asigna `numcheque` por `MAX(numcheque)` del turno (no `folios.ultimofolio`) → numeración divergente y colisión concurrente. [MEDIUM, adapter]
- FastPayment: línea única tax-inclusive con `impuesto=0` mientras `addItemToOrder` parte 16% → tax=0 reportado para ventas rápidas. [MEDIUM, data-fidelity]
- FastPayment interpola `idturno` en SQL (no parámetro); `MAX(numcheque)+1` sin lock. [LOW, adapter]
- `numcheque`/`impreso` solo en posRawData; impresión nativa standalone no distinguible. [LOW, edge-case]

**Cierre / contexto**
- Detector de turnos cerrados del producer compara `Operation.includes('UPDATE')` pero el trigger emite `'CLOSED'` → `closedShiftIdsInBatch` **siempre vacío** (la supresión v10 nunca dispara). [MEDIUM, shift-close]
- En v11, `closedShiftIdsInBatch` usa `parseInt(EntityId)` sobre un GUID → NaN, salta todo cambio de shift. [MEDIUM, entity-id]
- Trg_Avoqado_Shifts solo AFTER INSERT,UPDATE (no DELETE) pero el producer tiene rama DELETE de shift → cobertura contradictoria/muerta. [MEDIUM, trigger-coverage]
- Guards de OrderItems/Payments resuelven idturno vía `tempcheques`; si el padre ya se borró, el JOIN no encuentra y el guard no corta. [MEDIUM, shift-close]
- `turnos.otros` (otherDeclared) se acepta pero no se escribe en `closeShift`. [MEDIUM, adapter]
- Totales declarados solo en posRawData, no como campos tipados de `shift.closed`. [MEDIUM, data-fidelity]

**Transversales / completitud**
- **Catálogos** (productos, formasdepago, meseros, areasrestaurant, mesas, clientes) **nunca se sincronizan** POS→plataforma (sin trigger ni evento). El MCP expone set_menu_item_price/create_product etc. asumiendo un modelo autoritativo que el bridge no mantiene. [MEDIUM, trigger-coverage]
- Errores de trigger se marcan `RetryCount=99`/`Operation='ERROR'` y `sp_GetPendingChanges` los excluye (`RetryCount<5`) → **pérdida silenciosa** de un cambio sin alerta. [MEDIUM, data-fidelity]
- `folio` se bindea como `sql.Int` en varios lookups del producer mientras `tempcheques.folio` es BIGINT → overflow potencial en venues de alto volumen/split. [LOW, data-fidelity]
- Riesgo de deadlock/agotamiento de pool entre el poll de 2s (N×5 round-trips por cambio) y las tx de escritura del POS en SQL Express 32-bit; sin timeout/retry de deadlock visible. [MEDIUM, ordering-timing]
- Código muerto: `createSplitOrder/splitOrderItems/adjustOrderItemQuantities/updateParentOrderTotal/insertPaymentToPOS/markOrderAsPaid/trackPartialPayment` y tabla `AvoqadoPartialPayments` (no escrita en runtime). Docs referencian funciones inexistentes (`fn_CanCompleteOrderPayment`, `sp_AddPartialPayment`, `analysis/db/`). [LOW, other]
- `AvoqadoDebugLog` crece sin poda (`sp_CleanupOldTrackingRecords` solo toca `AvoqadoTracking`). [LOW, other]

---

## 6. Plan de captura en vivo

> Checklist accionable por la UI del POS, agrupado por área, para validar todo lo marcado `needs-live`/`domain-inferred`. En todos: iniciar Extended Events / `npm run monitor` **antes** de actuar, filtrado a la DB del POS (test: `avov2` @ `100.80.118.68,49759`). Repetir en v11/v12 y, de ser posible, en true-v10.

### Apertura de turno
- [ ] **Apertura nativa**: Apertura de caja (fondo, estación, cajero). Tablas: `turnos` (columnas, idturno, WorkspaceId), `folios`, `parametros`/`parametros2`, `cajas`, `AvoqadoTracking`.
- [ ] **Verificar OPENED único + formato id**: tras apertura, `SELECT TOP 20 ... FROM AvoqadoTracking WHERE EntityType='shift'`. Luego editar el turno abierto (fondo/cajero) y confirmar si aparece un SEGUNDO OPENED. Tablas: `AvoqadoTracking`, `turnos`, `AvoqadoConfig`.
- [ ] **Apertura vía Shift.OPEN**: publicar comando; confirmar `idturno=MAX+1`, columnas, `parametros.ultimoturno`. Tablas: `turnos`, `meseros`, `parametros`, `AvoqadoTracking`.
- [ ] **Publish end-to-end**: log `shift.created`, payload, `ProcessedAt`. Tablas: `AvoqadoTracking`, `turnos`.

### Abrir cuenta/mesa (F7)
- [ ] **Alta nativa F7** (sin productos): `INSERT tempcheques` (¿idturno 0 o real?, idarearestaurant/idempresa/estacion/seriefolio/WorkspaceId), `folios`, `mesas`/`mesasasignadas`, `PRODUCTOSENPRODUCCION`, límite tx. Tablas: `tempcheques`, `folios`, `mesas`, `mesasasignadas`, `turnos`, `AvoqadoTracking`.
- [ ] **Emisión del trigger**: confirmar 1 (o 2 vía Avoqado) filas order/CREATE y formato EntityId.
- [ ] **Publish order.created**: status='CONFIRMED', total=0, shiftData via fallback idturno=0.
- [ ] **idturno=0→real es en pago**: `SELECT folio,idturno,pagado` antes y después de pagar.
- [ ] **Guard de ocupación + TOCTOU**: segundo Order.CREATE en misma mesa; dos concurrentes.

### Items / modificadores / tiempos
- [ ] **Alta nativa de item**: lista completa de columnas (¿WorkspaceId, comanda, impuesto1/2/3, idproductocompuesto, preciocatalogo?) y UPDATE de totales.
- [ ] **2-3 items rápidos**: secuencia de `movimiento`, una fila orderitem + una order/UPDATE por folio.
- [ ] **Cambio de cantidad nativo**: ¿UPDATE cantidad vs DELETE+INSERT? ¿precio escala?
- [ ] **Void nativo de línea**: secuencia DELETE + `tempcancela` (columnas razón/usuario) + `productosenproduccion` + `bitacorasistema` + **si recalcula totales**.
- [ ] **Encogimiento por pago parcial**: UPDATE cantidad*ratio (todas), header rewrite, `AvoqadoDebugLog`.
- [ ] **Supresión en archivado de items**: `sp_BeginShiftArchiving` → DELETE → confirmar NO tracking → `sp_EndShiftArchiving`.
- [ ] **Comentario, descuento (% y monto), override de precio, modificadores (con/sin precio), tiempo/curso**: columnas escritas en `tempcheqdet`, header, y qué llega solo en posRawData.
- [ ] **v10 vs v11 entity-id de item**: GUID vs `Instance:Turno:Folio:Mov`.

### Nivel cuenta
- [ ] **Descuento de cuenta** (% y monto): columnas `tempcheques` (descuento/descuentoimporte/...), confirmar `discountAmount=descuentoimporte`.
- [ ] **Propina de cuenta** vs propina de pago (header vs `tempchequespagos`).
- [ ] **Comensales / cliente / mesero**: validar que `nopersonas`/`idcliente` solo viajan en posRawData; mesero re-resuelto vía `meseros`.
- [ ] **Debounce coalescing**: 3 cambios en ~2s → un solo `order.updated`; edición durante ventana de archivado.

### Dividir/juntar/transferir/cambiar mesa
- [ ] **Cambiar mesa**: columnas de `tempcheques`, `mesas`/`mesasasignadas`.
- [ ] **Dividir**: INSERT hija (sufijo mesa, WorkspaceId fresco?), cómo se mueven items (re-point vs delete+insert), `folios`.
- [ ] **Juntar**: mover items B→A, DELETE de B, confirmar `order.deleted`/CANCELLED para B.
- [ ] **Transferir item**: re-point foliodet, continuidad de WorkspaceId en v11.

### Imprimir
- [ ] **Imprimir nativo**: `folios` (TABLOCKX), `tempcheques` (impreso/numcheque/cierre/impresiones/seriefolio), `folios` UPDATE, `cuentas`, límite tx, fila order/UPDATE.
- [ ] **Qué publica el producer**: routing key order.updated (no print key), impreso/numcheque solo en posRawData.
- [ ] **FastPayment numcheque source**: `MAX(numcheque) per turno` vs folios; confirmar folios.ultimofolio NO avanza.

### Pago / parciales
- [ ] **Pago full vía Avoqado**: EXEC sp_ApplyPartialPayment y cada statement interno.
- [ ] **Parcial → split tender**: parcial (7 de 777), luego resto; **verificar si el 2º lee total encogido y si SUM(importe) concilia con el original** (C-1/H-7).
- [ ] **Sobrepago/cambio**: `@Remaining` negativo, full sin escribir `cambio`.
- [ ] **Propina en tarjeta**: `propina=@TipAmount`, importe NO reducido (H-6).
- [ ] **WorkspaceId-por-pago + archivado v11**: `99-SHIFT-CLOSE-DIAGNOSTIC.sql` secciones 5/6/7, cerrar turno, confirmar supresión de `Trg_Avoqado_Payments`.
- [ ] **Pago nativo en caja** (la captura de mayor valor): INSERT `tempchequespagos` + UPDATE `tempcheques` (buckets/propina/cambio/usuariopago), `folios` numcheque.
- [ ] **FastPayment**: 10 statements; verificar **sin WorkspaceId, propina=0** (H-8); comportamiento en archivado.
- [ ] **Publicación de parcial**: confirmar que NO se emite `payment.*` y que payments[] está vacío con pagado=0 (H-3).
- [ ] **v10 vs v11 resolución de folio** desde externalId.

### Cancelaciones
- [ ] **Cancelar item real (turno abierto)**: tabla audit real (`cancela` vs `tempcancela`) + columnas razón/auth; confirmar que NO se propagan (H-15).
- [ ] **Cancelar cuenta (antes de imprimir)**: `cancelado=1` (fila permanece) → status CANCELLED.
- [ ] **Anular tras impresión**: `cancelado=1` con impreso=1; diferenciar de pre-print.
- [ ] **Archival DELETE vs cancelación (prueba de supresión)**: corte Z; confirmar NO filas order/item/payment DELETE y exactamente una shift CLOSED; si el cierre no llama `sp_BeginShiftArchiving`, notar timing del fallback 30s; repetir v11 y v10.

### Caja
- [ ] **Depósito 333.33** / **Retiro 222.22**: nombre real de la tabla, columnas, confirmar **0 filas en AvoqadoTracking**.
- [ ] **Corte X**: confirmar solo SELECTs, `turnos.cierre` NULL, 0 tracking.
- [ ] **Corte Z**: secuencia implicit_transactions completa; qué columnas reciben efectivo declarado (incl. `otros` y posible tabla de denominaciones); fila shift CLOSED.

### Cierre de turno (a fondo)
- [ ] **Cierre nativo completo**: column lists de `cheques/cheqdet/chequespagos`; tablas aux reales; **confirmar UPDATE `cierre` ANTES de DELETE temp***; `mesas`/`PRODUCTOSENPRODUCCION`/`folios`; confirmar una sola tx. **Commit del trace a `info-softrest11/sql-traces`**.
- [ ] **Comportamiento de triggers en cierre**: una shift CLOSED, cero order/item/payment DELETE; medir duración vs 30s; probar la ruta del flag manualmente.
- [ ] **Estrés de turno grande (500+ órdenes)**: ¿filas DELETE espurias tras el segundo 30?
- [ ] **Gap v11/v12 de supresión de order-delete**: forzar order DELETE en el mismo batch que shift CLOSED; confirmar fuga (rama v11 no-op).
- [ ] **Shift.CLOSE vía Commander** (DB desechable): confirmar que los placeholders fallan/rollback.

### Venta rápida / Domicilio
- [ ] **F9 nativo**: columnas de tempcheques (tipoventarapida/tipodeservicio/mesa/idturno), impreso/numcheque, WorkspaceId por pago, una tx.
- [ ] **FastPayment.CREATE**: 10 statements; confirmar publish order.created + order.updated/payment en ~3s.
- [ ] **F8 nativo (captura de alto valor)**: identificar tipodeservicio de delivery, dónde viven teléfono/dirección/repartidor/estado, si los cambios de estado tocan `tempcheques` o tabla auxiliar no observada, idturno en alta vs pago.
- [ ] **Create→pay ajustado**: Order.CREATE + 2×OrderItem.CREATE + Payment.APPLY en ~1s; observar debounce 2.5s y reasignación idturno=0.

### CFDI
- [ ] **Facturar venta PAGADA antes del corte**: ¿se UPDATEa `tempcheques` (facturado/folio fiscal)? ¿o solo `facturas/foliosfacturas/cheques`? Confirmar si surge fila order/UPDATE y publish.
- [ ] **Capturar shapes fiscales**: `foliosfacturas` (serie, ultimofolio, tipoesquema, electronico, WorkspaceId), `facturas` (UUID/RFC/uso), qué UPDATE setea facturado; repetir v11 y v10.
- [ ] **Facturar venta ya archivada**: confirmar que solo toca `cheques/facturas/foliosfacturas` y **0 tracking** (blind spot limpio).

---

## 7. Veredicto de blindaje

### ✅ Lo que está sólido
- **Durabilidad de entrega (at-least-once)**: `sp_GetPendingChanges` filtra `ProcessedAt IS NULL`; el producer marca procesado **solo tras publish confirmado** (`producer.ts:103-107`, `:308-317`); guard anti-solapamiento (`isPollInProgress`) y defer cuando RabbitMQ no está conectado.
- **Fix de archivado de pagos (canónico)**: `sp_ApplyPartialPayment` usa `@PaymentMethod` y el `WorkspaceId` de la ORDEN en el INSERT del pago (`:443-444`) — corrige el bug histórico ACASH+NEWID (`PAYMENT-ARCHIVING-FIX.md`). Archivado join por **folio** tolera mismatch de WorkspaceId.
- **Reasignación idturno=0 → turno abierto** en pago, con rollback limpio si no hay turno abierto.
- **Triggers set-based** (FULL OUTER JOIN inserted/deleted) — correctos en operaciones multi-fila; `Trg_Avoqado_Shifts` correctamente sin guard de archivado en la rama de cierre.
- **Debounce de order.updated** (last-write-wins, re-lee fila fresca) — fidelidad del estado final.

### ❌ Lo que NO está sólido
- **Pagos parciales (C-1, H-6, H-7)**: aritmética destructiva, propina doble-contada, sin idempotencia. **Dinero en riesgo.**
- **Cierre de turno en v11/v12 (H-4, H-5, H-12, H-13, H-16, H-17 + el detector roto que compara `'UPDATE'` cuando el trigger emite `'CLOSED'`)**: el flag primario nunca se arma, el fallback de 30s falla por el orden de operaciones, y la red producer-side es v10-only. **Ventas completas pueden publicarse como canceladas.**
- **Identidad de entidades v11 (H-1, H-8, H-9)**: item DELETE con WorkspaceId de la orden; FastPayment y addItemToOrder sin WorkspaceId → eventos perdidos o irresolubles en la ruta dominante.
- **Eventos de pago (H-3)**: el producer no tiene caso `payment`; parciales invisibles al backend.
- **Caja (H-11)**: retiros/depósitos sin sincronizar — conciliación de efectivo imposible.
- **Fidelidad de payload**: `numcheque` (H-2), comensales/cliente/modificadores/tiempo no mapeados; tax por unidad vs línea; IVA hardcodeado 16%.
- **Cancelaciones**: motivo/autorización inalcanzables (H-15); merge publicado como CANCELLED.

### Siguientes pasos priorizados

1. **Arreglar C-1** (parcial destructivo) y **H-7** (idempotencia de pago) — anclar total original + clave de dedupe. *Bloqueante de dinero.*
2. **Blindar cierre de turno en v11/v12**: implementar supresión v11 (H-4/H-13/H-17), corregir el detector `'CLOSED'` vs `'UPDATE'`, y dejar de depender del flag no-armado (H-5/H-12/H-16) — suprimir DELETE de temp* cuando `turnos.cierre IS NOT NULL` para ese idturno. *Bloqueante de integridad de ventas.*
3. **Arreglar entity-id v11**: H-1 (item DELETE = WorkspaceId de la línea), H-8 y H-9 (escribir WorkspaceId en FastPayment y addItemToOrder).
4. **Eventos de pago (H-3)** + propina (H-6) + exponer `numcheque`/buckets (H-2).
5. **Captura en vivo del cierre nativo y de movimientos de caja** (§6) — commitear traces a `info-softrest11/sql-traces` para anclar todo lo `domain-inferred`, y decidir cobertura de caja (H-11) y de catálogos.
6. **Limpieza**: añadir `ORDER BY Timestamp ASC, Id ASC` a `sp_GetPendingChanges`; alertar filas `RetryCount=99`/error; bindear `folio` como BigInt; eliminar/cuarentenar código muerto y `Shift.CLOSE` no funcional (H-18); podar `AvoqadoDebugLog`.

> Cada cambio que toque esquema/SP/trigger debe replicarse en los 5 scripts SQL (`01-COMPLETE-INSTALL`, `00-CLEANUP-ALL`, `00-VERIFICATION`, `02-TESTING`, `03-DIAGNOSTICS`) y en la documentación (CLAUDE.md / AGENTS.md / master docs), por las reglas del repo.

---

## 8. Validación en vivo (2026-06-15) — captura real de la UI contra `avo`

Se manejó el **SoftRestaurant 12 real** (empresa TESTARUDO, DB `avo` = copia de producción, vía Tailscale por nombre de instancia `100.118.85.117\NATIONALSOFT`) **como mesero**, con captura **Extended Events** del SQL emitido. Esto cierra el hueco de que el repo no tiene traces reales (§2).

### ✅ Confirmado en vivo
- **C-1 (CRITICAL) — reproducido con números reales.** 2 pagos parciales de $7 sobre una cuenta de $75 vía `sp_ApplyPartialPayment`: el header `total` derivó **75 → 68 → 54** y `@Remaining` reportó **$54** cuando lo realmente restante era **$61**. Doble-conteo de $7 ⇒ la orden se cerraría cobrando **$68 de $75 (–$7)**. La `cantidad` del item se corrompió (1.0 → 0.72). **Bug de dinero confirmado.**
- **idturno = 0 → real.** La cuenta nativa (F7) nació con `idturno=0`; el SP la reasignó al turno abierto **304** en el primer pago. Confirma `SOFTRESTAURANT_ENTITY_RESOLUTION`.
- **H-3 (eventos de pago tragados).** Los parciales generaron **4 filas `payment` CREATE** en `AvoqadoTracking`; el producer (sin `case 'payment'`) las marcaría procesadas sin publicar → **nunca llegan al backend.**
- **Los triggers disparan con la UI real** (no solo con SQL a mano): abrir cuenta + 1 item = `order CREATE` + **7× `order UPDATE`** + `orderitem CREATE`, cada entidad con su **propio WorkspaceId**. El alud de 7 UPDATEs **justifica el debounce de 2.5s** (y el riesgo de coalescing H-14).

### 🔽 Corregido (la data real bajó severidad)
- **H-8 (era CRITICAL) y H-9 → LOW.** Se confirmó `DEFAULT (newid())` en la columna `WorkspaceId` de `tempcheques`, `tempcheqdet`, `tempchequespagos` y `turnos`. El INSERT nativo de SoftRestaurant **no** escribe `WorkspaceId` y aun así la fila obtiene GUID. ⇒ que el adapter (FastPayment / addItemToOrder) omita `WorkspaceId` **NO pierde la venta** en v11/v12 — el default lo cubre. *(Sigue siendo buena práctica setearlo explícito, y verificar que el default exista en el script de instalación y en DBs de clientes con esquemas viejos.)*

### 📄 SQL nativo capturado (verdad de campo)
**Abrir cuenta (F7)** = `INSERT INTO tempcheques(seriefolio,numcheque,fecha,cierre,mesa,nopersonas,idmesero,pagado,impreso,impresiones,...,idarearestaurant,idempresa,tipodeservicio,idturno,...,estacion,...,Usuarioapertura,desc_porc_original)` con **`idturno=0`**, **sin `WorkspaceId`** (default `newid()`), `folio` auto (IDENTITY), `tipodeservicio=1`, `estacion='ALIEN'`; **totales en un `UPDATE` separado** post-insert; lock de aplicación vía `cuentaenuso=1/0`.
**Agregar producto** = fila `tempcheqdet`: `idproducto`, `cantidad`, `precio` (con IVA), `preciosinimpuestos` (= precio/1.16), `impuesto1=16`, `idestacion='ALIEN'`, **WorkspaceId propio** (≠ al de la orden).

### ⏳ Pendiente de captura en vivo
Pago **nativo** en caja (requiere imprimir la cuenta primero → `impreso=1`/`numcheque`), **cierre de turno** (H-4/H-5, el más grave), **cancelación nativa** (`cancela`/`tempcancela`, H-15) y el **chain completo** producer→RabbitMQ→backend (reiniciar el servicio apuntando a `avo`).
