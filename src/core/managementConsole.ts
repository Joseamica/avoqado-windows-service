import readline from 'readline';
import { log } from './logger';
import { serviceStateManager, ServiceState } from './serviceState';
import { configurationManager } from './configurationManager';
import { startHeartbeat, stopHeartbeat, restartProducer, getInstanceId } from '../components/producer';
import { showConfirmationDialog } from './windowsNotification';

interface ConsoleCommand {
  command: string;
  description: string;
  handler: () => Promise<void>;
}

class ManagementConsole {
  private rl: readline.Interface;
  private isRunning = false;
  private commands: ConsoleCommand[] = [];

  constructor() {
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    this.setupCommands();
  }

  private setupCommands(): void {
    this.commands = [
      {
        command: 'status',
        description: 'Mostrar estado actual del servicio',
        handler: this.showStatus.bind(this)
      },
      {
        command: 'config',
        description: 'Mostrar información de configuración',
        handler: this.showConfiguration.bind(this)
      },
      {
        command: 'reconfig',
        description: 'Reconfigurar venueId',
        handler: this.reconfigureVenueId.bind(this)
      },
      {
        command: 'retry',
        description: 'Reintentar operación (reiniciar heartbeats)',
        handler: this.retryOperation.bind(this)
      },
      {
        command: 'restart',
        description: 'Reiniciar producer completo',
        handler: this.restartService.bind(this)
      },
      {
        command: 'history',
        description: 'Mostrar historial de configuraciones',
        handler: this.showConfigHistory.bind(this)
      },
      {
        command: 'rollback',
        description: 'Restaurar configuración anterior',
        handler: this.rollbackConfiguration.bind(this)
      },
      {
        command: 'validate',
        description: 'Validar configuración actual',
        handler: this.validateCurrentConfig.bind(this)
      },
      {
        command: 'help',
        description: 'Mostrar ayuda',
        handler: this.showHelp.bind(this)
      },
      {
        command: 'exit',
        description: 'Salir de la consola',
        handler: this.exit.bind(this)
      }
    ];
  }

  private async showStatus(): Promise<void> {
    console.log('\n' + '='.repeat(60));
    console.log('📊 ESTADO DEL SERVICIO AVOQADO SYNC');
    console.log('='.repeat(60));

    const currentState = serviceStateManager.getCurrentState();
    const isHealthy = serviceStateManager.isHealthy();
    const lastError = serviceStateManager.getLastError();

    // Estado general
    console.log(`Estado: ${this.getStateEmoji(currentState)} ${currentState}`);
    console.log(`Salud: ${isHealthy ? '✅ SALUDABLE' : '🚨 CON PROBLEMAS'}`);
    
    try {
      const instanceId = await getInstanceId();
      console.log(`Instance ID: ${instanceId}`);
    } catch (error) {
      console.log(`Instance ID: ❌ Error obteniendo ID`);
    }

    // Configuración actual
    const configStatus = configurationManager.getConfigurationStatus();
    console.log(`Venue ID: ${configStatus.currentVenueId}`);
    console.log(`Heartbeats: ${serviceStateManager.canSendHeartbeats() ? '✅ ACTIVOS' : '⏹️ DETENIDOS'}`);

    // Error actual si existe
    if (lastError) {
      console.log('\n🚨 ERROR ACTIVO:');
      console.log(`  Tipo: ${lastError.errorType}`);
      console.log(`  Venue ID Inválido: ${lastError.invalidVenueId}`);
      console.log(`  Mensaje: ${lastError.message}`);
      console.log(`  Timestamp: ${new Date(lastError.timestamp).toLocaleString()}`);
    }

    // Historial de estados recientes
    const stateHistory = serviceStateManager.getStateHistory().slice(-3);
    if (stateHistory.length > 0) {
      console.log('\n📜 ESTADOS RECIENTES:');
      stateHistory.reverse().forEach(entry => {
        console.log(`  ${entry.timestamp.toLocaleString()}: ${this.getStateEmoji(entry.state)} ${entry.state}${entry.reason ? ` (${entry.reason})` : ''}`);
      });
    }

    console.log('='.repeat(60) + '\n');
  }

  private getStateEmoji(state: ServiceState): string {
    switch (state) {
      case ServiceState.RUNNING: return '✅';
      case ServiceState.CONFIGURATION_ERROR: return '🚨';
      case ServiceState.RECONFIGURING: return '🔧';
      case ServiceState.STOPPED: return '⏹️';
      default: return '❓';
    }
  }

  private async showConfiguration(): Promise<void> {
    console.log('\n' + '='.repeat(60));
    console.log('⚙️ CONFIGURACIÓN ACTUAL');
    console.log('='.repeat(60));

    const configStatus = configurationManager.getConfigurationStatus();
    
    console.log(`Venue ID: ${configStatus.currentVenueId}`);
    console.log(`Estado del Servicio: ${configStatus.serviceState}`);
    console.log(`Configuración Válida: ${configStatus.isValid ? '✅ SÍ' : '❌ NO'}`);
    console.log(`Tiene Backups: ${configStatus.hasBackups ? '✅ SÍ' : '❌ NO'}`);

    if (configStatus.lastBackup) {
      console.log(`Último Backup: ${new Date(configStatus.lastBackup.timestamp).toLocaleString()}`);
      console.log(`  Venue ID: ${configStatus.lastBackup.venueId}`);
      console.log(`  Razón: ${configStatus.lastBackup.reason}`);
    }

    console.log('='.repeat(60) + '\n');
  }

  private async reconfigureVenueId(): Promise<void> {
    const currentState = serviceStateManager.getCurrentState();
    
    if (currentState !== ServiceState.CONFIGURATION_ERROR) {
      console.log('\n⚠️ La reconfiguración solo está disponible cuando hay un error de configuración.');
      console.log(`Estado actual: ${currentState}\n`);
      return;
    }

    console.log('\n🔧 RECONFIGURACIÓN DE VENUE ID');
    console.log('='.repeat(40));

    const newVenueId = await this.promptInput('Ingrese el nuevo Venue ID: ');
    
    if (!newVenueId || newVenueId.trim().length === 0) {
      console.log('❌ Venue ID no puede estar vacío.\n');
      return;
    }

    // Validar antes de aplicar
    console.log('🔍 Validando nuevo Venue ID...');
    const validation = await configurationManager.validateVenueId(newVenueId.trim());
    
    if (!validation.isValid) {
      console.log('❌ Validación fallida:');
      validation.errors.forEach(error => console.log(`  - ${error}`));
      console.log('');
      return;
    }

    if (validation.warnings.length > 0) {
      console.log('⚠️ Advertencias:');
      validation.warnings.forEach(warning => console.log(`  - ${warning}`));
    }

    // Confirmación
    const confirm = await this.promptInput(`¿Confirma actualizar el Venue ID a "${newVenueId.trim()}"? (s/N): `);
    
    if (confirm.toLowerCase() !== 's' && confirm.toLowerCase() !== 'si') {
      console.log('❌ Operación cancelada.\n');
      return;
    }

    console.log('🔄 Aplicando nueva configuración...');
    const success = await configurationManager.updateVenueId(newVenueId.trim(), 'Manual reconfiguration via console');
    
    if (success) {
      console.log('✅ Configuración actualizada exitosamente. El servicio se reiniciará automáticamente.\n');
    } else {
      console.log('❌ Error actualizando configuración. Verifique los logs para más detalles.\n');
    }
  }

  private async retryOperation(): Promise<void> {
    console.log('\n🔄 REINTENTAR OPERACIÓN');
    console.log('='.repeat(40));

    const currentState = serviceStateManager.getCurrentState();
    console.log(`Estado actual: ${currentState}`);

    switch (currentState) {
      case ServiceState.RUNNING:
        console.log('✅ El servicio ya está funcionando normalmente.');
        break;
        
      case ServiceState.CONFIGURATION_ERROR:
        console.log('🚨 Error de configuración detectado. Use "reconfig" para solucionar.');
        break;
        
      case ServiceState.STOPPED:
        console.log('🔄 Intentando reiniciar heartbeats...');
        startHeartbeat();
        serviceStateManager.start();
        console.log('✅ Heartbeats reiniciados.');
        break;
        
      default:
        console.log('🔄 Forzando reinicio de producer...');
        restartProducer();
        console.log('✅ Producer reiniciado.');
    }
    
    console.log('');
  }

  private async restartService(): Promise<void> {
    console.log('\n🔄 REINICIAR SERVICIO COMPLETO');
    console.log('='.repeat(40));

    const confirm = await this.promptInput('¿Confirma reiniciar el servicio completo? (s/N): ');
    
    if (confirm.toLowerCase() !== 's' && confirm.toLowerCase() !== 'si') {
      console.log('❌ Operación cancelada.\n');
      return;
    }

    console.log('🔄 Reiniciando servicio...');
    restartProducer();
    console.log('✅ Servicio reiniciado.\n');
  }

  private async showConfigHistory(): Promise<void> {
    console.log('\n' + '='.repeat(60));
    console.log('📜 HISTORIAL DE CONFIGURACIONES');
    console.log('='.repeat(60));

    const history = configurationManager.getConfigurationHistory();
    
    if (history.length === 0) {
      console.log('📭 No hay configuraciones anteriores guardadas.');
    } else {
      history.forEach((backup, index) => {
        console.log(`${index + 1}. ${new Date(backup.timestamp).toLocaleString()}`);
        console.log(`   Venue ID: ${backup.venueId}`);
        console.log(`   Razón: ${backup.reason}`);
        console.log('');
      });
    }

    console.log('='.repeat(60) + '\n');
  }

  private async rollbackConfiguration(): Promise<void> {
    console.log('\n🔙 RESTAURAR CONFIGURACIÓN ANTERIOR');
    console.log('='.repeat(40));

    const history = configurationManager.getConfigurationHistory();
    
    if (history.length === 0) {
      console.log('❌ No hay configuraciones anteriores para restaurar.\n');
      return;
    }

    console.log('Configuraciones disponibles:');
    history.forEach((backup, index) => {
      console.log(`${index + 1}. ${new Date(backup.timestamp).toLocaleString()} - ${backup.venueId} (${backup.reason})`);
    });

    const indexStr = await this.promptInput('Seleccione el número de configuración a restaurar (0 para cancelar): ');
    const index = parseInt(indexStr) - 1;

    if (isNaN(index) || index < 0 || index >= history.length) {
      console.log('❌ Selección inválida.\n');
      return;
    }

    const selectedBackup = history[index];
    const confirm = await this.promptInput(`¿Confirma restaurar la configuración "${selectedBackup.venueId}"? (s/N): `);
    
    if (confirm.toLowerCase() !== 's' && confirm.toLowerCase() !== 'si') {
      console.log('❌ Operación cancelada.\n');
      return;
    }

    console.log('🔄 Restaurando configuración...');
    const success = await configurationManager.rollbackToBackup(index);
    
    if (success) {
      console.log('✅ Configuración restaurada exitosamente.\n');
    } else {
      console.log('❌ Error restaurando configuración.\n');
    }
  }

  private async validateCurrentConfig(): Promise<void> {
    console.log('\n🔍 VALIDAR CONFIGURACIÓN ACTUAL');
    console.log('='.repeat(40));

    console.log('Validando configuración...');
    const validation = await configurationManager.verifyCurrentConfiguration();

    if (validation.isValid) {
      console.log('✅ Configuración válida');
    } else {
      console.log('❌ Configuración inválida:');
      validation.errors.forEach(error => console.log(`  - ${error}`));
    }

    if (validation.warnings.length > 0) {
      console.log('⚠️ Advertencias:');
      validation.warnings.forEach(warning => console.log(`  - ${warning}`));
    }

    console.log('');
  }

  private async showHelp(): Promise<void> {
    console.log('\n' + '='.repeat(60));
    console.log('📖 AYUDA - CONSOLA DE ADMINISTRACIÓN');
    console.log('='.repeat(60));

    console.log('Comandos disponibles:\n');
    this.commands.forEach(cmd => {
      console.log(`  ${cmd.command.padEnd(12)} - ${cmd.description}`);
    });

    console.log('\nEstados del servicio:');
    console.log('  ✅ RUNNING               - Funcionamiento normal');
    console.log('  🚨 CONFIGURATION_ERROR   - Error de configuración, requiere acción');
    console.log('  🔧 RECONFIGURING         - Reconfiguración en progreso');
    console.log('  ⏹️ STOPPED               - Servicio detenido');

    console.log('='.repeat(60) + '\n');
  }

  private async exit(): Promise<void> {
    console.log('\n👋 Saliendo de la consola de administración...\n');
    this.stop();
  }

  private async promptInput(question: string): Promise<string> {
    return new Promise((resolve) => {
      this.rl.question(question, (answer) => {
        resolve(answer);
      });
    });
  }

  public start(): void {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    
    console.log('\n' + '='.repeat(60));
    console.log('🎛️ CONSOLA DE ADMINISTRACIÓN - AVOQADO SYNC SERVICE');
    console.log('='.repeat(60));
    console.log('Escriba "help" para ver comandos disponibles');
    console.log('Escriba "status" para ver el estado actual');
    console.log('Escriba "exit" para salir\n');

    this.promptCommand();
  }

  private async promptCommand(): Promise<void> {
    if (!this.isRunning) return;

    const currentState = serviceStateManager.getCurrentState();
    const stateEmoji = this.getStateEmoji(currentState);
    
    this.rl.question(`${stateEmoji} [${currentState}] > `, async (input) => {
      const command = input.trim().toLowerCase();
      
      if (command) {
        const commandHandler = this.commands.find(cmd => cmd.command === command);
        
        if (commandHandler) {
          try {
            await commandHandler.handler();
          } catch (error) {
            console.log(`❌ Error ejecutando comando: ${error}\n`);
          }
        } else {
          console.log(`❌ Comando no reconocido: "${input}". Escriba "help" para ver comandos disponibles.\n`);
        }
      }

      // Continuar con el siguiente prompt
      this.promptCommand();
    });
  }

  public stop(): void {
    this.isRunning = false;
    this.rl.close();
  }
}

// Singleton instance
export const managementConsole = new ManagementConsole();
