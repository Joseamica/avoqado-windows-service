// core/commandDedup.ts
// Idempotencia de comandos (Avoqado -> POS) ATÓMICA con el efecto.
//
// El dedup viejo era SELECT-luego-INSERT en el Comandante, fuera de la transacción del
// efecto: no atómico. Dos entregas concurrentes (redelivery tras una reconexión) o un
// crash entre "efecto commiteado" y "registro escrito" podían APLICAR DOS VECES un comando
// no idempotente (Order.CREATE, Shift.OPEN, OrderItem.CREATE/CANCEL, Order.SPLIT, FastPayment).
//
// Aquí el "claim" del comando se inserta DENTRO de la misma transacción que el efecto: el
// registro de idempotencia y el efecto commitean o se revierten JUNTOS. Si el comando ya fue
// procesado, el INSERT viola la PK (AvoqadoProcessedCommands.CommandKey) -> lanzamos
// CommandAlreadyProcessedError, el método revierte y el Comandante hace ack+skip (no DLQ).
//
// FAIL-OPEN: si la tabla AvoqadoProcessedCommands no existe (instalación vieja), el guard
// `IF OBJECT_ID(...) IS NOT NULL` hace que el INSERT no se ejecute y el comando procede sin
// dedup — mismo comportamiento tolerante que antes, sin romper la transacción.
import sql from 'mssql'

/** Se lanza cuando el CommandKey ya existe (comando ya aplicado) -> ack+skip, NO DLQ. */
export class CommandAlreadyProcessedError extends Error {
  constructor(public readonly commandKey: string) {
    super(`Comando ${commandKey} ya aplicado (idempotente)`)
    this.name = 'CommandAlreadyProcessedError'
  }
}

const isDuplicateKeyError = (err: any): boolean => err && (err.number === 2627 || err.number === 2601)

/**
 * Reclama el comando DENTRO de la transacción `transaction`. Debe llamarse como PRIMER
 * statement tras `begin()`, antes de cualquier efecto, para que un duplicado falle barato.
 * - tabla ausente -> no-op (fail-open).
 * - clave ya existe (redelivery secuencial, el caso común) -> lanza CommandAlreadyProcessedError
 *   ANTES de cualquier INSERT, así la tx NO queda abortada y el caller puede revertir y propagar
 *   la sentinela limpiamente (-> el Comandante hace ack+skip).
 * - clave nueva -> INSERT; el efecto continúa en la misma tx.
 * - duplicado CONCURRENTE en vuelo (dos entregas a la vez, raro): el SELECT no ve la fila aún
 *   sin commitear, ambos INSERTan, uno gana y el otro viola la PK -> aborta -> la sentinela puede
 *   quedar enmascarada por el error de rollback -> el comando cae a la DLQ (fallback seguro: el
 *   efecto se aplicó exactamente una vez, el duplicado NO).
 */
export async function claimCommand(transaction: sql.Transaction, commandKey: string): Promise<void> {
  // 1) ¿existe la tabla? ¿ya está la clave? (un solo round-trip; el guard OBJECT_ID evita compilar
  //    la referencia a la tabla cuando no existe -> fail-open sin error).
  const check = await new sql.Request(transaction).input('k', sql.VarChar(200), commandKey).query(
    `IF OBJECT_ID('AvoqadoProcessedCommands') IS NULL
       SELECT 0 AS hasTable, 0 AS dup
     ELSE
       SELECT 1 AS hasTable, CASE WHEN EXISTS (SELECT 1 FROM AvoqadoProcessedCommands WHERE CommandKey=@k) THEN 1 ELSE 0 END AS dup`,
  )
  const row = check.recordset[0]
  if (!row || row.hasTable === 0) return // fail-open: instalación sin la tabla
  if (row.dup === 1) throw new CommandAlreadyProcessedError(commandKey) // duplicado secuencial: tx limpia

  // 2) clave nueva -> INSERT. La PK sigue protegiendo el caso concurrente (raro).
  try {
    await new sql.Request(transaction)
      .input('k', sql.VarChar(200), commandKey)
      .query('INSERT INTO AvoqadoProcessedCommands (CommandKey) VALUES (@k)')
  } catch (err: any) {
    if (isDuplicateKeyError(err)) {
      throw new CommandAlreadyProcessedError(commandKey)
    }
    throw err
  }
}
