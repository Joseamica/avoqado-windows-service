import { ConsumeMessage } from 'amqplib'
import { log } from '../core/logger'
import { getRabbitMQChannel, POS_COMMANDS_EXCHANGE } from '../core/rabbitmq'
import { serviceStateManager, ConfigurationError } from '../core/serviceState'
import { loadConfig } from '../config'
import { stopHeartbeat, getInstanceId } from './producer'
import { notifyConfigurationError } from '../core/windowsNotification'

interface ConfigurationErrorMessage {
  entity: 'Configuration'
  action: 'ERROR'
  payload: ConfigurationError
}

let isConsumerRunning = false
let configErrorQueue: string | null = null

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
    log.error(`[Config Error Consumer] 🚨 VENUE ID INVÁLIDO: ${errorPayload.invalidVenueId}`)

    // 1. Detener heartbeats para evitar más errores
    log.info('[Config Error Consumer] Deteniendo heartbeats...')
    stopHeartbeat()

    // 2. Actualizar estado del servicio
    serviceStateManager.setConfigurationError(errorPayload)

    // 3. Registrar en Event Log de Windows
    await logToWindowsEventLog(errorPayload)

    // 4. Mostrar notificación al administrador
    await notifyConfigurationError(errorPayload)

    log.warn('[Config Error Consumer] ⚠️ Servicio en modo de error de configuración. Se requiere reconfiguración manual.')
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

export const startConfigurationErrorConsumer = async (): Promise<void> => {
  if (isConsumerRunning) {
    log.warn('[Config Error Consumer] Consumer ya está corriendo')
    return
  }

  try {
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

    // Bind queue to exchange with routing key para errores de configuración
    const routingKey = `command.${posType}.configuration.error`
    await channel.bindQueue(configErrorQueue, POS_COMMANDS_EXCHANGE, routingKey)

    // Configurar consumer
    await channel.consume(configErrorQueue, handleConfigurationError, {
      noAck: false, // Requerimos acknowledgment manual
    })

    isConsumerRunning = true
    log.info(`[Config Error Consumer] ✅ Consumer iniciado para queue: ${configErrorQueue}, routing key: ${routingKey}`)
  } catch (error) {
    log.error('[Config Error Consumer] 🔥 Error iniciando consumer:', error)
    throw error
  }
}

export const stopConfigurationErrorConsumer = async (): Promise<void> => {
  if (!isConsumerRunning || !configErrorQueue) {
    return
  }

  try {
    const channel = getRabbitMQChannel()
    await channel.cancel(configErrorQueue)

    isConsumerRunning = false
    log.info('[Config Error Consumer] Consumer detenido')
  } catch (error) {
    log.error('[Config Error Consumer] Error deteniendo consumer:', error)
  }
}

export const isConfigurationErrorConsumerRunning = (): boolean => {
  return isConsumerRunning
}
