import { log } from './logger';
import { serviceStateManager, ServiceState } from './serviceState';
import { connectToRabbitMQ, closeRabbitMQConnection } from './rabbitmq';
import { startConfigurationErrorConsumer } from '../components/configurationErrorConsumer';
import { restartProducer } from '../components/producer';

export interface ConnectionState {
  rabbitmq: boolean;
  database: boolean;
  lastCheck: Date;
}

class ConnectionResilienceManager {
  private connectionState: ConnectionState = {
    rabbitmq: false,
    database: false,
    lastCheck: new Date()
  };
  
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectInterval = 5000; // 5 seconds
  private healthCheckInterval: NodeJS.Timeout | null = null;
  
  constructor() {
    this.startHealthChecks();
  }

  private startHealthChecks(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval);
    }

    this.healthCheckInterval = setInterval(() => {
      this.performHealthCheck();
    }, 30000); // Check every 30 seconds

    log.info('[Connection Resilience] Health checks iniciados');
  }

  private async performHealthCheck(): Promise<void> {
    try {
      // Update last check time
      this.connectionState.lastCheck = new Date();

      // Check RabbitMQ connection
      await this.checkRabbitMQHealth();
      
      // If we reach here, connections are healthy
      if (this.reconnectAttempts > 0) {
        log.info('[Connection Resilience] ✅ Conexiones restauradas después de problemas');
        this.reconnectAttempts = 0;
      }

    } catch (error) {
      log.error('[Connection Resilience] ❌ Health check failed:', error);
      await this.handleConnectionFailure();
    }
  }

  private async checkRabbitMQHealth(): Promise<void> {
    try {
      // Try to get RabbitMQ channel (this will throw if connection is down)
      const { getRabbitMQChannel } = await import('./rabbitmq');
      const channel = getRabbitMQChannel();
      
      // If we can get the channel, connection is healthy
      this.connectionState.rabbitmq = true;
      
    } catch (error) {
      this.connectionState.rabbitmq = false;
      throw new Error(`RabbitMQ connection failed: ${error}`);
    }
  }

  private async handleConnectionFailure(): Promise<void> {
    this.reconnectAttempts++;
    
    log.warn(`[Connection Resilience] ⚠️ Intento de reconexión ${this.reconnectAttempts}/${this.maxReconnectAttempts}`);

    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      log.error('[Connection Resilience] 🚨 Máximo número de intentos de reconexión alcanzado');
      serviceStateManager.stop('Conexiones perdidas permanentemente');
      return;
    }

    // Wait before attempting reconnection
    await this.sleep(this.reconnectInterval * this.reconnectAttempts);

    try {
      await this.attemptReconnection();
    } catch (error) {
      log.error('[Connection Resilience] Error en reconexión:', error);
    }
  }

  private async attemptReconnection(): Promise<void> {
    log.info('[Connection Resilience] 🔄 Intentando reconectar...');

    try {
      // Close existing connections
      await closeRabbitMQConnection();
      
      // Wait a moment
      await this.sleep(2000);
      
      // Reconnect to RabbitMQ
      await connectToRabbitMQ();
      log.info('[Connection Resilience] ✅ RabbitMQ reconectado');
      
      // Restart configuration error consumer
      await startConfigurationErrorConsumer();
      log.info('[Connection Resilience] ✅ Configuration error consumer reiniciado');
      
      // If service was running, restart producer
      if (serviceStateManager.getCurrentState() === ServiceState.RUNNING) {
        restartProducer();
        log.info('[Connection Resilience] ✅ Producer reiniciado');
      }
      
      this.connectionState.rabbitmq = true;
      log.info('[Connection Resilience] 🎉 Reconexión exitosa');
      
    } catch (error) {
      log.error('[Connection Resilience] ❌ Fallo en reconexión:', error);
      throw error;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  public getConnectionState(): ConnectionState {
    return { ...this.connectionState };
  }

  public async forceReconnection(): Promise<boolean> {
    try {
      log.info('[Connection Resilience] 🔄 Reconexión forzada solicitada');
      this.reconnectAttempts = 0; // Reset attempts for manual retry
      await this.attemptReconnection();
      return true;
    } catch (error) {
      log.error('[Connection Resilience] Error en reconexión forzada:', error);
      return false;
    }
  }

  public stop(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval);
      this.healthCheckInterval = null;
    }
    log.info('[Connection Resilience] Health checks detenidos');
  }

  public getReconnectAttempts(): number {
    return this.reconnectAttempts;
  }

  public getMaxReconnectAttempts(): number {
    return this.maxReconnectAttempts;
  }
}

// Singleton instance
export const connectionResilienceManager = new ConnectionResilienceManager();
