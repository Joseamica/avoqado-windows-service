import winston from 'winston';
import 'winston-daily-rotate-file';
import path from 'path';

// const logDir = path.join(process.env.ProgramData || 'C:/ProgramData', 'AvoqadoSync', 'logs');
const logDir = path.join(__dirname, '../../logs');

export const initializeLogger = () => {
  winston.configure({
    transports: [
      new winston.transports.Console({
        format: winston.format.combine(
          winston.format.colorize(),
          winston.format.simple()
        ),
        level: 'info',
      }),
      new winston.transports.DailyRotateFile({
        filename: path.join(logDir, 'info-%DATE%.log'),
        datePattern: 'YYYY-MM-DD',
        zippedArchive: true,
        maxSize: '20m',
        maxFiles: '14d',
        level: 'info',
        format: winston.format.combine(
          winston.format.timestamp(),
          winston.format.json()
        ),
      }),
      new winston.transports.DailyRotateFile({
        filename: path.join(logDir, 'error-%DATE%.log'),
        datePattern: 'YYYY-MM-DD',
        zippedArchive: true,
        maxSize: '20m',
        maxFiles: '14d',
        level: 'error',
        format: winston.format.combine(
          winston.format.timestamp(),
          winston.format.json()
        ),
      }),
    ]
  });
};

export const log = winston;