import { exec } from 'child_process';
import { promisify } from 'util';
import { log } from './logger';
import { ConfigurationError } from './serviceState';

const execAsync = promisify(exec);

export interface NotificationOptions {
  title: string;
  message: string;
  type: 'info' | 'warning' | 'error';
  timeout?: number; // in seconds
}

/**
 * Muestra una notificación de Windows usando PowerShell
 */
export const showWindowsNotification = async (options: NotificationOptions): Promise<void> => {
  try {
    const { title, message, type, timeout = 10 } = options;
    
    // Escapar comillas en el mensaje
    const escapedTitle = title.replace(/"/g, '""');
    const escapedMessage = message.replace(/"/g, '""');
    
    // Determinar el icono basado en el tipo
    let iconType = 'Info';
    switch (type) {
      case 'warning':
        iconType = 'Warning';
        break;
      case 'error':
        iconType = 'Error';
        break;
      default:
        iconType = 'Info';
    }

    // Comando PowerShell para mostrar notificación
    const powershellCommand = `
      Add-Type -AssemblyName System.Windows.Forms;
      $notify = New-Object System.Windows.Forms.NotifyIcon;
      $notify.Icon = [System.Drawing.SystemIcons]::${iconType};
      $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::${iconType};
      $notify.BalloonTipText = "${escapedMessage}";
      $notify.BalloonTipTitle = "${escapedTitle}";
      $notify.Visible = $true;
      $notify.ShowBalloonTip(${timeout * 1000});
      Start-Sleep -Seconds ${timeout + 1};
      $notify.Dispose();
    `;

    await execAsync(`powershell -Command "${powershellCommand.replace(/\n/g, ' ')}"`);
    
    log.info(`[Windows Notification] Notificación mostrada: ${title}`);
    
  } catch (error) {
    log.error('[Windows Notification] Error mostrando notificación:', error);
    
    // Fallback: mostrar en consola si falla la notificación
    console.log(`\n${'='.repeat(60)}`);
    console.log(`🔔 NOTIFICACIÓN: ${options.title}`);
    console.log(`${options.message}`);
    console.log(`${'='.repeat(60)}\n`);
  }
};

/**
 * Muestra una notificación específica para errores de configuración
 */
export const notifyConfigurationError = async (error: ConfigurationError): Promise<void> => {
  const title = 'Avoqado Sync Service - Error de Configuración';
  
  const message = `Error: ${error.errorType}

Venue ID inválido: ${error.invalidVenueId}

${error.message}

El servicio ha detenido los heartbeats. Se requiere reconfiguración manual.

Timestamp: ${new Date(error.timestamp).toLocaleString()}`;

  await showWindowsNotification({
    title,
    message,
    type: 'error',
    timeout: 30 // 30 segundos para errores críticos
  });

  // También mostrar mensaje en consola para mayor visibilidad
  console.log('\n' + '🚨'.repeat(20));
  console.log('🚨 ERROR DE CONFIGURACIÓN CRÍTICO 🚨');
  console.log('🚨'.repeat(20));
  console.log(`\nVenue ID inválido: ${error.invalidVenueId}`);
  console.log(`Mensaje: ${error.message}`);
  console.log(`\nEl servicio ha sido detenido y requiere reconfiguración manual.`);
  console.log(`Timestamp: ${new Date(error.timestamp).toLocaleString()}`);
  console.log('\n' + '🚨'.repeat(20) + '\n');
};

/**
 * Muestra una notificación de éxito después de reconfiguración
 */
export const notifyReconfigurationSuccess = async (newVenueId: string): Promise<void> => {
  const title = 'Avoqado Sync Service - Reconfiguración Exitosa';
  const message = `El servicio ha sido reconfigurado exitosamente.

Nuevo Venue ID: ${newVenueId}

Los heartbeats se han reanudado y el servicio está operativo.

Timestamp: ${new Date().toLocaleString()}`;

  await showWindowsNotification({
    title,
    message,
    type: 'info',
    timeout: 15
  });
};

/**
 * Muestra una notificación de fallo en reconfiguración
 */
export const notifyReconfigurationFailure = async (reason: string): Promise<void> => {
  const title = 'Avoqado Sync Service - Fallo en Reconfiguración';
  const message = `La reconfiguración del servicio ha fallado.

Razón: ${reason}

Por favor, verifique la configuración e intente nuevamente.

Timestamp: ${new Date().toLocaleString()}`;

  await showWindowsNotification({
    title,
    message,
    type: 'error',
    timeout: 20
  });
};

/**
 * Muestra diálogo de confirmación usando PowerShell
 */
export const showConfirmationDialog = async (
  title: string, 
  message: string, 
  buttons: string[] = ['Sí', 'No']
): Promise<number> => {
  try {
    const escapedTitle = title.replace(/"/g, '""');
    const escapedMessage = message.replace(/"/g, '""');
    const buttonsList = buttons.map(b => `"${b.replace(/"/g, '""')}"`).join(',');

    const powershellCommand = `
      Add-Type -AssemblyName System.Windows.Forms;
      $result = [System.Windows.Forms.MessageBox]::Show(
        "${escapedMessage}",
        "${escapedTitle}",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
      );
      if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { 
        Write-Output "0" 
      } else { 
        Write-Output "1" 
      }
    `;

    const { stdout } = await execAsync(`powershell -Command "${powershellCommand.replace(/\n/g, ' ')}"`);
    const result = parseInt(stdout.trim());
    
    log.info(`[Windows Dialog] Respuesta del usuario: ${buttons[result] || 'Unknown'} (${result})`);
    return result;
    
  } catch (error) {
    log.error('[Windows Dialog] Error mostrando diálogo:', error);
    
    // Fallback: usar readline en consola
    console.log(`\n📋 ${title}`);
    console.log(`${message}\n`);
    
    return 1; // Default to "No" en caso de error
  }
};
