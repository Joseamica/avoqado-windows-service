import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { log } from './core/logger';

// Cargar variables de entorno desde .env en la raíz del proyecto
dotenv.config({ path: path.resolve(__dirname, '../.env') });

export interface AppConfig {
    venueId: string;
    posType: 'softrestaurant';
    posVersion: string;
    rabbitMqUrl: string;
    logLevel: 'info' | 'warn' | 'error';
    sqlConfig: { // ✅ Agrupamos la configuración de SQL
      server: string;
      instanceName: string;
      database: string;
      user: string;
      password: string;
      options: {
        instanceName: string;
        encrypt: boolean;
        trustServerCertificate: boolean;
      };
    };
  }

let config: AppConfig;

const loadConfigFromEnv = (): AppConfig => {
  log.info(' Modo Desarrollo: Cargando configuración desde el archivo .env');
  const requiredVars = ['VENUE_ID', 'RABBITMQ_URL', 'DB_SERVER', 'DB_DATABASE', 'DB_USER', 'DB_PASSWORD'];
  
  for (const varName of requiredVars) {
    if (!process.env[varName]) {
      throw new Error(`Variable de entorno requerida no encontrada en .env: ${varName}`);
    }
  }

  return {
    venueId: process.env.VENUE_ID!,
    posType: process.env.POS_TYPE as 'softrestaurant',
    posVersion: process.env.POS_VERSION!,
    rabbitMqUrl: process.env.RABBITMQ_URL!,
    sqlConfig: {
      server: process.env.DB_SERVER!,
      instanceName: process.env.DB_INSTANCE!,
      database: process.env.DB_DATABASE!,
      user: process.env.DB_USER!,
      password: process.env.DB_PASSWORD!,
      options: {
        instanceName: process.env.DB_INSTANCE!,
        encrypt: false,
        trustServerCertificate: true
      }
    },
    logLevel: (process.env.LOG_LEVEL as any) || 'info',
  };
};

const loadConfigFromFile = (): AppConfig => {
  const configPath = path.join(process.env.ProgramData || 'C:/ProgramData', 'AvoqadoSync', 'config.json');
  log.info(` Modo Producción: Cargando configuración desde: ${configPath}`);

  if (!fs.existsSync(configPath)) {
    throw new Error(`Archivo de configuración no encontrado en ${configPath}`);
  }
  
  const rawConfig = fs.readFileSync(configPath, 'utf-8');
  const fileConfig = JSON.parse(rawConfig) as AppConfig;

  if (!fileConfig.venueId || !fileConfig.rabbitMqUrl || !fileConfig.sqlConfig) {
    throw new Error("Faltan campos requeridos en config.json (venueId, rabbitMqUrl, sqlConfig)");
  }
  
  return fileConfig;
};


export const loadConfig = (): AppConfig => {
  if (config) return config;

  try {
    // La variable NODE_ENV la definiremos en los scripts de package.json
    if (process.env.NODE_ENV === 'development') {
      config = loadConfigFromEnv();
    } else {
      config = loadConfigFromFile();
    }
    
    log.info(`Configuración cargada exitosamente para el Venue ID: ${config.venueId} (Versión POS: ${config.posVersion})`);
    return config;

  } catch (error: any) {
    log.error(`FATAL: Error al cargar la configuración: ${error.message}`);
    process.exit(1);
  }
};