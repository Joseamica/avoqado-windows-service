Now I have full confirmation of the key facts. I'll write the comprehensive audit document in Spanish.

# SoftRestaurant — Blindaje de la dirección Avoqado→POS (Commander/adapter)

> Auditoría de la dirección **EXECUTE** (Avoqado TPV/app/backend → SoftRestaurant local): el Comandante que consume comandos de `pos_commands_exchange` y el adaptador de POS que los ejecuta. NO cubre la dirección observe/producer.
> Repo canónico: `C:\Dev\Avoqado\avoqado-windows-service`. Lente rector: **"a prueba de errores"** (correctitud, completitud, atomicidad, manejo de fallos, idempotencia, compatibilidad v10/v11/v12, hardcodes).
> Ya corregido y **NO** re-reportado: `sp_ApplyPartialPayment` C-1/H-7 (matemática de Payment.APPLY + idempotencia por `@Reference`); `WorkspaceId DEFAULT(newid())` en `tempcheques`/`tempcheqdet`/`tempchequespagos`/`turnos` (omitir la columna ya no pierde la fila).

---

## 1. Resumen ejecutivo

**Estado global de la ejecución TPV→SoftRestaurant: NO está a prueba de errores.** La superficie de comandos cableados es de **solo 6** (`Order.CREATE`, `OrderItem.CREATE`, `Payment.APPLY`, `Shift.OPEN`, `Shift.CLOSE`, `FastPayment.CREATE`), de los cuales **uno está completamente roto** (`Shift.CLOSE`) y los otros cinco funcionan **con caveats serios**. Toda la mitad transaccional del puente —voids, descuentos, modificadores, dividir/juntar/transferir cuentas, cambiar mesa, imprimir, cancelar orden— **no existe**.

Los dos defectos arquitectónicos que envenenan **toda** la dirección EXECUTE son:

1. **La cola de comandos no tiene Dead-Letter Exchange.** Cada `channel.nack(msg, false, false)` (con comentario "Enviar a la Dead-Letter Queue") **descarta el mensaje en silencio**, porque la cola se declara `assertQueue(queueName, { durable: true })` sin `x-dead-letter-exchange` (`commander.ts:161`). El DLX solo está cableado a la cola de eventos (`rabbitmq.ts:62-74`). Un pago, una orden o un cierre de turno que falle transitoriamente **desaparece sin rastro ni replay**.
2. **No hay idempotencia a nivel de comando.** RabbitMQ es *at-least-once* y el `ack` ocurre solo después de que el adaptador retorna (`commander.ts:134`). Solo `Payment.APPLY` está protegido (por `@Reference` en el SP). Los otros cinco comandos **duplican** al re-entregarse: doble orden, doble línea, doble turno abierto, doble venta rápida.

**Gaps CRITICAL/HIGH confirmados:** **6 CRITICAL** y **~25 HIGH** (varios son la misma raíz —DLQ ausente / no-idempotencia— manifestándose por operación).

> **Fase 5d — hardcodes (2026-06-15, ✅):** se eliminaron hardcodes de dinero y de versión en la ruta EXECUTE, todos leyendo tablas existentes vía un nuevo helper `src/core/posMeta.ts` (`getIvaRate` → `parametros.impuesto1`, fallback 16; `detectUsesWorkspaceId` → `COL_LENGTH('tempcheques','WorkspaceId')`; `getDefaultEmpresa` → `SELECT TOP 1 idempresa FROM empresas`, fallback '1'). Cambios: **(1)** `Order.CREATE` ahora es **version-aware** — v11/v12 conserva la columna `WorkspaceId` y recupera folio por GUID, v10 la **omite** y recupera folio vía `SCOPE_IDENTITY()` (folio es IDENTITY bigint) → **resuelve H-9** (la rama v10 con `SCOPE_IDENTITY` aún **no validada en una v10 real**, falta validación en vivo antes de producción); además honra `data.posAreaId` para `idarearestaurant` (antes ignorado/hardcodeado '01') e `idempresa` desde `getDefaultEmpresa` (antes '1'). **(2)** `addItemToOrder` lee el IVA de `parametros.impuesto1` (antes `1.16`/`16.00` hardcode), corrigiendo tasas != 16% (frontera 8%, exento). **(3)** `openShift` es version-aware (v10 omite `WorkspaceId`/`NEWID()`), usa `nextShiftId = max(MAX(turnos.idturno), MAX(parametros.ultimoturno)) + 1` (evita colisión con el contador nativo) e `idempresa` de config. **(4)** `applyPayment` (no cableado): el INSERT placeholder `'...'` se reemplazó por un INSERT real → **cierra el segundo flanco de H-19** (el flanco de `cancelOrderItem` se cerró en Fase 5b). Además binds `folio`/`idturno` migrados `sql.Int`→`sql.BigInt` en `Order.CREATE`/`addItemToOrder`/`openShift`/`applyPayment`/`closeAndPayOrder`/`cancelOrderItem`. **Sigue abierto:** H-1 (recálculo cabecera con `cantidad>1`), H-2/H-7/H-10 idempotencia de operación, H-3 (lookup por `descripcion`); el cableado de `applyPayment`/`closeAndPayOrder`/`cancelOrderItem` sigue pendiente.

| # CRITICAL | Qué |
|---|---|
| C-1 | **✅ ARREGLADO (Fase 5a-1)** — Cola de comandos sin DLX → todo comando fallido se pierde en silencio. Ahora la cola tiene DLX (`avoqado_commands_dead_letter_queue`); fallidos/desconocidos/JSON-inválido se preservan en la DLQ. |
| C-2 | **◑ PARCIAL (Fase 5a-2)** — Sin idempotencia a nivel Comandante → re-entrega duplica órdenes/ítems/turnos/ventas. El Commander ya de-duplica por CommandKey contra `AvoqadoProcessedCommands`; requiere `commandId` estable del backend (fail-open hoy). |
| C-3 | `closeShift` con SQL de archivado en placeholder `'...'` (no ejecutable) y `DELETE temp*` **antes** de archivar/marcar `cierre` (`SoftRestaurant11Adapter.ts:303-341`) — **pendiente (Fase 5b)** |
| C-4 | `Order.CREATE` cae bajo C-1: nack de orden = pérdida silenciosa — **mitigado por C-1 (DLQ); ya no se pierde en silencio** |

**Las 3-5 cosas más urgentes (en orden):**

1. ~~**Cablear un DLX/DLQ a la cola de comandos** (mirror de `AVOQADO_EVENTS_QUEUE`) y hacer que el `default` del switch **lance** en vez de hacer `ack`.~~ **✅ HECHO (Fase 5a-1).** Sin esto, nada de lo demás era recuperable; ya está la DLQ de comandos.
2. **Blindar `Shift.CLOSE` (`closeShift`)**: hoy es código muerto que siempre lanza; el orden `DELETE`-antes-de-archivar es destructivo por diseño. Gatear con `NOT_IMPLEMENTED` hasta implementarlo column-exact y con validación de conteos. **(Fase 5b, pendiente)**
3. ~~**Idempotencia de comandos**: usar la tabla `AvoqadoCommands` existente (con columna `CommandId`) + claves naturales por operación.~~ **◑ PARCIAL (Fase 5a-2):** el Commander de-duplica por CommandKey contra `AvoqadoProcessedCommands`; **requiere que el backend envíe un `commandId` único y estable** (fail-open hoy).
4. **Corregir el recálculo de totales de cabecera en `addItemToOrder` para `cantidad > 1`** (hoy suma columnas unitarias como si fueran totales de línea → cabecera mal en dinero).
5. **`cancelOrderItem`**: contiene SQL placeholder `'...'`, no recalcula totales y no está cableado. Es una bomba latente; arreglarlo y exponerlo, o documentarlo como no disponible. **(Fase 5b, pendiente)**

---

## 2. Tabla por operación

| Operación | Comando | Método adapter | Estado | Qué ejecuta | Error-proofing (tx / DLQ / idempotencia) | v10/v11/v12 |
|---|---|---|---|---|---|---|
| Abrir cuenta/mesa | `Order.CREATE` | `createEmptyOrder` → `services/Orders/createEmptyOrder.ts` | ⚠️ caveats | INSERT `tempcheques` (idturno=0, `idarearestaurant` ← `data.posAreaId` (fb '01') ✅5d, `idempresa` ← `getDefaultEmpresa` (fb '1') ✅5d, `WorkspaceId` solo v11/v12 ✅5d); +1 `folios.ultimaorden`; UPDATE totales=0 **post-commit fuera de tx** | tx con rollback **parcial** (guard de ocupación y totales fuera de la tx); ❌ DLQ; ❌ idempotencia | **✅5d version-aware**: v11/v12 con WorkspaceId (folio por GUID), v10 omite WorkspaceId (folio por `SCOPE_IDENTITY()`); rama v10 **pendiente de validación en vivo** |
| Agregar producto | `OrderItem.CREATE` | `addItemToOrder` (`:33`) | ⚠️ caveats | lookup producto por **`descripcion`** (no idproducto); INSERT `tempcheqdet` (IVA ← `parametros.impuesto1` ✅5d, `idestacion='AVOQADO_SYNC'`); recalc cabecera por SUM | tx con rollback OK; ❌ DLQ; ❌ idempotencia; **recalc cabecera mal si cantidad>1** | mismo SQL en todas; WorkspaceId vía DEFAULT; folio bind `sql.BigInt` ✅5d |
| Cobrar (parcial/total) | `Payment.APPLY` | `applyIntelligentPayment` (`:361`) → `sp_ApplyPartialPayment` | ⚠️ caveats / ✔ math&idemp. fixed | resuelve folio (v10 parts[2] / v11 WorkspaceId); EXEC SP: INSERT `tempchequespagos`, escala `cantidad` en parcial, `pagado=1` en total | SP atómico (BEGIN TRAN/CATCH/ROLLBACK); ✔ idempotencia por `@Reference` (colapsa si ref vacía); ❌ DLQ | v11/v12 primario; v10 menos probado |
| Abrir turno | `Shift.OPEN` | `openShift` (`:239`) | ⚠️ caveats | INSERT `turnos` (idturno = max(MAX(turnos.idturno), MAX(parametros.ultimoturno))+1 ✅5d, sin lock; `cajero`=staffId, `idmesero=''`, `idempresa` ← `getDefaultEmpresa` ✅5d, `WorkspaceId`/`NEWID()` solo v11/v12 ✅5d); UPDATE `parametros.ultimoturno` **sin WHERE** | tx con rollback OK; ❌ DLQ; ❌ idempotencia (sin guard `cierre IS NULL`) | **✅5d version-aware**: v10 omite WorkspaceId; idturno bind `sql.BigInt` ✅5d; staffId publicado vacío en todas |
| Cerrar turno | `Shift.CLOSE` | `closeShift` (`:288`) | ❌ **broken** | archivado `cheques/cheqdet/chequespagos` = **placeholders `'...'`**; `DELETE temp*` **antes** de `UPDATE turnos.cierre`; reset `folios WHERE serie=''` | tx con rollback (siempre lanza); ❌ DLQ; ❌ idempotencia; **no llama `sp_BeginShiftArchiving`** | idéntico/roto en todas |
| Venta rápida | `FastPayment.CREATE` | `createFastPayment` (`:995`) | ⚠️ caveats | tx completa: turno abierto, INSERTs `tempcheques`/`tempcheqdet`(FASTPAY)/`tempchequespagos`; `impreso=1`; numcheque=MAX+1; `pagado=1` | tx con rollback OK; ❌ DLQ; ❌ idempotencia; numcheque sin lock; IVA=0 | v11/v12 OK (WorkspaceId DEFAULT); v10 menos probado |
| Cancelar producto/línea | *(ninguno)* | `cancelOrderItem` (`:129`, declarado pero **NO cableado**) | ⛔ no-wired | DELETE `tempcheqdet`; INSERT `tempcancela`; **no recalcula totales** (recalc + remoción de `bitacorasistema` `'...'` = Fase 5b) | tx OK; ❌ DLQ; ❌ idempotencia; folio bind `sql.BigInt` ✅5d | agnóstico; sin cablear hoy |
| Cancelar orden completa | *(ninguno)* | *(no existe)* | ⛔ not-implemented | — | cae en `default` → warn + **ack silencioso** | — |
| Modificadores / descuento ítem / comentario-edit / curso | *(ninguno)* | *(no existe; solo comentario en alta)* | ⛔ not-implemented | — | `default` → ack silencioso | — |
| Propina (ajuste) | *(ninguno)* | solo columna en pago; `createFastPayment` hardcodea `propina=0` | ⛔ not-implemented | — | — | — |
| Dividir / juntar / transferir / cambiar mesa | *(ninguno)* | `createSplitOrder`/`splitOrderItems`/… (**código muerto**, 0 callers) | ⛔ not-implemented | — | helpers con tx pero nunca alcanzados | — |
| Imprimir cuenta (pre-cuenta) | *(ninguno)* | *(no existe; solo efecto colateral de pago/fast)* | ⛔ not-implemented | — | `default` → ack silencioso | — |
| `applyPayment` / `closeAndPayOrder` (legacy) | *(ninguno)* | `:188` / `:206` (declarados, **no cableados**) | ⛔ no-wired | `applyPayment`: INSERT `tempchequespagos` real (folio, idformadepago, importe, propina, referencia) ✅5d (antes `'...'` no ejecutable); folio bind `sql.BigInt` ✅5d en ambos | sin tx (applyPayment) | — |

Leyenda: ✅ works · ⚠️ caveats · ❌ broken · ⛔ not-implemented · ✔ fixed.

---

## 3. Gaps confirmados

### 3.1 CRITICAL

#### C-1 — La cola de comandos NO tiene Dead-Letter Exchange: TODO comando fallido se descarta en silencio
**✅ ARREGLADO (Fase 5a-1):** la cola de comandos ahora tiene dead-letter-exchange (avoqado_commands_dead_letter_queue); comandos fallidos/desconocidos/JSON-inválido se preservan en la DLQ (validado en vivo: comando desconocido fue a la DLQ). Migración automática de la cola existente.

- **Severidad:** CRITICAL · **Categoría:** failure-handling
- **Evidencia:** `commander.ts:161` `await channel.assertQueue(queueName, { durable: true })` (sin `arguments`/`x-dead-letter-exchange`). `commander.ts:39` y `commander.ts:148` hacen `channel.nack(msg, false, false)` con comentario "Enviar a la Dead-Letter Queue". El DLX real (`DEAD_LETTER_EXCHANGE` + `avoqado_events_dead_letter_queue`) está atado **solo** a `AVOQADO_EVENTS_QUEUE` en `rabbitmq.ts:62-74`. La cola `commands_queue.venue_${venueId}` nunca aparece en `assertTopology`.
- **Por qué importa:** Es la dirección EXECUTE: un mensaje descartado es una acción de negocio perdida (un pago no registrado, una orden no creada, un turno no cerrado) sin traza, sin replay, sin visibilidad de operación. Un blip de 2 s de SQL o un deadlock pierde permanentemente un comando que un reintento habría completado. El log/comentario hacen creer que el mensaje está a salvo en una DLQ cuando ya no existe.
- **Recomendación accionable:** Declarar la cola de comandos con `arguments: { 'x-dead-letter-exchange': DEAD_LETTER_EXCHANGE, 'x-dead-letter-routing-key': 'dead-letter.commands' }` y atar una `commands_dead_letter_queue`, centralizado en `assertTopology()` (no ad-hoc en `setupConsumer`). Como cambiar argumentos de una cola durable requiere borrar+recrear, versionar el nombre o documentar la migración. Distinguir transitorio (requeue con backoff acotado) de permanente (DLQ). Alertar sobre profundidad de la DLQ de comandos.

#### C-2 — Sin idempotencia a nivel Comandante: re-entrega duplica órdenes/ítems/turnos/ventas
**◑ PARCIAL (Fase 5a-2):** el Commander de-duplica por CommandKey (messageId/commandId/idempotencyKey) contra AvoqadoProcessedCommands (validado: comando con id repetido se omite). REQUIERE que el backend (avoqado-server) envíe un id único y estable por comando — hoy no lo hace (fail-open). Tracked como chip de backend.

- **Severidad:** CRITICAL · **Categoría:** idempotency
- **Evidencia:** `commander.ts:134` `channel.ack(msg)` ocurre tras el `await` del adaptador; no hay verificación de `messageId`/`commandId` contra `AvoqadoCommands` (que existe con columna `CommandId`, `01-COMPLETE-INSTALL.sql:217-229`). `addItemToOrder` usa `ISNULL(MAX(movimiento),0)+1` (`SoftRestaurant11Adapter.ts:56`); `openShift` usa `MAX(idturno)+1` sin guard de turno abierto (`:247`); `createFastPayment` inserta venta sin dedupe (`:1030-1056`). Solo `Payment.APPLY` protegido por `@Reference` (`01-COMPLETE-INSTALL.sql:410-418`).
- **Por qué importa:** Un blip de red al momento del `ack` duplica en silencio una acción adyacente a dinero: orden pagada duplicada, folio de venta rápida duplicado, o dos turnos abiertos para un cajero — todo corrompe reportes de ventas/turno y la conciliación.
- **Recomendación accionable:** Exigir un `commandId` estable del backend (usar AMQP `messageId` o un campo `commandId` en el payload) y registrarlo en `AvoqadoCommands` **dentro de la misma transacción** que la escritura al POS; en re-entrega, detectar el id ya procesado y hacer `ack` sin re-ejecutar. Como mínimo, idempotencia por clave natural por comando (turno abierto único; `(folio, externalLineId)`; venta rápida por `referencia`).

#### C-3 — `closeShift`: SQL de archivado es placeholder `'...'` (no ejecutable) y `DELETE temp*` corre ANTES de archivar/marcar `cierre`
- **Severidad:** CRITICAL · **Categoría:** correctness / transactionality
- **Evidencia:** `SoftRestaurant11Adapter.ts:303-308` construye `archivalQueries = ['INSERT INTO cheques (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempcheques WHERE idturno = @shiftId', ...]` con `(...)` y `...` literales (T-SQL inválido); el comentario L307 admite "(añadir aquí los demás INSERT/SELECT)". El loop `:310-312` ejecuta el primero → SQL Server lanza error de sintaxis → catch `:347-351` rollback+rethrow. Los `DELETE FROM tempchequespagos/tempcheqdet/tempcancela/tempcheques` (`:316-329`) están escritos **antes** de `UPDATE turnos SET cierre=@cierre` (`:341`). `commander.ts:99-110` cablea `Shift.CLOSE` a este método.
- **Por qué importa:** La operación EXECUTE más importante del ciclo de turno es código muerto disfrazado de implementado. Todo `Shift.CLOSE` lanza, hace rollback y se dropea (por C-1). Nada se archiva, los temp* no se borran, `turnos.cierre` nunca se setea. Si alguien "rellena" los `'...'` sin mapeo de columnas exacto, el `DELETE`-antes-de-archivado-verificado **destruye las ventas de un turno completo** que nunca llegaron a `cheques/cheqdet/chequespagos`. Además, como `cierre` se setea después del DELETE y nunca se llama `sp_BeginShiftArchiving`, cada línea/pago borrado se publicaría como **CANCELLED** (los guards del trigger están inactivos en ese punto).
- **Recomendación accionable:** (a) Gatear: lanzar `NOT_IMPLEMENTED` al inicio de `closeShift` (o quitar el case `Shift.CLOSE`) para que el Corte Z nativo siga siendo la fuente de verdad. (b) Al implementar de verdad: setear `turnos.cierre` **antes** de cualquier DELETE; llamar `sp_BeginShiftArchiving(@idturno)` tras `begin()` y `sp_EndShiftArchiving(@idturno)` tras `commit()`; INSERTs column-exact (verificados contra traza real) capturando `@@ROWCOUNT`; aseverar `conteo_archivado == conteo_temp` por tabla **antes** de borrar; archivar también las tablas auxiliares (`cancela`, `cheqpedidos`, `bitacoratarjetacredito`, `numerostarjetas`, `foliosfacturados`). **Nunca DELETE antes de archivo verificado.** Aplicar la regla de 5 scripts SQL + doc-sync.

> **Nota:** Los hallazgos C-1, C-2 y C-4 son la misma raíz (DLQ ausente / no-idempotencia) manifestándose por operación. La auditoría los registra individualmente por operación porque cada uno tiene impacto distinto (pago perdido vs orden duplicada vs turno doble). Resolver C-1 y C-2 a nivel transversal cierra simultáneamente la mayoría de los HIGH de `failure-handling`/`idempotency` listados abajo.

### 3.2 HIGH

#### H-1 — `addItemToOrder`: el recálculo de cabecera trata columnas unitarias como totales de línea → totales mal para cantidad > 1
- **Categoría:** correctness · **Evidencia:** `SoftRestaurant11Adapter.ts:73` guarda `precio` como UNITARIO (tras fix ad32e0f); pero el UPDATE de cabecera `:93-105` hace `total = SUM(precio)`, `subtotal = SUM(preciosinimpuestos)`, `totalimpuesto1 = SUM(precio-preciosinimpuestos)` **sin multiplicar por `cantidad`**. El producer lee `precio` como unitario y calcula total de línea = `precio*cantidad` (`producer.ts:807,810`). Para una línea cantidad=2 a $100, cabecera da total=100 mientras la línea vale 200.
- **Por qué importa:** Cualquier alta con cantidad>1 produce `tempcheques.total/subtotal/totalimpuesto1` subvaluado por un factor de `cantidad`. El `order.updated` (producer lee `tempcheques.total` verbatim, `producer.ts:592`) envía el total equivocado al backend, y la cuenta del POS está mal. Es defecto de dinero.
- **Recomendación:** En el UPDATE de cabecera multiplicar por `cantidad`: `SUM(precio*cantidad)`, `SUM(preciosinimpuestos*cantidad)`, `SUM((precio-preciosinimpuestos)*cantidad)`. Agregar test de regresión con cantidad=2 que aseverе cabecera == 2×unitario.

#### H-2 — `addItemToOrder`: sin idempotencia → re-entrega inserta línea duplicada
- **Categoría:** idempotency · **Evidencia:** `SoftRestaurant11Adapter.ts:54-77` (MAX(movimiento)+1, sin dedupe); `commander.ts:65,134` (ack tras retornar). Una re-entrega tras `commit()` (`:113`) inserta una segunda fila `tempcheqdet` y re-infla la cabecera.
- **Recomendación:** Llevar un `itemExternalId/lineId` estable de Avoqado y hacer el INSERT condicional (skip si existe `(foliodet, lineId)`), análogo al `@Reference` del SP.

#### H-3 — `addItemToOrder`: producto resuelto por `descripcion` (nombre), no por `idproducto`
- **Categoría:** correctness · **Evidencia:** `SoftRestaurant11Adapter.ts:42-43` `WHERE descripcion = @productIdLookup`, pese a que `OrderAddItemData.productId` se documenta como "el idproducto del POS" (`IPosAdapter.ts:39`); `recordset[0]` tomado sin validar >1 match (`:48`).
- **Por qué importa:** `descripcion` es texto libre sin unicidad; nombres duplicados/renombrados → idproducto equivocado o 0 filas (que dead-lettera/dropea un alta legítima).
- **Recomendación:** Buscar por `idproducto`; si Avoqado realmente envía nombre, añadir ruta indexada con chequeo de unicidad y error en múltiples coincidencias. Alinear el doc de `IPosAdapter`.

#### H-4 — `Payment.APPLY`: ruta de pago TOTAL incompleta vs nativo (sin `impreso/numcheque/cierre`, sin distribuir `efectivo/tarjeta/vales/otros`, sin `folios.ultimofolio`)
- **Categoría:** completeness · **Evidencia:** ruta total del SP solo hace `UPDATE tempcheques SET pagado=1, observaciones+=' | PAGADO'` (`01-COMPLETE-INSTALL.sql:480-482`); ningún `impreso/numcheque/efectivo/tarjeta` en el SP. El flujo nativo (preservado en `04-Native-Payment-Flow.sql:175-259`) asigna `numcheque`/`impreso=1`/`cierre`, sube `folios.ultimofolio` y distribuye por `formasdepago.tipo`. `PAYMENT-METHOD-FIX.md:47-59` confirma que las columnas de tipo de pago en cabecera importan para reportes.
- **Por qué importa:** Una orden Avoqado totalmente pagada queda `pagado=1` pero sin número de cheque impreso y con cabecera reportando $0 efectivo / $0 tarjeta. El corte de caja y X/Z mal-reportan el desglose efectivo/tarjeta de órdenes pagadas vía Avoqado.
- **Recomendación:** Portar el bloque de pago total nativo a la rama `@Remaining<=0.01` del SP: asignar `numcheque/impreso/cierre` desde `folios` (con `TABLOCKX`), subir `folios.ultimofolio`, recomputar `efectivo/tarjeta/vales/otros` por JOIN a `formasdepago.tipo`. Verificar contra un cierre fresco.

#### H-5 — `Payment.APPLY`: el pago PARCIAL re-escala las cantidades de ítem destructivamente
- **Categoría:** correctness · **Evidencia:** `01-COMPLETE-INSTALL.sql:500` `@RemainingRatio = @Remaining/@OrderTotal`; `:508-510` `UPDATE tempcheqdet SET cantidad = cantidad*@RemainingRatio`. Un parcial de $7 sobre $777 escala todas las cantidades por 0.9909 (1 taco → 0.99 taco), perdiendo la cantidad original.
- **Por qué importa:** El nativo trackea pagado-vs-debido por filas de pago + `pagado`, no encogiendo cantidades. Cantidades fraccionarias corrompen: conteos de cocina, reportes de mezcla de producto, deducción de inventario por receta (`INVENTORY_TRACKING` es PREMIUM), y cualquier cancelación de línea posterior. El producer re-publica estos ítems escalados como `orderitem.updated`, propagando la corrupción.
- **Recomendación:** NO mutar `tempcheqdet.cantidad`. Representar el cobro parcial solo vía filas `tempchequespagos` + un campo de balance, espejando el split nativo (que mueve ítems a un cheque hijo). Si hay que reducir `tempcheques.total`, hacerlo solo en la cabecera. **Requiere decisión de tier/producto** (parcial toca inventario).

#### H-6 — `Payment.APPLY`: la idempotencia colapsa a cero cuando `@Reference` es null/vacío
- **Categoría:** idempotency · **Evidencia:** guard `01-COMPLETE-INSTALL.sql:410` `IF @Reference IS NOT NULL AND LTRIM(RTRIM(@Reference)) <> '' AND EXISTS(...)`; el adaptador envía `payment.reference || null` (`SoftRestaurant11Adapter.ts:381`); `reference` es opcional en el tipo (`IPosAdapter.ts:51,:55`). Sin referencia, una re-entrega inserta una segunda fila de pago y re-escala cantidades otra vez.
- **Por qué importa:** Doble cobro — el peor resultado de un comando de pago.
- **Recomendación:** Hacer `Reference` obligatoria y estable para `Payment.APPLY`, validada en `commander.ts` (hoy solo chequea `orderExternalId+paymentData`, `:71-74`). Defensa en profundidad: índice único en `folio+referencia` y rechazar referencias en blanco en el SP en vez de saltar el guard.

#### H-7 — `Shift.OPEN`: `openShift` no es idempotente → re-entrega abre un segundo turno
- **Categoría:** idempotency · **Evidencia:** `SoftRestaurant11Adapter.ts:247` (`MAX(idturno)+1`), `:260-269` (INSERT incondicional, sin chequeo `cierre IS NULL`); `commander.ts:86-97`→ack `:134`.
- **Por qué importa:** Dos turnos OPEN concurrentes corrompen el modelo de doble-clave: `idturno` es la clave de negocio en todo entity-id y join. `createFastPayment` (`:1005-1010`) y el producer (`producer.ts:403,440`) eligen `TOP 1 ... cierre IS NULL ORDER BY apertura DESC` → "el turno actual" se vuelve ambiguo y puede atribuir ventas/efectivo al turno equivocado.
- **Recomendación:** Pre-chequear `IF EXISTS(SELECT 1 FROM turnos WHERE cierre IS NULL...)` y no-op-retornar el turno abierto existente (o rechazar). Esto duplica como guard de idempotencia para re-entregas.

#### H-8 — `Shift.OPEN`: turnos abiertos vía Avoqado publican `staffId` vacío (cajero escrito en `cajero`, no `idmesero`)
- **Categoría:** completeness · **Evidencia:** `SoftRestaurant11Adapter.ts:261-267` (`... cajero, idempresa, idmesero, WorkspaceId VALUES (... @cajero, '1', '', NEWID())`); el producer deriva el staff del turno **solo** de `turnos.idmesero` (`producer.ts:943` V10, `:985` V11).
- **Por qué importa:** El backend no puede atribuir el turno abierto a un empleado — rompe reportes por cajero, conciliación de efectivo por operador y lógica por staff. Específico de la ruta EXECUTE de Avoqado.
- **Recomendación:** Confirmar (vía captura nativa) si SoftRestaurant identifica al operador por `idmesero` o `cajero`, escribir `posStaffId` en la columna que POS/producer leen, y alinear la fuente del producer.

#### H-9 — `Order.CREATE`: el INSERT no es version-aware — columna `WorkspaceId` hardcodeada rompe en v10 real
**✅ ARREGLADO (Fase 5d):** `createEmptyOrder` ahora detecta versión vía `detectUsesWorkspaceId` (`posMeta.ts`, criterio `COL_LENGTH('tempcheques','WorkspaceId')`): v11/v12 conserva la columna `WorkspaceId` y recupera el folio por GUID; v10 **omite** la columna y recupera el folio vía `SCOPE_IDENTITY()` (folio es IDENTITY bigint). **Caveat:** la rama v10 (`SCOPE_IDENTITY`) **NO está validada en una v10 real** (ninguna alcanzable) — requiere validación en vivo antes de producción. La rama v11 quedó validada en vivo en sr11 local.
- **Categoría:** version-compat · **Evidencia:** `createEmptyOrder.ts:41,45,54` hardcodeaban `WorkspaceId` en la lista de columnas y VALUES sin rama de versión. En un esquema v10 genuino (sin columna `WorkspaceId`) el INSERT fallaba con "Invalid column name WorkspaceId". Contradecía el requisito duro de CLAUDE.md (todo cambio debe funcionar en v10 Y v11).
- **Recomendación:** ✅ Resuelto vía `detectUsesWorkspaceId`. **Pendiente:** verificar la rama v10 contra un DB de prueba v10 real antes de producción.

#### H-10 — `Order.CREATE`: sin idempotencia → re-entrega crea órdenes abiertas duplicadas
- **Categoría:** idempotency · **Evidencia:** `createEmptyOrder.ts:8-79`; el único guard es el SELECT de ocupación `:18-29`, que no protege ni contra re-entrega tras pagar/liberar la mesa, ni contra dos entregas en carrera antes del commit; el INSERT genera un WorkspaceId fresco cada vez (`:14`) sin clave de dedupe.
- **Recomendación:** Idempotency key estable de Avoqado (id de orden de plataforma) en columna/tabla con UNIQUE; en re-entrega devolver el folio existente. Como mínimo, mover el chequeo de existencia dentro de la transacción.

#### H-11 — `Order.CREATE`: guard de ocupación fuera de la transacción → carrera TOCTOU permite dos órdenes en la misma mesa
- **Categoría:** transactionality · **Evidencia:** `createEmptyOrder.ts:23` el SELECT corre en `pool` antes de `:32 transaction.begin()`, sin `UPDLOCK/HOLDLOCK` y sin re-chequeo dentro de la tx.
- **Recomendación:** Mover el chequeo dentro de la tx con `SELECT ... WITH (UPDLOCK, HOLDLOCK)` o un índice único filtrado por `mesa` para órdenes activas, para hacer atómico el check-then-insert.

#### H-12 — `Order.CREATE`: bajo C-1 — `Order.CREATE` nackeado se dropea en silencio
- **Categoría:** failure-handling · **Evidencia:** misma raíz que C-1 (`commander.ts:161` sin DLX vs `rabbitmq.ts:68-74`). Un fallo transitorio en la creación de orden (blip de DB, deadlock, el UPDATE de totales post-commit fallando) pierde el "abrir mesa" sin retry ni DLQ.
- **Recomendación:** Igual que C-1.

#### H-13 — `Shift.CLOSE`: los `DELETE temp*` corren en la misma transacción que el archivado placeholder — diseño propenso a pérdida de datos cuando el archivado sea real
- **Categoría:** transactionality · **Evidencia:** `SoftRestaurant11Adapter.ts:310-329` (loop de INSERTs seguido inmediatamente de DELETEs en una tx); no archiva tablas auxiliares. Sin validación pre-archivo (sin órdenes abiertas/impagas) antes de purgar.
- **Recomendación:** Setear `turnos.cierre` ANTES de cualquier DELETE; archivar TODAS las tablas (maestras + auxiliares); validación pre-archivo; aseverar conteo archivado == conteo temp por tabla antes de borrar; todo en una transacción.

#### H-14 — `Shift.CLOSE`: sin guard de doble-cierre → re-entrega re-ejecuta un cierre destructivo sobre un turno ya cerrado
- **Categoría:** idempotency · **Evidencia:** `SoftRestaurant11Adapter.ts:288-352` (sin SELECT de `turnos.cierre` / sin `IF cierre IS NULL` antes de mutar); `commander.ts:134` ackea tras retornar; `rabbitmq.ts:164` prefetch(1) manual ack.
- **Recomendación:** Al inicio de la tx, `SELECT turnos.cierre WHERE idturno=@shiftId`; si ya cerrado, tratar como no-op exitoso. Acotar INSERTs de archivado con `NOT EXISTS` contra destino/`idturno_cierre`.

#### H-15 — `Shift.CLOSE`: nunca llama `sp_BeginShiftArchiving` y setea `cierre` DESPUÉS de los DELETEs → cada línea/pago se emitiría como CANCELLED
- **Categoría:** failure-handling · **Evidencia:** DELETEs `:316-329` preceden a UPDATE cierre `:341`; `sp_BeginShiftArchiving`/`sp_EndShiftArchiving` definidos (`01-COMPLETE-INSTALL.sql:577-603`) pero llamados en ningún lado; guards de trigger `:666-678/716-730/777-790` requieren `IsArchiving=1` o `cierre` dentro de 30 s.
- **Recomendación:** Llamar `sp_BeginShiftArchiving(@idturno)` tras `begin()` y `sp_EndShiftArchiving(@idturno)` tras `commit()`, O setear `turnos.cierre` antes de los DELETEs. Endurecer el fallback del trigger para suprimir cualquier DELETE de temp* cuyo turno tenga `cierre IS NOT NULL` sin importar el tiempo transcurrido.

#### H-16 — `FastPayment.CREATE`: re-entrega duplica una venta de dinero real (sin idempotencia)
- **Categoría:** idempotency · **Evidencia:** `SoftRestaurant11Adapter.ts:995-1190` (sin guard SELECT-before-insert, sin dedupe por `@Reference`); `commander.ts:120,134`. `data.reference` se escribe en `tempchequespagos.referencia` (`:1143`) pero nunca se chequea.
- **Por qué importa:** Venta rápida duplicada = ingreso duplicado en el reporte de turno/Z y orden pagada fantasma.
- **Recomendación:** Idempotencia sobre clave estable (`data.reference` o `commandId`): SELECT existente por `(referencia + amount + idturno)` al inicio de la tx y short-circuit (devolver folio/numcheque existente).

#### H-17 — `FastPayment.CREATE`: bajo C-1 — venta rápida fallida se dropea en silencio
- **Categoría:** failure-handling · **Evidencia:** `commander.ts:148` nack(false,false); `:161` sin DLX; `rabbitmq.ts:68-74` DLX solo en eventos.
- **Recomendación:** Igual que C-1. Verificar que la DLQ atada realmente reciba comandos nackeados.

#### H-18 — `cancelOrderItem`: nunca cableado a comando — anular una línea es inalcanzable desde Avoqado
- **Categoría:** missing-feature · **Evidencia:** `commander.ts:53-131` solo tiene `OrderItem.CREATE`; sin case de cancel. `cancelOrderItem` definido en `SoftRestaurant11Adapter.ts:129`, declarado en `IPosAdapter.ts:98`. Un comando de cancel cae en `default` (`:129-130`) → warn → **ack** (`:134`) como si se hubiera procesado.
- **Por qué importa:** La TPV no puede anular una línea por este puente. Un void en Avoqado nunca llega al POS → el POS sigue cobrando un producto removido.
- **Recomendación:** Agregar case `OrderItem.CANCEL` que valide `{orderFolio, movementId, reason, user}` y llame `adapter.cancelOrderItem(...)`. Hasta entonces, documentar que no está expuesta.

#### H-19 — anti-patrón SQL placeholder `'...'` en rutas de ejecución (`cancelOrderItem` + `applyPayment`)
**✅ ARREGLADO (Fase 5b + 5d):** los dos flancos del anti-patrón `'...'` están cerrados. (a) **Fase 5b** — se quitó la escritura placeholder a `bitacorasistema` en `cancelOrderItem`. (b) **Fase 5d** — el INSERT placeholder de `applyPayment` (`INSERT INTO tempchequespagos (..., ...) VALUES (..., ...)`, T-SQL inválido que siempre lanzaba) se reemplazó por un INSERT real (folio, idformadepago, importe, propina, referencia). **Nota:** `applyPayment` sigue **sin cablear** (Payment.APPLY usa `applyIntelligentPayment`); la corrección elimina la bomba latente. H-19 queda **totalmente resuelto** a través de 5b+5d.
- **Categoría:** correctness · **Evidencia (original):** `SoftRestaurant11Adapter.ts:167-171` `.query('INSERT INTO bitacorasistema (fecha, usuario, evento, valores, ...) VALUES(GETDATE(), @usuario, @evento, @valores, ...)')`; mismo anti-patrón `'...'` en `applyPayment` (`:199`).
- **Recomendación:** ✅ Resuelto. Mantener la regla de no enviar SQL placeholder en ninguna ruta de ejecución.

#### H-20 — `cancelOrderItem`: no recalcula totales de cabecera tras borrar la línea; el comentario afirma falsamente que lo hace el trigger
- **Categoría:** completeness · **Evidencia:** `SoftRestaurant11Adapter.ts:151-175` (DELETE luego commit, sin UPDATE de `tempcheques`; comentario L175 dice "El Trigger del DELETE... debería haber recalculado los totales"). Pero `Trg_Avoqado_OrderItems` (`01-COMPLETE-INSTALL.sql:711-765`) solo escribe `AvoqadoTracking`, no recalcula. Contrasta con `addItemToOrder` que SÍ recalcula (`:82-109`).
- **Por qué importa:** El DELETE dispara el trigger que encola un order UPDATE; el producer re-lee `tempcheques` verbatim y republica `order.updated` con un total MÁS ALTO que la suma de los ítems restantes → reportes de total/impuesto/ventas corrompidos en cada void.
- **Recomendación:** Tras el DELETE, ejecutar el mismo UPDATE por SUM de `addItemToOrder` (manejando el caso orden vacía → totales 0), dentro de la misma transacción. Quitar el comentario engañoso.

#### H-21 — `cancelOrderItem`: bajo C-1 — fallos de cancel chocan con cola sin DLX → pérdida silenciosa
- **Categoría:** failure-handling · **Evidencia:** `commander.ts:156-162` cola sin DLX; `rabbitmq.ts:68-74` DLX solo en eventos; `:39` y `:148` nack(false,false). · **Recomendación:** Igual que C-1.

#### H-22 — Cancelar orden completa / void de cuenta: completamente no implementado en EXECUTE
- **Categoría:** missing-feature · **Evidencia:** `IPosAdapter.ts:90-109` no expone `cancelOrder/voidOrder`; `SoftRestaurant11Adapter.ts` no lo implementa (solo `cancelOrderItem`); `commander.ts:53-131` sin case; ningún SP hace `cancelado=1`. El nativo es `UPDATE tempcheques SET cancelado=1` (la fila permanece) + INSERT `cancela` (auditoría razón/usuario).
- **Por qué importa:** Una orden anulada en Avoqado nunca se anula en el POS: el cheque queda activo (`cancelado=0`), mantiene la mesa ocupada y se archiva/paga como venta real en el cierre → venta fantasma y descuadre de efectivo/inventario.
- **Recomendación:** Agregar `cancelOrder(externalId, reason, user)` que en una tx con rollback: resuelva folio vía `extractFolioFromExternalId`; `UPDATE tempcheques SET cancelado=1` + columnas nativas de cancel-user/date; escriba `cancela/tempcancela`; `UPDATE productosenproduccion SET cancelado=1`. Cablear `Order.CANCEL`. Confirmar el set nativo con el monitor SQL. **Implementar con `cancelado=1` (flag), NO DELETE** (un DELETE sería leído por el producer como archivado de cierre y suprimido).

#### H-23 — Cancelar orden completa: un `Order.CANCEL` sería ackeado y dropeado en silencio (default hace ack)
- **Categoría:** failure-handling · **Evidencia:** `commander.ts:129-130` (default: solo `log.warn`, sin throw) → `:134` `channel.ack(msg)`.
- **Recomendación:** Hacer que el default **lance** (`throw new Error('No handler for command ' + entity + '.' + action)`) para que vaya al DLQ, en vez de ackear. Esto futureproof-ea todo comando nuevo de la plataforma.

#### H-24 — Modificadores, descuento por ítem, edición de comentario y curso/tiempo: completamente no implementados en EXECUTE
- **Categoría:** missing-feature · **Evidencia:** `commander.ts:53-131` (6 comandos, sin `OrderItem.UPDATE/MODIFIER/DISCOUNT/COMMENT/COURSE`); `OrderAddItemData` (`IPosAdapter.ts:38-45`) solo tiene `productId, quantity, price, waiterPosId, notes` (con TODO explícito "modificadores"); `addItemToOrder` INSERT (`:62-63`) omite `descuento/modificador/tiempo`. El POS usa esas columnas (probado por el SELECT del split helper `:655-659`: `descuento, comentario, tiempo, modificador, usuariodescuento, comentariodescuento, idtipodescuento, idproductocompuesto, productocompuestoprincipal, idcortesia`).
- **Por qué importa:** Una TPV que permita "sin cebolla", una cortesía 50% o asignar un platillo al tiempo 2 no puede empujar nada de eso al POS. El ticket de cocina y el cheque de cierre quedan sin modificadores/descuentos/curso → comida equivocada, totales mal (un descuento de ítem se vuelve precio completo), descuadres.
- **Recomendación:** Agregar `OrderItem.UPDATE` (y/o `OrderItem.DISCOUNT/MODIFIER/COMMENT/COURSE`) → métodos transaccionales nuevos que UPDATEen las columnas nativas correspondientes e inserten filas de producto compuesto para modificadores; recalcular totales tras cada uno.

#### H-25 — Modificadores/descuentos: comandos desconocidos para estas operaciones son ackeados y dropeados en silencio
- **Categoría:** failure-handling · **Evidencia:** `commander.ts:129-130` default warn → ack `:134`. · **Recomendación:** Igual que H-23 (default debe nackear a DLQ / lanzar).

#### H-26 — Dividir/juntar/transferir/cambiar mesa: NO implementados en EXECUTE (sin comando, sin método de interfaz)
- **Categoría:** missing-feature · **Evidencia:** `commander.ts:53-131` (6 comandos, sin split/merge/transfer/changeTable); `IPosAdapter.ts:90-109` sin firma. Los helpers `createSplitOrder`(`:567`)/`splitOrderItems`(`:650`)/`adjustOrderItemQuantities`(`:752`)/`updateParentOrderTotal`(`:979`) tienen **cero callers** (código muerto).
- **Por qué importa:** Operaciones core de servicio de mesa. Su ausencia hace el puente unidireccional para los flujos de piso más comunes; la UI de Avoqado y el POS divergen al dividir/juntar/transferir/mover una mesa.
- **Recomendación:** Decidir alcance de producto. Si deben ser ejecutables, diseñar comandos explícitos (`Order.SPLIT`, `Order.MERGE`, `OrderItem.TRANSFER`, `Order.CHANGETABLE`) + métodos que repliquen fielmente el SQL nativo (contadores `folios`, ocupación `mesas/mesasasignadas`, re-apuntar `foliodet`, recalc de totales padre/hijo), cada uno transaccional. Si son observe-only, documentarlo y **eliminar los helpers muertos**.

#### H-27 — Imprimir cuenta (pre-cuenta): no existe operación discreta
- **Categoría:** missing-feature · **Evidencia:** `commander.ts:53-131` sin case `Order.PRINT/Bill.PRINT/impreso`; `IPosAdapter.ts:90-109` sin método print. Las columnas nativas (`impreso=1` + `numcheque` desde `folios.ultimofolio` + `cierre/impresiones/seriefolio` + avance de `folios` + `cuentas.imprimir/procesado`) solo se escriben como efecto colateral de `closeAndPayOrder` (no cableado), `markOrderAsPaid` (privado, no llamado) o `createFastPayment` (orden nueva).
- **Por qué importa:** `impreso=1` es el gatekeeper de SoftRestaurant: nativamente una orden no se liquida en caja sin estar impresa y con `numcheque`. Si la TPV debe imprimir antes de pagar, ese flujo no está disponible.
- **Recomendación:** Si la TPV necesita print-bill, agregar `Order.PRINT` + `adapter.printBill(folio)` que en UNA tx bloquee `folios` (`WITH (TABLOCKX)`), lea `ultimofolio`, UPDATE `tempcheques SET impreso=1, numcheque=@n, impresiones=impresiones+1`, UPDATE `folios`, UPDATE `cuentas`. Version-aware (serie/WorkspaceId) e idempotente (no-op si `impreso=1`). Si está fuera de alcance, documentarlo para que el backend no emita el comando.

#### H-28 — Imprimir cuenta / cualquier comando futuro: comando desconocido es ackeado y dropeado
- **Categoría:** failure-handling · **Evidencia:** `commander.ts:129-130` default warn → ack `:134`. · **Recomendación:** Igual que H-23.

#### H-29 — `FastPayment.CREATE`: `numcheque` asignado por `MAX(numcheque)` por turno, no por `folios.ultimofolio` — numeración divergente + colisión concurrente
- **Categoría:** correctness · **Evidencia:** `SoftRestaurant11Adapter.ts:1093-1108` (`MAX(numcheque)+1` por idturno, sin lock; nunca avanza `folios.ultimofolio`). El nativo deriva `numcheque` de `folios.ultimofolio` bajo `TABLOCKX`.
- **Por qué importa:** `numcheque` es el número de ticket humano usado para corte/cruces fiscales; numeración divergente o colisionante rompe la conciliación y puede producir dos órdenes con el mismo ticket en un turno.
- **Recomendación:** Igualar el nativo: leer `folios.ultimofolio` con lock, asignar `numcheque` desde ahí, y UPDATE `folios.ultimofolio`. Centralizar la asignación de número de cheque en un helper reusado por FastPayment y un futuro `printBill`.

#### H-30 — `FastPayment.CREATE`: venta registrada IVA-inclusive con `impuesto1=0` — IVA sub-reportado
- **Categoría:** correctness · **Evidencia:** `SoftRestaurant11Adapter.ts:1051-1053` (`totalimpuesto1=0`, `subtotalsinimpuestos=@amount`), `:1077-1090` (`precio=preciosinimpuestos=@amount`, `impuesto1/2/3=0`). `createFastPayment` quedó **fuera del alcance de Fase 5d**, por lo que ahora es inconsistente con `addItemToOrder`, que tras 5d sí desglosa el IVA usando la tasa real (`parametros.impuesto1` vía `getIvaRate`, `:59`).
- **Por qué importa:** El IVA de cada venta rápida se reporta como 0 y la base neta se sobre-estima → totales de impuesto corrompidos y cruces fiscales/CFDI rotos. Internamente inconsistente con las órdenes normales (que ya usan la tasa configurada tras 5d).
- **Recomendación:** Computar el impuesto con la tasa configurada del venue (no hardcodear 16%): `preciosinimpuestos = amount/(1+rate)`, `impuesto1 = amount - preciosinimpuestos`. Reusar la misma derivación que `addItemToOrder` (`getIvaRate`).

#### H-31 — `FastPayment.CREATE`: hardcodes `idarearestaurant='01'`, `idempresa='0000000001'`, `mesa='FAST'`, producto `'FASTPAY'` — rompen venues que no los tienen
- **Categoría:** hardcode · **Evidencia:** `SoftRestaurant11Adapter.ts:1027` (producto default `'FASTPAY'`), `:1047-1049` (`mesa='FAST'`, `idarearestaurant='01'`, `idempresa='0000000001'`), `:1076` (INSERT `tempcheqdet` con idproducto literal). `createFastPayment` quedó **fuera del alcance de Fase 5d** y sigue con estos literales. (En contraste, `createEmptyOrder` ya deriva `idempresa` de `getDefaultEmpresa` ✅5d — **inconsistencia entre las dos rutas**: una resuelve de config, la otra aún hardcodea.)
- **Por qué importa:** Multi-tenant: un venue cuyo área no es '01', cuya empresa no es '0000000001', o cuyo catálogo carece de un producto `'FASTPAY'` obtiene fallo de FK y toda venta rápida es rechazada (luego dropeada por C-1).
- **Recomendación:** Derivar `idarearestaurant/idempresa` de config o del turno/estación abierta en vez de literales, y alinear con `createEmptyOrder`. Validar/auto-provisionar el producto de venta rápida (como AVOTEST/ACASH/ACARD en el install). Reconciliar la discrepancia de `idempresa`.

#### H-32 — Integridad transaccional: comandos no idempotentes ackean solo tras commit → re-entrega duplica
- **Categoría:** idempotency · (raíz compartida con C-2) · **Evidencia:** `commander.ts:134` ack tras `await`; `createEmptyOrder.ts:49-71`; `SoftRestaurant11Adapter.ts:54-77`, `:247-269`, `:1030-1056`. · **Recomendación:** Igual que C-2.

---

### 3.3 MEDIUM

| ID | Operación | Hallazgo | Evidencia | Recomendación |
|---|---|---|---|---|
| M-1 | Shift.OPEN | `idturno` sin lock → carrera con altas nativas/comandos concurrentes. **Parcial 5d:** ya no usa solo `MAX(turnos.idturno)+1` sino `max(MAX(turnos.idturno), MAX(parametros.ultimoturno))+1` (evita colisión con el contador nativo); **sigue sin lock** (la carrera concurrente persiste). | `SoftRestaurant11Adapter.ts:247` (sin hint de lock; ✅5d considera `parametros.ultimoturno`) | Leer MAX bajo `UPDLOCK,HOLDLOCK` (o serializable), o derivar el número como el POS nativo (contador bajo `TABLOCKX`) |
| M-2 | Shift.OPEN | `UPDATE parametros SET ultimoturno` sin WHERE; puede no ser el contador que lee el POS | `SoftRestaurant11Adapter.ts:271-273` | Capturar alta nativa de turno; actualizar exactamente esa columna con scope y lock correctos |
| M-3 | Shift.OPEN | Sin guard contra abrir turno cuando ya hay uno abierto | `SoftRestaurant11Adapter.ts:239-283` | Rechazar/no-op `Shift.OPEN` si ya existe turno abierto (también sirve de idempotencia) |
| M-4 | Shift.OPEN | `Trg_Avoqado_Shifts` re-emite OPENED en cualquier UPDATE que deje `cierre` NULL → `shift.created` duplicado | `01-COMPLETE-INSTALL.sql:821,827-836` (rama OPENED sin join a `deleted`) vs CLOSE `:839-848` | Disparar OPENED solo en altas reales (trigger INSERT-only o join a `deleted`). Aplicar regla 5-scripts |
| M-5 | Shift.CLOSE | Bajo C-1 — close fallido se dropea, no dead-lettered; Avoqado sin señal de fallo | `commander.ts:148/:161`; `rabbitmq.ts:62-74` | Igual que C-1; emitir evento de fallo/ack-back a Avoqado |
| M-6 | Shift.CLOSE | `turnos.otros` aceptado pero descartado; limpieza nativa omitida (mesas, PRODUCTOSENPRODUCCION, reset completo de folios, notes) | `SoftRestaurant11Adapter.ts:340-341,343` | Persistir todos los declarados (otros, notes) y hacer la limpieza nativa, tras resolver C-3 |
| M-7 | Shift.CLOSE | `serie=''` hardcodeada en reset de folios → rompe venues con series con nombre | `SoftRestaurant11Adapter.ts:343` (mismo en `:212,:222,:539,:559`) | Resolver la(s) serie(s) activa(s) del venue desde config |
| M-8 | Order.CREATE | Orden creada con `idturno=0` y sin validación de turno abierto | `createEmptyOrder.ts:44`; reconciliado solo en pago | Validar turno abierto (o estampar `idturno` actual) al crear, reduciendo la ventana `idturno=0` |
| M-9 | Order.CREATE | Incompleto vs F7 nativo: ocupación (`mesas/mesasasignadas`) no escrita; totales seteados fuera de la tx (post-commit) | `createEmptyOrder.ts:37-69`; UPDATE `:74-77` tras `commit() :71` | Escribir ocupación nativa (o documentar bridge-only); plegar la inicialización de totales=0 dentro del INSERT |
| M-10 | Order.CREATE | **✅ ARREGLADO (Fase 5d):** `idarearestaurant` ← `data.posAreaId` (fb '01'); `idempresa` ← `getDefaultEmpresa` (fb '1'); `posAreaId` ya se lee. Queda pendiente la estación hardcodeada y la validación de existencia de área/empresa. | `createEmptyOrder.ts:44-45` (antes literales); `data.posAreaId` antes nunca leído (existe en `IPosAdapter.ts:35`) | ✅ posAreaId + idempresa resueltos; pendiente: estación de config + validar existencia de área/empresa |
| M-11 | Payment.APPLY | Sin validación de método de pago: `idformadepago` no en `formasdepago` lanza (→ drop) o se archiva no reconocido; tip difiere del nativo | `01-COMPLETE-INSTALL.sql:464-465` (sin lookup); nativo separa `importe` vs `propina` (`04-Native...:223`) | Validar `@PaymentMethod` contra `formasdepago` (devolver Success=0, no lanzar); decidir semántica de tip explícitamente |
| M-12 | Payment.APPLY | IVA 16% hardcodeado como fallback en recálculo parcial (latente, vía helper TS `updateOrderTotal`). **Parcial 5d:** el hardcode de `addItemToOrder` (`:59`) ya se quitó (lee `parametros.impuesto1` vía `getIvaRate`); **sigue abierto** el fallback `taxRate = 0.16` del helper `updateOrderTotal` (`:810`), que 5d NO tocó. | `SoftRestaurant11Adapter.ts:810` (`taxRate = 0.16`); `:59` ✅5d | Quitar el fallback 0.16 de `updateOrderTotal`; reusar `getIvaRate`/config; fallar fuerte si no se puede derivar |
| M-13 | cancelOrderItem | Auditoría de cancelación (razón/usuario) estructuralmente inalcanzable a Avoqado — sin trigger en `tempcancela/cancela/bitacorasistema` | `01-COMPLETE-INSTALL.sql` (4 triggers, ninguno en esas tablas); `cancelOrderItem` escribe `tempcancela`+`bitacorasistema` (`:156-171`) | Trigger AFTER INSERT en la tabla real de auditoría → EntityType 'cancellation', rama producer, routing key `pos.softrestaurant.cancellation.created` |
| M-14 | cancelOrderItem | Sin guard de idempotencia — re-entrega doble-aplica/mis-falla | `SoftRestaurant11Adapter.ts:136-142` (lanza en 0 filas, sin short-circuit) | Tratar "línea ya ausente" como éxito (no-op + ack); y/o clave de idempotencia en `tempcancela` |
| M-15 | Commander core | venueId entrante nunca validado contra config local (solo se valida el formato del routing key) | `commander.ts:48-51` (`keyParts[2]` sin usar); contraste `configurationErrorConsumer.ts:61-66` | Aseverar `keyParts[2] === config.venueId` antes de despachar; en mismatch nackear a DLQ |
| M-16 | Commander core | Sin validación de esquema de payload — comandos JSON-válidos pero malformados lanzan a mitad del handler y se dropean | `commander.ts:45,61-63,71-73,...`; `IPosAdapter` usa `[key: string]: any` (`:3-14`) | Validar payload con zod/joi por `entity.action` antes de despachar; rutear fallos de esquema a la DLQ; tipar los payloads |
| M-17 | tx-integrity | `createEmptyOrder` hace UPDATE de totales FUERA de la tx, tras commit — no atómico; fila medio-inicializada visible; `rollback()` llamado tras commit | `createEmptyOrder.ts:71,74-77,80-84` | Mover la inicialización de totales al INSERT; no llamar `rollback()` incondicionalmente tras posible commit (guard con flag `committed`) |
| M-18 | tx-integrity | Métodos legacy inalcanzables (`applyPayment`, `closeAndPayOrder`). **5b/5d:** el SQL placeholder `'...'` ya se eliminó (`applyPayment` INSERT real ✅5d; `bitacorasistema` de cancelOrderItem ✅5b). **Sigue abierto:** `applyPayment` ejecuta el INSERT **sin tx** y ambos siguen sin cablear → borrar o cablear con tx. | `SoftRestaurant11Adapter.ts:198-200` (applyPayment INSERT real pero sin tx ✅5d) | Borrar los legacy inalcanzables o cablearlos con tx (el SQL placeholder ya no es el problema) |
| M-19 | tx-integrity | El handler `pool.on('error')` anula el pool mientras hay transacciones en vuelo → tx huérfanas/abortadas, rollback sin conexión limpia | `db.ts:72-77`; `getDbPool` lanza si null (`:106-111`); métodos crean `new sql.Transaction(getDbPool())` una vez al inicio | No anular el pool compartido en errores transitorios mientras hay trabajo en vuelo; capturar el pool en local al inicio del método; tratar comandos interrumpidos por error de pool como transitorios (retry) |
| M-20 | table-ops | Si se cableara tal cual, `splitOrderItems` corrompería totales de cabecera y estado de pago (incompleto + no idempotente) | `SoftRestaurant11Adapter.ts:670-744,605-633`; `updateOrderTotal:793` (taxRate 0.16, `totalarticulos=1.0`) | No cablear tal cual; cualquier implementación real debe recomputar totales padre+hijo, derivar total hijo de líneas movidas, usar tasa real, escribir ocupación, y ser idempotente |
| M-21 | table-ops / print | Comandos desconocidos (split/merge/print futuros) ackeados-y-dropeados, no dead-lettered | `commander.ts:129-130`→`:134`; cola sin DLX `:161` | Default debe lanzar (→ catch → nack a DLQ de comandos) |

### 3.4 LOW

| ID | Operación | Hallazgo | Evidencia | Recomendación |
|---|---|---|---|---|
| L-1 | Shift.OPEN | Set de columnas de `turnos` parcial/hardcodeado (`idempresa='1'`, lookup `meseros` solo cosmético, sin `caja/serie/numturno`) | `SoftRestaurant11Adapter.ts:252-258,261-268` | Derivar `idempresa/idestacion` de config; alinear set de columnas con un alta nativa capturada |
| L-2 | Shift.CLOSE | Supuestos de tablas/columnas de limpieza y cobertura de auxiliares no verificados (sin trazas reales) | `SoftRestaurant11Adapter.ts:319,328`; ausencia de `info-softrest11/sql-traces` | Capturar el Corte Z nativo (`npm run monitor`/Extended Events), commitear la traza, derivar listas exactas |
| L-3 | OrderItem.CREATE | `movimiento` = MAX+1 sin lock → carrera/colisión | `SoftRestaurant11Adapter.ts:54-57` | `UPDLOCK` al leer MAX, o estrategia de secuencia consistente con el POS |
| L-4 | OrderItem.CREATE | **✅ ARREGLADO (Fase 5d):** `folio` migrado `sql.Int`→`sql.BigInt` en `addItemToOrder` (y en `Order.CREATE`/`openShift`/`applyPayment`/`closeAndPayOrder`/`cancelOrderItem`). | `SoftRestaurant11Adapter.ts:56,66,109` (antes `sql.Int`) | ✅ Resuelto en la ruta de comandos cableada; verificar que ningún binding `sql.Int` de folio quede en helpers no cableados |
| L-5 | OrderItem.CREATE | Side-effects nativos faltantes: sin `comanda/productosenproduccion` (KDS), WorkspaceId no escrito (vía DEFAULT), estación hardcodeada | `SoftRestaurant11Adapter.ts:61-77` | Decidir si los ítems Avoqado deben llegar a cocina; usar estación real; escribir WorkspaceId explícito |
| L-6 | Payment.APPLY | `applyIntelligentPayment` corre el SP fuera de tx de adaptador e ignora el skip idempotente en el mapeo de resultado | `SoftRestaurant11Adapter.ts:376-385,402-413`; SP retorna `Remaining=@OrderTotal` en skip (`:415`) | El SP debe señalar el skip idempotente distintamente; resolver folio dentro de la llamada al SP para evitar la carrera de lookup |
| L-7 | Payment.APPLY | Logging de debug pesado y sin acotar (~10 filas `AvoqadoDebugLog`/llamada) en la ruta de dinero | `01-COMPLETE-INSTALL.sql:388-571` (múltiples inserts); prune en `:640` | Gatear el logging verboso tras un flag; confirmar que el prune corre |
| L-8 | FastPayment.CREATE | `idturno` interpolado directo en SQL (no parametrizado); MAX(numcheque) sin lock | `SoftRestaurant11Adapter.ts:1093-1097` | Bindear `idturno` con `.input(... sql.BigInt ...)` y `UPDLOCK` en la derivación de numcheque |
| L-9 | FastPayment.CREATE | WorkspaceId omitido en 3 INSERTs — depende de DEFAULT; entidades relacionadas solo por folio | `SoftRestaurant11Adapter.ts:1038-1053,1081-1090,1145-1150` vs `createEmptyOrder.ts:14,41,45,54` | Generar uuidv4 y escribir WorkspaceId explícito en los 3 INSERTs para consistencia con `createEmptyOrder` |
| L-10 | FastPayment.CREATE | No escribe `mesas/mesasasignadas` ni `productosenproduccion` — parcial vs venta rápida nativa | `SoftRestaurant11Adapter.ts:995-1190` | Confirmar contra traza nativa F9 si escribe PRODUCTOSENPRODUCCION; espejarlo si el venue usa KDS |
| L-11 | cancelOrderItem | Match de `productosenproduccion` por `movimiento` puede no coincidir con la clave KDS nativa (no verificado) | `SoftRestaurant11Adapter.ts:145-149` | Capturar void nativo para confirmar las columnas clave de `productosenproduccion` |
| L-12 | tx-integrity | La mayoría de rollbacks en catch no están protegidos → un fallo de rollback enmascara el error original | `SoftRestaurant11Adapter.ts:178,232,280,349,1186`; `createEmptyOrder.ts:82` vs guard en `addItemToOrder:117-121` | Envolver cada rollback en try/catch interno y re-lanzar el error ORIGINAL; idealmente unificar vía `db.executeTransaction` |

---

## 4. Operaciones FALTANTES (la TPV las necesita, el adapter no las implementa) — lista priorizada

Priorizada por impacto en dinero/integridad y frecuencia de uso en piso:

1. **Cancelar línea de ítem** — `cancelOrderItem` existe pero NO cableado y roto (`'...'`, sin recalc). Riesgo directo de cobrar producto removido. (P0)
2. **Cancelar orden completa / void de cuenta** (`cancelado=1` + auditoría `cancela`) — sin comando, sin método, sin SP. Genera ventas fantasma al cierre. (P0)
3. **Modificadores / guarniciones / producto compuesto** (`modificador`, `idproductocompuesto`, `productocompuestoprincipal`, `mitad`) — sin soporte de escritura; `addItemToOrder` no puede enviar modificadores. Comida equivocada en cocina. (P0)
4. **Descuento por ítem** (`descuento` + `idtipodescuento/usuariodescuento/comentariodescuento`) — sin comando. Descuento se vuelve precio completo. (P1)
5. **Reembolso / reversa de un pago aplicado** — sin comando (solo `Payment.APPLY` hacia adelante). (P1)
6. **Descuento a nivel cuenta** (`tempcheques.descuento/descuentoimporte`) — sin comando. (P1)
7. **Editar comentario de ítem** (post-alta) — solo seteable en alta vía `addItemToOrder.notes`. (P2)
8. **Override de precio por ítem / cambio de precio** — sin comando. (P2)
9. **Curso/tiempo por ítem** (`tiempo`, `horaproduccion`, marcar/enviar a cocina) — sin comando. (P2)
10. **Imprimir cuenta / pre-cuenta** (`impreso=1` + `numcheque`) como operación discreta — sin comando. (P2)
11. **Propina a nivel cuenta / ajuste de propina** (separada del pago; `createFastPayment` hardcodea `propina=0`) — sin comando. (P2)
12. **Dividir cuenta** (helpers `createSplitOrder/splitOrderItems` son código muerto) — sin comando. (P2)
13. **Juntar cuentas** — sin comando. (P2)
14. **Transferir ítems entre cuentas** — sin comando. (P2)
15. **Cambiar mesa** — sin comando. (P2)
16. **Cambiar # de comensales / asignar cliente / cambiar mesero** post-creación — solo en alta. (P3)
17. **Entrada/salida de efectivo, retiro, corte X** (`movimientoscaja`, `retiro`) — sin comando (y sin trigger en observe). (P3)
18. **Delivery / Domicilio** (driver, dirección, estado) — no modelado. (P3)
19. **Push de catálogo** (productos/métodos/meseros/áreas/clientes) POS→plataforma — sin comando. (P3)
20. **CFDI / timbrado** — fuera de alcance (PREMIUM server-side). (P3)

---

## 5. Riesgos transversales

### 5.1 Commander (`src/components/commander.ts` + `src/core/rabbitmq.ts`)

- **DLQ inexistente para comandos (CRITICAL, C-1).** `assertQueue(queueName, { durable: true })` (`:161`) sin `x-dead-letter-exchange`. Ambos `nack(msg,false,false)` (`:39` JSON inválido, `:148` error de ejecución) **dropean** en vez de dead-letterar. Los comentarios "Enviar a la Dead-Letter Queue" (`:34,:148`) son **falsos** para esta cola. El DLX solo está en `AVOQADO_EVENTS_QUEUE` (`rabbitmq.ts:68-74`).
- **Comando desconocido = ack-and-drop (HIGH).** El `default` (`:129-130`) solo hace `log.warn` y cae a `channel.ack(msg)` (`:134`). Todo comando no implementado (cancel, split, print, modificadores) o con typo (`OrderItem.Update` vs `OrderItem.UPDATE`) se traga en silencio → la TPV cree que se ejecutó.
- **Sin idempotencia (CRITICAL, C-2).** `ack` tras `await` (`:134`); RabbitMQ at-least-once. Solo `Payment.APPLY` protegido. La tabla `AvoqadoCommands` (con `CommandId`) existe pero no se usa.
- **venueId entrante no validado (MEDIUM, M-15).** Solo se valida el formato del routing key (`:48-51`); `keyParts[2]` nunca se compara con `config.venueId`. El aislamiento depende enteramente del binding.
- **Sin validación de esquema de payload (MEDIUM, M-16).** Payloads JSON-válidos pero malformados lanzan a mitad del handler y se dropean. `IPosAdapter` usa `[key: string]: any`.
- **Gate de versión rígido.** `startCommander` (`:175`) solo arranca el consumer si `config.posVersion.startsWith('11')`. Un venue v10 **no consume comandos** (no-op silencioso, no error). Un `posVersion='12.x'` literal también fallaría el gate — confirmar que v12 reporta `posVersion` con prefijo '11'.

### 5.2 Integridad transaccional del adapter (`src/adapters/SoftRestaurant11Adapter.ts` + `src/services/Orders/createEmptyOrder.ts` + `src/core/db.ts`)

- **`closeShift` rompe atomicidad por diseño (CRITICAL, C-3/H-13):** archivado placeholder `'...'` + `DELETE temp*` antes de `cierre`/sin verificación de conteos.
- **`createEmptyOrder` no es atómico (MEDIUM, M-17):** UPDATE de totales post-commit fuera de la tx; `rollback()` llamado tras posible commit.
- **Código muerto sin tx (MEDIUM, M-18):** `applyPayment` (`:198-200`, sin tx; el `'...'` ya se reemplazó por INSERT real en 5d) y `closeAndPayOrder` siguen sin cablear. (El placeholder `'...'` de `cancelOrderItem`/`bitacorasistema` se quitó en 5b.) Bombas latentes el día que se cableen — pero ya no por SQL inválido.
- **Pool compartido anulado en vuelo (MEDIUM, M-19):** `pool.on('error')` (`db.ts:72-77`) puede dejar transacciones huérfanas.
- **Rollbacks en catch sin proteger (LOW, L-12):** enmascaran el error original; solo `addItemToOrder` lo hace bien.
- **Hardcodes que rompen multi-tenant:** **✅ corregidos en Fase 5d:** IVA de `addItemToOrder` (ahora `parametros.impuesto1` vía `getIvaRate`), `idarearestaurant='01'` y `idempresa='1'` de `createEmptyOrder` (ahora `data.posAreaId`/`getDefaultEmpresa`), `WorkspaceId` hardcodeado en `Order.CREATE`/`openShift` (ahora version-aware), `folio` como `sql.Int` sobre BIGINT (ahora `sql.BigInt`). **Siguen abiertos:** IVA en `createFastPayment` (=0, H-30) y fallback `0.16` del helper `updateOrderTotal:810` (M-12); `idempresa='0000000001'` y `idarearestaurant='01'` en `createFastPayment` (H-31); `serie=''` (M-7); estación `'AVOQADO_SYNC'`; `MAX+1` sin lock para `idturno`/`movimiento`/`numcheque` (M-1 mitigado al considerar `parametros.ultimoturno` pero sin lock; L-3, H-29).

---

## 6. Plan de blindaje priorizado (Fase 5.x)

> **Estado:** **Fase 5a — HECHA** (detener el sangrado a nivel transporte): DLQ de comandos (5a-1, ✅) + idempotencia a nivel Commander vía `AvoqadoProcessedCommands` (5a-2, ◑ parcial — requiere `commandId` estable del backend, hoy fail-open). **Fase 5b — HECHA (parcial):** remoción del SQL placeholder `'...'` de `cancelOrderItem`/`bitacorasistema` + recálculo de totales (la implementación real de `closeShift` y el cableado de `cancelOrderItem` siguen pendientes). **Fase 5d — HECHA** (quitar hardcodes de dinero/versión vía `posMeta.ts`): `Order.CREATE`/`openShift` version-aware (H-9 ✅, rama v10 pendiente de validación en vivo), IVA de `addItemToOrder` desde `parametros.impuesto1`, `posAreaId`/`idempresa` de config en `Order.CREATE`, `applyPayment` INSERT real (cierra H-19 con 5b), folios `sql.Int`→`sql.BigInt`. **Pendiente: Fase 5b** (resto — `closeShift` placeholder/destructivo y cablear `cancelOrderItem`) y **Fase 5c** (implementar operaciones faltantes — cancel orden, modificadores/descuentos, imprimir, split/merge/transfer/cambiar mesa).

### Fase 5.1 — Detener el sangrado (transversal, desbloquea todo lo demás)
1. **DLX/DLQ para la cola de comandos.** En `assertTopology()` (`rabbitmq.ts`) declarar `commands_dead_letter_queue` atada a `DEAD_LETTER_EXCHANGE` con routing key `dead-letter.commands`; en `commander.ts:161` asertar la cola con `arguments: { 'x-dead-letter-exchange': DEAD_LETTER_EXCHANGE, 'x-dead-letter-routing-key': 'dead-letter.commands' }`. Como cambiar args de cola durable requiere borrar+recrear, **versionar el nombre** (`commands_queue.v2.venue_*`) o documentar la migración. Alertar sobre profundidad. (C-1, H-12, H-17, H-21, M-5, M-21)
2. **`default` del switch debe LANZAR**, no ackear (`commander.ts:129-130`). Distinguir transitorio (requeue acotado) de permanente (DLQ). (H-23, H-25, H-28)
3. **Idempotencia de comandos.** Exigir `commandId` (AMQP `messageId` o campo de payload); registrarlo en `AvoqadoCommands` **en la misma tx** que la escritura; en re-entrega, `ack` sin re-ejecutar. (C-2, H-2, H-10, H-16, H-32) — Regla 5-scripts SQL al tocar `AvoqadoCommands`.

### Fase 5.2 — Arreglar lo roto
4. **`closeShift`:** gatear con `NOT_IMPLEMENTED` al inicio (mientras el Corte Z nativo sea la fuente de verdad). Al implementar de verdad: `sp_BeginShiftArchiving`/`sp_EndShiftArchiving`, `cierre` antes de DELETEs, INSERTs column-exact con verificación de `@@ROWCOUNT == conteo_temp`, archivado de auxiliares, guard de doble-cierre. **Capturar traza nativa primero.** (C-3, H-13, H-14, H-15, M-5, M-6, M-7, L-2) — Regla 5-scripts + doc-sync.
5. **`addItemToOrder` recálculo de cabecera con `cantidad`** (`SUM(precio*cantidad)`...) + test de regresión. (H-1)
6. **`cancelOrderItem`:** reemplazar el INSERT `bitacorasistema` `'...'` por SQL válido; recalcular totales tras el DELETE (SUM, manejando orden vacía); cablear `OrderItem.CANCEL` con validación; idempotencia ("línea ausente" = no-op). (H-18, H-19, H-20, M-13, M-14, L-11)

### Fase 5.3 — Implementar lo faltante (con decisión de tier/producto donde aplique)
7. **Cancelar orden completa** (`Order.CANCEL` → `cancelOrder` con `cancelado=1` + auditoría `cancela` + `productosenproduccion`). (H-22)
8. **Modificadores + descuento por ítem + comentario-edit + curso** (`OrderItem.UPDATE`/`MODIFIER`/`DISCOUNT`/`COMMENT`/`COURSE`). (H-24)
9. **Imprimir cuenta** (`Order.PRINT` → `printBill`, idempotente, `folios` con `TABLOCKX`). (H-27, H-29)
10. **Dividir/juntar/transferir/cambiar mesa** — primero decidir alcance; si va, comandos explícitos con SQL nativo fiel; si no, **eliminar los helpers muertos** y documentar observe-only. (H-26, M-20)

### Fase 5.4 — Endurecer correctitud/dinero
11. **`Payment.APPLY` total**: portar el bloque nativo (`numcheque/impreso/cierre`, `folios.ultimofolio`, distribución `efectivo/tarjeta/...`). (H-4) — doc-sync con `04-Native-Payment-Flow`.
12. **`Payment.APPLY` parcial**: dejar de re-escalar `cantidad`; usar filas de pago + balance. (H-5) — **decisión de tier (toca inventario PREMIUM)**.
13. **`Reference` obligatoria** para `Payment.APPLY` (validar en `commander.ts`) + índice único `folio+referencia`. (H-6)
14. **Validación de método de pago** contra `formasdepago` (no lanzar; devolver Success=0). (M-11)
15. **`FastPayment` IVA real** (no `impuesto1=0`) + idempotencia por referencia + `numcheque` desde `folios`. (H-16, H-29, H-30)

### Fase 5.5 — Quitar hardcodes y rigidez de versión
16. **`Order.CREATE` version-aware** — **✅ HECHO (Fase 5d)** (omite `WorkspaceId` en v10 vía `detectUsesWorkspaceId`, usa `posAreaId`, `idempresa` de `getDefaultEmpresa`; **rama v10 pendiente de validación en vivo**). **Pendiente:** ocupación nativa + totales dentro de la tx. (H-9 ✅, M-8, M-9, M-10 parcial, M-17)
17. **Reconciliar `idempresa`** entre `createEmptyOrder` (ahora `getDefaultEmpresa` ✅5d) y `createFastPayment` (aún `'0000000001'`); derivar `createFastPayment` de config. (H-31)
18. **Quitar fallback IVA 0.16** — `addItemToOrder` ✅ HECHO (Fase 5d, lee `parametros.impuesto1`); **pendiente** el fallback `0.16` del helper `updateOrderTotal`. (M-12 parcial)
19. **`idturno`/`movimiento`/`numcheque` bajo lock** (pendiente; M-1 mitigado en 5d al considerar `parametros.ultimoturno`, sin lock); **bindear folios como `sql.BigInt`** ✅ HECHO (Fase 5d); parametrizar `idturno` interpolado (pendiente). (M-1 parcial, L-3, L-4 ✅, L-8)
20. **Unificar transacciones vía `db.executeTransaction`** con rollback protegido y re-throw del error original; no anular el pool en vuelo. (M-19, L-12)
21. **Validación de venueId entrante** + **esquema de payload (zod)** + tipado de `IPosAdapter` (quitar `[key:string]: any`). (M-15, M-16)
22. **`Trg_Avoqado_Shifts`** disparar OPENED solo en altas reales. (M-4) — Regla 5-scripts.
23. **Limpiar código muerto** (split helpers, `updateOrderTotal`/`markOrderAsPaid`/`insertPaymentToPOS`/`getOrderData`/resolvers duplicados, `applyPayment`/`closeAndPayOrder` legacy). (M-18, M-20)

> **Recordatorio de reglas del repo:** todo cambio en objetos SQL debe sincronizarse en los 5 scripts (`01-COMPLETE-INSTALL.sql`, `00-CLEANUP-ALL.sql`, `00-VERIFICATION.sql`, `02-TESTING.sql`, `03-DIAGNOSTICS.sql`); todo cambio de comportamiento/superficie debe reflejarse en `CLAUDE.md`/`AGENTS.md`/`docs/SoftRestaurant_Master_Documentation.md`; toda nueva capacidad de sync que corresponda a una feature de plataforma con tier debe consultarse con el founder antes de shippear, y mantenerse en lockstep con el MCP (`avoqado-server/scripts/mcp/`) y la presentación de ventas. Cada cambio debe verificarse contra v10 **y** v11 (v12 va por la ruta v11/WorkspaceId).