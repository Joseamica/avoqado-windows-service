import { log } from './logger'
import { serviceStateManager, ServiceState } from './serviceState'
import { connectToRabbitMQ, closeRabbitMQConnection } from './rabbitmq'
import { startConfigurationErrorConsumer } from '../components/configurationErrorConsumer'
import { restartProducer } from '../components/producer'
import { connectToSql, getDbPool, closeDbPool } from './db'

export interface ConnectionState {
  rabbitmq: boolean
  database: boolean
  lastCheck: Date
  lastError?: string
  consecutiveFailures: number
}

class ConnectionResilienceManager {
  private connectionState: ConnectionState = {
    rabbitmq: false,
    database: false,
    lastCheck: new Date(),
    consecutiveFailures: 0,
  }

  private reconnectAttempts = 0
  private maxReconnectAttempts = 10
  private reconnectInterval = 5000 // 5 seconds
  private healthCheckInterval: NodeJS.Timeout | null = null
  private isReconnecting = false
  private circuitBreakerOpen = false
  private circuitBreakerTimeout: NodeJS.Timeout | null = null
  private readonly CIRCUIT_BREAKER_THRESHOLD = 5
  private readonly CIRCUIT_BREAKER_RESET_TIME = 60000 // 1 minute

  constructor() {
    this.startHealthChecks()
  }

  private startHealthChecks(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval)
    }

    this.healthCheckInterval = setInterval(() => {
      this.performHealthCheck()
    }, 30000) // Check every 30 seconds

    log.info('[Connection Resilience] Health checks iniciados')
  }

  private async performHealthCheck(): Promise<void> {
    if (this.circuitBreakerOpen) {
      log.debug('[Connection Resilience] Circuit breaker open, skipping health check')
      return
    }

    if (this.isReconnecting) {
      log.debug('[Connection Resilience] Already reconnecting, skipping health check')
      return
    }

    try {
      // Update last check time
      this.connectionState.lastCheck = new Date()

      // Check database connection first
      await this.checkDatabaseHealth()

      // Check RabbitMQ connection
      await this.checkRabbitMQHealth()

      // If we reach here, connections are healthy
      if (this.reconnectAttempts > 0) {
        log.info('[Connection Resilience] ✅ Conexiones restauradas después de problemas')
        this.reconnectAttempts = 0
        this.connectionState.consecutiveFailures = 0
        this.resetCircuitBreaker()
      }
    } catch (error: any) {
      this.connectionState.lastError = error.message
      this.connectionState.consecutiveFailures++
      log.error(`[Connection Resilience] ❌ Health check failed (${this.connectionState.consecutiveFailures} consecutive):`, error.message)

      // Open circuit breaker if too many consecutive failures
      if (this.connectionState.consecutiveFailures >= this.CIRCUIT_BREAKER_THRESHOLD) {
        this.openCircuitBreaker()
      }

      await this.handleConnectionFailure()
    }
  }

  private async checkDatabaseHealth(): Promise<void> {
    try {
      const pool = getDbPool()
      // Simple query to test connection
      await pool.request().query('SELECT 1 as test')
      this.connectionState.database = true
    } catch (error) {
      this.connectionState.database = false
      throw new Error(`Database connection failed: ${error}`)
    }
  }

  private async checkRabbitMQHealth(): Promise<void> {
    try {
      // Try to get RabbitMQ channel (this will throw if connection is down)
      const { getRabbitMQChannel } = await import('./rabbitmq')
      const channel = getRabbitMQChannel()

      // Test channel with a basic operation
      await channel.checkQueue('')  // This will fail if channel is not healthy
      this.connectionState.rabbitmq = true
    } catch (error) {
      this.connectionState.rabbitmq = false
      throw new Error(`RabbitMQ connection failed: ${error}`)
    }
  }

  private async handleConnectionFailure(): Promise<void> {
    if (this.isReconnecting) {
      log.debug('[Connection Resilience] Already handling connection failure')
      return
    }

    this.reconnectAttempts++
    this.isReconnecting = true

    try {
      log.warn(`[Connection Resilience] ⚠️ Intento de reconexión ${this.reconnectAttempts}/${this.maxReconnectAttempts}`)

      if (this.reconnectAttempts >= this.maxReconnectAttempts) {
        log.error('[Connection Resilience] 🚨 Máximo número de intentos de reconexión alcanzado')
        serviceStateManager.stop('Conexiones perdidas permanentemente')
        return
      }

      // Exponential backoff with jitter
      const baseDelay = this.reconnectInterval * Math.pow(2, this.reconnectAttempts - 1)
      const jitter = Math.random() * 1000 // Add up to 1 second of jitter
      const delay = Math.min(baseDelay + jitter, 30000) // Cap at 30 seconds

      log.info(`[Connection Resilience] ⏳ Waiting ${Math.round(delay / 1000)}s before reconnection attempt...`)
      await this.sleep(delay)

      await this.attemptReconnection()
    } catch (error) {
      log.error('[Connection Resilience] Error en reconexión:', error)
    } finally {
      this.isReconnecting = false
    }
  }

  private async attemptReconnection(): Promise<void> {
    log.info('[Connection Resilience] 🔄 Intentando reconectar...')

    try {
      // Close existing connections gracefully
      log.info('[Connection Resilience] Closing existing connections...')
      await Promise.allSettled([
        closeRabbitMQConnection(),
        closeDbPool()
      ])

      // Wait a moment for cleanup
      await this.sleep(2000)

      // Reconnect to database first
      log.info('[Connection Resilience] Reconnecting to database...')
      await connectToSql()
      this.connectionState.database = true
      log.info('[Connection Resilience] ✅ Database reconnected')

      // Reconnect to RabbitMQ
      log.info('[Connection Resilience] Reconnecting to RabbitMQ...')
      await connectToRabbitMQ()
      this.connectionState.rabbitmq = true
      log.info('[Connection Resilience] ✅ RabbitMQ reconnected')

      // Restart configuration error consumer
      await startConfigurationErrorConsumer()
      log.info('[Connection Resilience] ✅ Configuration error consumer restarted')

      // If service was running, restart producer
      if (serviceStateManager.getCurrentState() === ServiceState.RUNNING) {
        restartProducer()
        log.info('[Connection Resilience] ✅ Producer restarted')
      }

      log.info('[Connection Resilience] 🎉 Full reconnection successful')
    } catch (error) {
      log.error('[Connection Resilience] ❌ Reconnection failed:', error)
      throw error
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms))
  }

  public getConnectionState(): ConnectionState {
    return { ...this.connectionState }
  }

  public async forceReconnection(): Promise<boolean> {
    if (this.isReconnecting) {
      log.warn('[Connection Resilience] Reconnection already in progress')
      return false
    }

    try {
      log.info('[Connection Resilience] 🔄 Force reconnection requested')
      this.reconnectAttempts = 0 // Reset attempts for manual retry
      this.connectionState.consecutiveFailures = 0
      this.resetCircuitBreaker()

      this.isReconnecting = true
      await this.attemptReconnection()
      return true
    } catch (error) {
      log.error('[Connection Resilience] Error in forced reconnection:', error)
      return false
    } finally {
      this.isReconnecting = false
    }
  }

  private openCircuitBreaker(): void {
    if (this.circuitBreakerOpen) return

    this.circuitBreakerOpen = true
    log.warn(`[Connection Resilience] 🚫 Circuit breaker opened after ${this.connectionState.consecutiveFailures} consecutive failures`)

    // Reset circuit breaker after timeout
    this.circuitBreakerTimeout = setTimeout(() => {
      this.resetCircuitBreaker()
    }, this.CIRCUIT_BREAKER_RESET_TIME)
  }

  private resetCircuitBreaker(): void {
    if (this.circuitBreakerTimeout) {
      clearTimeout(this.circuitBreakerTimeout)
      this.circuitBreakerTimeout = null
    }

    if (this.circuitBreakerOpen) {
      this.circuitBreakerOpen = false
      log.info('[Connection Resilience] ✅ Circuit breaker reset')
    }
  }

  public stop(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval)
      this.healthCheckInterval = null
    }

    if (this.circuitBreakerTimeout) {
      clearTimeout(this.circuitBreakerTimeout)
      this.circuitBreakerTimeout = null
    }

    this.resetCircuitBreaker()
    log.info('[Connection Resilience] Health checks stopped')
  }

  public getReconnectAttempts(): number {
    return this.reconnectAttempts
  }

  public getMaxReconnectAttempts(): number {
    return this.maxReconnectAttempts
  }

  public isCircuitBreakerOpen(): boolean {
    return this.circuitBreakerOpen
  }

  public getHealthStatus(): {
    healthy: boolean
    database: boolean
    rabbitmq: boolean
    reconnectAttempts: number
    consecutiveFailures: number
    circuitBreakerOpen: boolean
    lastError?: string
    lastCheck: Date
  } {
    return {
      healthy: this.connectionState.database && this.connectionState.rabbitmq,
      database: this.connectionState.database,
      rabbitmq: this.connectionState.rabbitmq,
      reconnectAttempts: this.reconnectAttempts,
      consecutiveFailures: this.connectionState.consecutiveFailures,
      circuitBreakerOpen: this.circuitBreakerOpen,
      lastError: this.connectionState.lastError,
      lastCheck: this.connectionState.lastCheck
    }
  }
}

// Singleton instance
export const connectionResilienceManager = new ConnectionResilienceManager()
