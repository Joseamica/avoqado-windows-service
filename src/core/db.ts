import sql, { ConnectionPool, Transaction } from 'mssql'
import { loadConfig } from '../config'
import { log } from './logger'

// Esta variable mantendrá la conexión viva
let pool: ConnectionPool | null = null
let isConnecting = false
let retryCount = 0
const MAX_RETRIES = 5
const RETRY_BASE_DELAY = 1000 // 1 second base delay

const connectWithRetry = async (): Promise<void> => {
  if (pool) return
  if (isConnecting) {
    // Wait for current connection attempt to finish
    while (isConnecting && !pool) {
      await new Promise(resolve => setTimeout(resolve, 100))
    }
    return
  }

  if (retryCount >= MAX_RETRIES) {
    const error = new Error(`SQL Server connection failed after ${MAX_RETRIES} attempts`)
    log.error('🔥 Maximum connection retry attempts reached:', error.message)
    throw error
  }

  isConnecting = true
  retryCount++

  try {
    const { sqlConfig } = loadConfig() // Obtenemos la config desde un solo lugar
    log.info('🔌 Conectando a SQL Server...')

    // Parse server and port if provided
    let server = sqlConfig.server
    let port: number | undefined = undefined

    if (sqlConfig.server.includes(',')) {
      // If server has comma, parse port explicitly (e.g., "100.80.118.68,49759")
      const parts = sqlConfig.server.split(',')
      server = parts[0]
      port = parseInt(parts[1])
    }
    // No else - let SQL Server use its default connection method (named instance or default port)

    // Creamos un nuevo objeto de configuración para la librería mssql
    const dbConfig: sql.config = {
      user: sqlConfig.user,
      password: sqlConfig.password,
      database: sqlConfig.database,
      server: server,
      port: port,
      pool: {
        max: 10,
        min: 0,
        idleTimeoutMillis: 30000,
      },
      options: {
        instanceName: port ? undefined : sqlConfig.instanceName, // Don't use instance name if port is specified
        encrypt: process.env.NODE_ENV === 'production' ? true : false, // Enable encryption in production
        trustServerCertificate: process.env.NODE_ENV === 'production' ? false : true, // Don't trust self-signed certs in production
        enableArithAbort: true, // Required for SQL Server 2014 compatibility
        abortTransactionOnError: true, // Abort transaction on error
      },
    }

    pool = await new ConnectionPool(dbConfig).connect()
    retryCount = 0 // Reset retry count on successful connection
    log.info('✅ Conexión con SQL Server establecida.')

    pool.on('error', err => {
      log.error('❌ Error en el pool de SQL Server:', err)
      // Reset pool to allow reconnection on pool errors
      pool = null
      isConnecting = false
    })
  } catch (error: any) {
    log.error(`🔥 SQL Server connection failed (attempt ${retryCount}/${MAX_RETRIES}):`, error.message)
    pool = null
    isConnecting = false

    if (retryCount < MAX_RETRIES) {
      // Exponential backoff: 1s, 2s, 4s, 8s, 16s
      const delay = RETRY_BASE_DELAY * Math.pow(2, retryCount - 1)
      log.info(`🔄 Retrying connection in ${delay}ms...`)
      await new Promise(resolve => setTimeout(resolve, delay))
      return await connectWithRetry()
    } else {
      // Max retries reached, throw the error
      throw new Error(`SQL Server connection failed after ${MAX_RETRIES} attempts: ${error.message}`)
    }
  } finally {
    if (retryCount >= MAX_RETRIES || pool) {
      isConnecting = false
    }
  }
}

export const connectToSql = async (): Promise<void> => {
  if (!pool) {
    await connectWithRetry()
  }
}

export const getDbPool = (): ConnectionPool => {
  if (!pool) {
    throw new Error('El pool de conexiones de SQL Server no ha sido inicializado.')
  }
  return pool
}

// Función de ayuda para ejecutar queries de forma segura
export const executeQuery = async (query: string): Promise<any[]> => {
  const pool = getDbPool()
  const result = await pool.request().query(query)
  return result.recordset
}

/**
 * Ejecuta una serie de operaciones de base de datos dentro de una transacción.
 * Asegura que todas las operaciones se completen con éxito (commit) o
 * se reviertan todas si alguna falla (rollback).
 *
 * @param action Una función async que recibe la transacción y contiene las queries a ejecutar.
 */
export const executeTransaction = async <T>(action: (transaction: Transaction) => Promise<T>): Promise<T> => {
  const pool = getDbPool()
  const transaction = pool.transaction()

  try {
    await transaction.begin()
    const result = await action(transaction)
    await transaction.commit()
    return result
  } catch (error) {
    log.error('❌ Error en la transacción. Revirtiendo cambios...', error)
    await transaction.rollback()
    // Relanzamos el error para que el código que llamó a la función sepa que algo salió mal.
    throw error
  }
}

export const closeDbPool = async (): Promise<void> => {
  if (pool) {
    log.info('🚪 Cerrando pool de SQL Server...')
    try {
      await pool.close()
    } catch (error) {
      log.error('Error closing SQL Server pool:', error)
    } finally {
      pool = null
      isConnecting = false
      retryCount = 0 // Reset retry count when closing
    }
  }
}
