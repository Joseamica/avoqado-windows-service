import sql, { ConnectionPool } from 'mssql';
import { loadConfig } from '../config';
import { log } from './logger';

// Esta variable mantendrá la conexión viva
let pool: ConnectionPool | null = null;
let isConnecting = false;

const connectWithRetry = async (): Promise<void> => {
  if (pool || isConnecting) return;
  isConnecting = true;

  try {
    const { sqlConfig } = loadConfig(); // Obtenemos la config desde un solo lugar
    log.info('🔌 Conectando a SQL Server...');
    
    // Creamos un nuevo objeto de configuración para la librería mssql
    const dbConfig: sql.config = {
      user: sqlConfig.user,
      password: sqlConfig.password,
      database: sqlConfig.database,
      server: sqlConfig.server,
      pool: {
        max: 10,
        min: 0,
        idleTimeoutMillis: 30000
      },
      options: {
        instanceName: sqlConfig.instanceName,
        encrypt: false, // Para desarrollo local. En producción, debería ser true con un certificado válido.
        trustServerCertificate: true // Necesario para certificados autofirmados en desarrollo
      }
    };
    
    pool = await new ConnectionPool(dbConfig).connect();
    log.info('✅ Conexión con SQL Server establecida.');

    pool.on('error', (err) => {
      log.error('❌ Error en el pool de SQL Server:', err);
    });

  } catch (error: any) {
    log.error('🔥 Falla catastrófica al conectar con SQL Server, reintentando en 10s...', error.message);
    pool = null;
    setTimeout(connectWithRetry, 10000);
  } finally {
    isConnecting = false;
  }
};

export const connectToSql = async (): Promise<void> => {
  if (!pool) {
    await connectWithRetry();
  }
};

export const getDbPool = (): ConnectionPool => {
  if (!pool) {
    throw new Error('El pool de conexiones de SQL Server no ha sido inicializado.');
  }
  return pool;
};

// Función de ayuda para ejecutar queries de forma segura
export const executeQuery = async (query: string): Promise<any[]> => {
  const pool = getDbPool();
  const result = await pool.request().query(query);
  return result.recordset;
};

export const closeDbPool = async (): Promise<void> => {
  if (pool) {
    log.info('🚪 Cerrando pool de SQL Server...');
    await pool.close();
    pool = null;
  }
};