import { ConsumeMessage } from 'amqplib'
import { log } from '../core/logger'
import { getRabbitMQChannel, onReconnect, POS_COMMANDS_EXCHANGE } from '../core/rabbitmq'
import { serviceStateManager, ConfigurationError } from '../core/serviceState'
import { loadConfig } from '../config'
import { stopHeartbeat, getInstanceId } from './producer'
import { notifyConfigurationError } from '../core/windowsNotification'

interface ConfigurationErrorMessage {
  entity: 'Configuration'
  action: 'ERROR'
  payload: ConfigurationError
}

// Track configuration error patterns to avoid false positives
interface ErrorTracker {
  consecutiveErrors: number
  lastErrorTime: Date
  errorHistory: Array<{
    timestamp: Date
    errorType: string
    details: string
  }>
}

const MAX_CONSECUTIVE_ERRORS = 3
const ERROR_COOLDOWN_MS = 2 * 60 * 1000 // 2 minutes cooldown
const MAX_ERROR_HISTORY = 10

let isConsumerRunning = false
let configErrorQueue: string | null = null
let consumerTag: string | null = null
let reconnectHandlerRegistered = false
let errorTracker: ErrorTracker = {
  consecutiveErrors: 0,
  lastErrorTime: new Date(0),
  errorHistory: []
}

const handleConfigurationError = async (msg: ConsumeMessage | null) => {
  if (!msg) return

  const channel = getRabbitMQChannel()
  let routingKey = 'unknown_routing_key'

  try {
    const errorMessage: ConfigurationErrorMessage = JSON.parse(msg.content.toString())
    routingKey = msg.fields.routingKey

    log.info(`[Config Error Consumer] Error recibido: ${routingKey}`)

    const { entity, action, payload } = errorMessage

    if (entity !== 'Configuration' || action !== 'ERROR') {
      log.warn(`[Config Error Consumer] Mensaje no es error de configuración: ${entity}.${action}`)
      channel.ack(msg)
      return
    }

    // Verificar que el error es para esta instancia
    const currentInstanceId = await getInstanceId()
    if (payload.instanceId !== currentInstanceId) {
      log.info(`[Config Error Consumer] Error no es para esta instancia (${currentInstanceId}), ignorando`)
      channel.ack(msg)
      return
    }

    log.error(`[Config Error Consumer] 🚨 Error de configuración recibido:`, {
      errorType: payload.errorType,
      invalidVenueId: payload.invalidVenueId,
      message: payload.message,
      timestamp: payload.timestamp,
    })

    // Procesar el error según su tipo
    switch (payload.errorType) {
      case 'INVALID_VENUE_ID':
        await handleInvalidVenueIdError(payload)
        break
      default:
        log.warn(`[Config Error Consumer] Tipo de error no reconocido: ${payload.errorType}`)
    }

    channel.ack(msg)
    log.info(`[Config Error Consumer] Mensaje de error procesado y confirmado`)
  } catch (error) {
    log.error(`[Config Error Consumer] 🔥 Error procesando mensaje de configuración:`, error)
    channel.nack(msg, false, false) // No requeue - send to DLQ if configured
  }
}

const handleInvalidVenueIdError = async (errorPayload: ConfigurationError) => {
  try {
    const now = new Date()
    const timeSinceLastError = now.getTime() - errorTracker.lastErrorTime.getTime()

    // Add to error history
    errorTracker.errorHistory.push({
      timestamp: now,
      errorType: errorPayload.errorType,
      details: errorPayload.message
    })

    // Keep only recent errors
    if (errorTracker.errorHistory.length > MAX_ERROR_HISTORY) {
      errorTracker.errorHistory.shift()
    }

    // Check if this might be a database connectivity issue
    const isDatabaseIssue = errorPayload.message?.includes('conectividad') ||
                           errorPayload.message?.includes('Database unhealthy') ||
                           (errorPayload as any).additionalInfo?.databaseHealthy === false

    // Reset counter if enough time has passed or if this is a database issue
    if (timeSinceLastError > ERROR_COOLDOWN_MS || isDatabaseIssue) {
      errorTracker.consecutiveErrors = 0
      log.info(`[Config Error Consumer] Reset error counter due to ${isDatabaseIssue ? 'database issue' : 'cooldown period'}`)
    }

    errorTracker.consecutiveErrors++
    errorTracker.lastErrorTime = now

    log.error(`[Config Error Consumer] 🚨 VENUE ID ERROR (${errorTracker.consecutiveErrors}/${MAX_CONSECUTIVE_ERRORS}): ${errorPayload.invalidVenueId}`)
    log.error(`[Config Error Consumer] Error details: ${errorPayload.message}`)

    // Only take drastic action after multiple consecutive errors
    if (errorTracker.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
      log.error(`[Config Error Consumer] 🚨 ${MAX_CONSECUTIVE_ERRORS} errores consecutivos detectados. Deteniendo heartbeats...`)

      // 1. Stop heartbeats to prevent more errors
      stopHeartbeat()

      // 2. Update service state
      serviceStateManager.setConfigurationError(errorPayload)

      // 3. Log to Windows Event Log
      await logToWindowsEventLog(errorPayload)

      // 4. Show notification to administrator
      await notifyConfigurationError(errorPayload)

      log.warn('[Config Error Consumer] ⚠️ Servicio en modo de error de configuración. Se requiere reconfiguración manual.')
    } else {
      // Just log the error but keep running
      log.warn(`[Config Error Consumer] ⚠️ Error de configuración temporal (${errorTracker.consecutiveErrors}/${MAX_CONSECUTIVE_ERRORS}). ${isDatabaseIssue ? 'Problema de conectividad detectado.' : 'Esperando antes de tomar acción...'}`)

      if (isDatabaseIssue) {
        log.info('[Config Error Consumer] 💡 Esto parece ser un problema de conectividad a la base de datos. No se detendrán los heartbeats.')
      }
    }
  } catch (error) {
    log.error('[Config Error Consumer] Error manejando INVALID_VENUE_ID:', error)
  }
}

const logToWindowsEventLog = async (errorPayload: ConfigurationError): Promise<void> => {
  try {
    // For Windows Event Log, we'll use a simple log entry since we're in Node.js
    // In a production Windows service, this would use Windows API
    const eventMessage = `AVOQADO SYNC SERVICE - CONFIGURATION ERROR
    
Error Type: ${errorPayload.errorType}
Invalid Venue ID: ${errorPayload.invalidVenueId}
Instance ID: ${errorPayload.instanceId}
Message: ${errorPayload.message}
Timestamp: ${errorPayload.timestamp}

ACTION REQUIRED: Please reconfigure the service with a valid venue ID.`

    log.error(`[Windows Event Log] ${eventMessage}`)

    // In a real Windows service implementation, you would use:
    // - node-windows package for Windows Event Log integration
    // - Windows API calls through native modules
    // - PowerShell execution for event log writes
  } catch (error) {
    log.error('[Config Error Consumer] Error escribiendo al Event Log de Windows:', error)
  }
}

const bindConfigErrorConsumer = async (): Promise<void> => {
  const channel = getRabbitMQChannel()
  const { posType } = loadConfig()
  const instanceId = await getInstanceId()

  // Crear cola específica para esta instancia
  configErrorQueue = `config_errors_${posType}_${instanceId}`

  await channel.assertQueue(configErrorQueue, {
    durable: true,
    autoDelete: false,
    exclusive: false,
  })

  // Bind queue to exchange con routing key para errores de configuración
  const routingKey = `command.${posType}.configuration.error`
  await channel.bindQueue(configErrorQueue, POS_COMMANDS_EXCHANGE, routingKey)

  // Configurar consumer
  const consumeResult = await channel.consume(configErrorQueue, handleConfigurationError, {
    noAck: false, // Requerimos acknowledgment manual
  })
  consumerTag = consumeResult.consumerTag

  isConsumerRunning = true
  log.info(`[Config Error Consumer] ✅ Consumer iniciado para queue: ${configErrorQueue}, routing key: ${routingKey}`)
}

export const startConfigurationErrorConsumer = async (): Promise<void> => {
  // El consumer se (re)vincula al canal en CADA conexión exitosa (incluida la
  // primera). Antes vinculaba directo aquí y, si RabbitMQ no había conectado,
  // getRabbitMQChannel lanzaba y crasheaba el arranque. Un canal nuevo tampoco
  // hereda los consume() del anterior, así que esto cubre también el blip de red.
  if (!reconnectHandlerRegistered) {
    onReconnect(async () => {
      try {
        isConsumerRunning = false
        consumerTag = null
        await bindConfigErrorConsumer()
      } catch (error) {
        log.error('[Config Error Consumer] 🔥 Error vinculando consumer:', error)
      }
    })
    reconnectHandlerRegistered = true
  }
}

export const stopConfigurationErrorConsumer = async (): Promise<void> => {
  if (!isConsumerRunning || !consumerTag) {
    return
  }

  try {
    const channel = getRabbitMQChannel()
    // channel.cancel espera el consumerTag devuelto por consume(), no el
    // nombre de la cola (antes se pasaba la cola y la cancelación era un no-op).
    await channel.cancel(consumerTag)

    isConsumerRunning = false
    consumerTag = null
    log.info('[Config Error Consumer] Consumer detenido')
  } catch (error) {
    log.error('[Config Error Consumer] Error deteniendo consumer:', error)
  }
}

export const isConfigurationErrorConsumerRunning = (): boolean => {
  return isConsumerRunning
}

/**
 * Get current error tracking status for monitoring
 */
export const getErrorTrackingStatus = () => {
  return {
    consecutiveErrors: errorTracker.consecutiveErrors,
    lastErrorTime: errorTracker.lastErrorTime,
    errorHistory: errorTracker.errorHistory.slice(-5), // Last 5 errors
    isInErrorState: errorTracker.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS,
    timeUntilReset: Math.max(0, ERROR_COOLDOWN_MS - (Date.now() - errorTracker.lastErrorTime.getTime()))
  }
}

/**
 * Manually reset error tracking (for recovery purposes)
 */
export const resetErrorTracking = () => {
  log.info('[Config Error Consumer] 🔄 Resetting error tracking manually')
  errorTracker.consecutiveErrors = 0
  errorTracker.lastErrorTime = new Date(0)
  errorTracker.errorHistory = []
}

/**
 * Add success tracking to reset consecutive errors on successful operations
 */
export const recordSuccessfulHeartbeat = () => {
  if (errorTracker.consecutiveErrors > 0) {
    log.info(`[Config Error Consumer] ✅ Successful heartbeat after ${errorTracker.consecutiveErrors} errors. Resetting error counter.`)
    errorTracker.consecutiveErrors = 0
  }
}
