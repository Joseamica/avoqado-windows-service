import { log } from './logger';
import EventEmitter from 'events';

export enum ServiceState {
  RUNNING = 'RUNNING',
  CONFIGURATION_ERROR = 'CONFIGURATION_ERROR', 
  RECONFIGURING = 'RECONFIGURING',
  STOPPED = 'STOPPED'
}

export interface ConfigurationError {
  errorType: string;
  invalidVenueId: string;
  instanceId: string;
  message: string;
  timestamp: string;
  requiresReconfiguration: boolean;
}

class ServiceStateManager extends EventEmitter {
  private currentState: ServiceState = ServiceState.STOPPED;
  private lastError: ConfigurationError | null = null;
  private stateHistory: Array<{ state: ServiceState; timestamp: Date; reason?: string }> = [];

  constructor() {
    super();
    this.addStateToHistory(ServiceState.STOPPED, 'Initial state');
  }

  private addStateToHistory(state: ServiceState, reason?: string) {
    this.stateHistory.push({
      state,
      timestamp: new Date(),
      reason
    });
    
    // Keep only last 50 state changes
    if (this.stateHistory.length > 50) {
      this.stateHistory = this.stateHistory.slice(-50);
    }
  }

  public getCurrentState(): ServiceState {
    return this.currentState;
  }

  public getLastError(): ConfigurationError | null {
    return this.lastError;
  }

  public getStateHistory(): Array<{ state: ServiceState; timestamp: Date; reason?: string }> {
    return [...this.stateHistory];
  }

  public isHealthy(): boolean {
    return this.currentState === ServiceState.RUNNING;
  }

  public canSendHeartbeats(): boolean {
    return this.currentState === ServiceState.RUNNING;
  }

  public setState(newState: ServiceState, reason?: string): void {
    const previousState = this.currentState;
    
    if (previousState === newState) {
      return; // No state change
    }

    log.info(`[Service State] Cambiando estado de ${previousState} a ${newState}${reason ? ` - ${reason}` : ''}`);
    
    this.currentState = newState;
    this.addStateToHistory(newState, reason);
    
    // Emit state change event
    this.emit('stateChanged', {
      previousState,
      newState,
      reason,
      timestamp: new Date()
    });

    // Log state-specific information
    switch (newState) {
      case ServiceState.RUNNING:
        log.info('[Service State] ✅ Servicio operando normalmente');
        this.lastError = null;
        break;
      case ServiceState.CONFIGURATION_ERROR:
        log.warn('[Service State] ⚠️ Error de configuración detectado');
        break;
      case ServiceState.RECONFIGURING:
        log.info('[Service State] 🔧 Reconfigurando servicio');
        break;
      case ServiceState.STOPPED:
        log.info('[Service State] ⏹️ Servicio detenido');
        break;
    }
  }

  public setConfigurationError(error: ConfigurationError): void {
    this.lastError = error;
    this.setState(ServiceState.CONFIGURATION_ERROR, `Invalid venueId: ${error.invalidVenueId}`);
    
    log.error('[Service State] 🚨 Error de configuración:', {
      errorType: error.errorType,
      invalidVenueId: error.invalidVenueId,
      message: error.message,
      timestamp: error.timestamp
    });
  }

  public startReconfiguration(): void {
    if (this.currentState !== ServiceState.CONFIGURATION_ERROR) {
      log.warn('[Service State] Intento de reconfiguración desde estado no válido:', this.currentState);
      return;
    }
    
    this.setState(ServiceState.RECONFIGURING, 'Usuario inició reconfiguración');
  }

  public completeReconfiguration(success: boolean, newVenueId?: string): void {
    if (this.currentState !== ServiceState.RECONFIGURING) {
      log.warn('[Service State] Intento de completar reconfiguración desde estado no válido:', this.currentState);
      return;
    }

    if (success) {
      this.setState(ServiceState.RUNNING, `Reconfiguración exitosa${newVenueId ? ` con venueId: ${newVenueId}` : ''}`);
    } else {
      this.setState(ServiceState.CONFIGURATION_ERROR, 'Fallo en reconfiguración');
    }
  }

  public stop(reason?: string): void {
    this.setState(ServiceState.STOPPED, reason || 'Parada manual');
  }

  public start(): void {
    if (this.currentState === ServiceState.STOPPED) {
      this.setState(ServiceState.RUNNING, 'Inicio manual');
    }
  }
}

// Singleton instance
export const serviceStateManager = new ServiceStateManager();
