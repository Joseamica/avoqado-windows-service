import fs from 'fs';
import path from 'path';
import { log } from './logger';
import { AppConfig, loadConfig, invalidateConfigCache } from '../config';
import { serviceStateManager, ServiceState } from './serviceState';
import { restartProducer } from '../components/producer';
import { notifyReconfigurationSuccess, notifyReconfigurationFailure } from './windowsNotification';

export interface ConfigurationBackup {
  timestamp: string;
  venueId: string;
  reason: string;
}

export interface ValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

class ConfigurationManager {
  private configBackups: ConfigurationBackup[] = [];
  private maxBackups = 10;

  constructor() {
    this.loadBackupHistory();
  }

  /**
   * Archivo de configuración ACTIVO según el entorno. Debe coincidir con lo
   * que lee loadConfig(): .env en desarrollo, config.json en producción.
   * (Antes siempre se escribía .env, así que reconfigurar en producción
   * modificaba un archivo que nadie leía.)
   */
  private getActiveConfigTarget(): { mode: 'env' | 'json'; filePath: string } {
    if (process.env.NODE_ENV === 'development') {
      return { mode: 'env', filePath: path.resolve(__dirname, '../../.env') };
    }
    return {
      mode: 'json',
      filePath: path.join(process.env.ProgramData || 'C:/ProgramData', 'AvoqadoSync', 'config.json'),
    };
  }

  private writeVenueIdToConfigSource(newVenueId: string): void {
    const { mode, filePath } = this.getActiveConfigTarget();

    if (mode === 'env') {
      const envContent = fs.readFileSync(filePath, 'utf8');
      const updatedContent = envContent.replace(/^VENUE_ID=.*$/m, `VENUE_ID=${newVenueId}`);
      fs.writeFileSync(filePath, updatedContent);
    } else {
      const fileConfig = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      fileConfig.venueId = newVenueId;
      fs.writeFileSync(filePath, JSON.stringify(fileConfig, null, 2));
    }

    // Sin invalidar el caché, loadConfig() seguiría devolviendo el venueId
    // viejo y el restart del producer no aplicaría nada.
    invalidateConfigCache();
  }

  private loadBackupHistory(): void {
    try {
      const backupFile = path.resolve(__dirname, '../../config-backups.json');
      if (fs.existsSync(backupFile)) {
        const data = fs.readFileSync(backupFile, 'utf8');
        this.configBackups = JSON.parse(data);
      }
    } catch (error) {
      log.warn('[Config Manager] Error cargando historial de backups:', error);
      this.configBackups = [];
    }
  }

  private saveBackupHistory(): void {
    try {
      const backupFile = path.resolve(__dirname, '../../config-backups.json');
      fs.writeFileSync(backupFile, JSON.stringify(this.configBackups, null, 2));
    } catch (error) {
      log.error('[Config Manager] Error guardando historial de backups:', error);
    }
  }

  private createBackup(currentVenueId: string, reason: string): void {
    const backup: ConfigurationBackup = {
      timestamp: new Date().toISOString(),
      venueId: currentVenueId,
      reason
    };

    this.configBackups.unshift(backup);
    
    // Mantener solo los últimos backups
    if (this.configBackups.length > this.maxBackups) {
      this.configBackups = this.configBackups.slice(0, this.maxBackups);
    }

    this.saveBackupHistory();
    log.info(`[Config Manager] Backup creado para venueId: ${currentVenueId}`);
  }

  /**
   * Valida un venueId antes de aplicarlo
   */
  public async validateVenueId(venueId: string): Promise<ValidationResult> {
    const result: ValidationResult = {
      isValid: true,
      errors: [],
      warnings: []
    };

    // Validaciones básicas
    if (!venueId || venueId.trim().length === 0) {
      result.errors.push('El venueId no puede estar vacío');
      result.isValid = false;
    }

    if (venueId.length < 10) {
      result.errors.push('El venueId debe tener al menos 10 caracteres');
      result.isValid = false;
    }

    if (venueId.length > 100) {
      result.errors.push('El venueId no puede exceder 100 caracteres');
      result.isValid = false;
    }

    // Validar formato (debe ser alfanumérico)
    if (!/^[a-zA-Z0-9_-]+$/.test(venueId)) {
      result.errors.push('El venueId solo puede contener letras, números, guiones y guiones bajos');
      result.isValid = false;
    }

    // Verificar si es diferente al actual
    try {
      const currentConfig = loadConfig();
      if (currentConfig.venueId === venueId) {
        result.warnings.push('El venueId es igual al actual');
      }
    } catch (error) {
      result.warnings.push('No se pudo cargar la configuración actual para comparar');
    }

    // Aquí podrías agregar validaciones adicionales como:
    // - Verificar conectividad con el servidor
    // - Validar formato específico del venueId
    // - Verificar permisos

    log.info(`[Config Manager] Validación de venueId ${venueId}: ${result.isValid ? 'VÁLIDO' : 'INVÁLIDO'}`);
    
    if (result.errors.length > 0) {
      log.warn('[Config Manager] Errores de validación:', result.errors);
    }
    
    if (result.warnings.length > 0) {
      log.info('[Config Manager] Advertencias de validación:', result.warnings);
    }

    return result;
  }

  /**
   * Actualiza el venueId en el archivo de configuración
   */
  public async updateVenueId(newVenueId: string, reason: string = 'Manual update'): Promise<boolean> {
    try {
      // Verificar que el servicio esté en estado de reconfiguración
      if (serviceStateManager.getCurrentState() !== ServiceState.CONFIGURATION_ERROR &&
          serviceStateManager.getCurrentState() !== ServiceState.RECONFIGURING) {
        log.warn('[Config Manager] Intento de actualización desde estado no válido:', serviceStateManager.getCurrentState());
        return false;
      }

      // Establecer estado de reconfiguración
      serviceStateManager.startReconfiguration();

      // Validar nuevo venueId
      const validation = await this.validateVenueId(newVenueId);
      if (!validation.isValid) {
        log.error('[Config Manager] venueId inválido:', validation.errors);
        await notifyReconfigurationFailure(`Validación fallida: ${validation.errors.join(', ')}`);
        serviceStateManager.completeReconfiguration(false);
        return false;
      }

      // Obtener configuración actual
      const currentConfig = loadConfig();
      
      // Crear backup
      this.createBackup(currentConfig.venueId, reason);

      // Escribir al archivo de configuración ACTIVO (env o json según entorno)
      // e invalidar el caché para que el restart lea el valor nuevo.
      this.writeVenueIdToConfigSource(newVenueId);

      log.info(`[Config Manager] ✅ venueId actualizado de ${currentConfig.venueId} a ${newVenueId}`);

      // Reiniciar el producer para aplicar la nueva configuración
      log.info('[Config Manager] Reiniciando producer con nueva configuración...');
      
      // Dar tiempo para que se procese
      setTimeout(async () => {
        try {
          restartProducer();
          serviceStateManager.completeReconfiguration(true, newVenueId);
          await notifyReconfigurationSuccess(newVenueId);
        } catch (error) {
          log.error('[Config Manager] Error reiniciando producer:', error);
          serviceStateManager.completeReconfiguration(false);
          await notifyReconfigurationFailure(`Error reiniciando: ${error}`);
        }
      }, 1000);

      return true;

    } catch (error) {
      log.error('[Config Manager] Error actualizando venueId:', error);
      serviceStateManager.completeReconfiguration(false);
      await notifyReconfigurationFailure(`Error técnico: ${error}`);
      return false;
    }
  }

  /**
   * Restaura una configuración desde backup
   */
  public async rollbackToBackup(backupIndex: number): Promise<boolean> {
    try {
      if (backupIndex < 0 || backupIndex >= this.configBackups.length) {
        log.error('[Config Manager] Índice de backup inválido:', backupIndex);
        return false;
      }

      const backup = this.configBackups[backupIndex];
      log.info(`[Config Manager] Restaurando backup del ${backup.timestamp} (${backup.reason})`);

      return await this.updateVenueId(backup.venueId, `Rollback to ${backup.timestamp}`);

    } catch (error) {
      log.error('[Config Manager] Error en rollback:', error);
      return false;
    }
  }

  /**
   * Obtiene el historial de configuraciones
   */
  public getConfigurationHistory(): ConfigurationBackup[] {
    return [...this.configBackups];
  }

  /**
   * Verifica si hay una configuración válida
   */
  public async verifyCurrentConfiguration(): Promise<ValidationResult> {
    try {
      const currentConfig = loadConfig();
      return await this.validateVenueId(currentConfig.venueId);
    } catch (error) {
      return {
        isValid: false,
        errors: [`Error cargando configuración: ${error}`],
        warnings: []
      };
    }
  }

  /**
   * Obtiene información del estado actual de configuración
   */
  public getConfigurationStatus(): {
    currentVenueId: string;
    serviceState: ServiceState;
    hasBackups: boolean;
    lastBackup?: ConfigurationBackup;
    isValid: boolean;
  } {
    try {
      const currentConfig = loadConfig();
      const lastBackup = this.configBackups.length > 0 ? this.configBackups[0] : undefined;

      return {
        currentVenueId: currentConfig.venueId,
        serviceState: serviceStateManager.getCurrentState(),
        hasBackups: this.configBackups.length > 0,
        lastBackup,
        isValid: serviceStateManager.isHealthy()
      };
    } catch (error) {
      return {
        currentVenueId: 'ERROR',
        serviceState: ServiceState.STOPPED,
        hasBackups: false,
        isValid: false
      };
    }
  }
}

// Singleton instance
export const configurationManager = new ConfigurationManager();
