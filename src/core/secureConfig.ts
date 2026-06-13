import fs from 'fs'
import path from 'path'
import crypto from 'crypto'
import { log } from './logger'
import { AppConfig } from '../config'

// Encryption key for production config files (derived from machine-specific data)
const ENCRYPTION_ALGORITHM = 'aes-256-cbc'
const ENCRYPTION_KEY_LENGTH = 32
const IV_LENGTH = 16

/**
 * Production-ready configuration management with security features:
 * - Windows Authentication for SQL Server (no passwords)
 * - Encrypted configuration files
 * - Machine-specific encryption keys
 * - Configuration validation and backup
 */
export class SecureConfigManager {
  private configPath: string
  private backupPath: string
  private encryptionKey: Buffer | null = null

  constructor() {
    const programData = process.env.ProgramData || 'C:/ProgramData'
    const configDir = path.join(programData, 'AvoqadoSync')

    this.configPath = path.join(configDir, 'config.json')
    this.backupPath = path.join(configDir, 'config.backup.json')

    // Ensure config directory exists
    if (!fs.existsSync(configDir)) {
      fs.mkdirSync(configDir, { recursive: true })
    }
  }

  /**
   * Generate machine-specific encryption key using hardware identifiers
   * Uses dynamically retrieved system information for security
   */
  private generateEncryptionKey(): Buffer {
    if (this.encryptionKey) return this.encryptionKey

    try {
      // Dynamically get machine-specific data from environment
      const machineId = process.env.COMPUTERNAME || process.env.HOSTNAME || 'unknown-machine'
      const userProfile = process.env.USERPROFILE || process.env.HOME || 'unknown-user'
      const systemRoot = process.env.SystemRoot || process.env.WINDIR || 'unknown-system'
      const processor = process.env.PROCESSOR_IDENTIFIER || process.arch

      log.info(`🔐 Generating encryption key for machine: ${machineId}`)

      // Create deterministic key from machine-specific data
      const keyMaterial = `${machineId}-${userProfile}-${systemRoot}-${processor}-avoqado-sync`
      this.encryptionKey = crypto.scryptSync(keyMaterial, 'avoqado-salt-2024', ENCRYPTION_KEY_LENGTH)

      log.info('🔐 Machine-specific encryption key generated successfully')
      return this.encryptionKey
    } catch (error) {
      log.error('Failed to generate encryption key:', error)
      throw new Error('Cannot generate secure encryption key')
    }
  }

  /**
   * Encrypt configuration data using AES-256-CBC with proper IV
   */
  private encryptConfig(config: AppConfig): string {
    const key = this.generateEncryptionKey()
    const iv = crypto.randomBytes(IV_LENGTH)

    const cipher = crypto.createCipheriv(ENCRYPTION_ALGORITHM, key, iv)
    const configJson = JSON.stringify(config, null, 2)

    let encrypted = cipher.update(configJson, 'utf8', 'hex')
    encrypted += cipher.final('hex')

    // Store IV and encrypted data
    const result = {
      iv: iv.toString('hex'),
      data: encrypted,
      version: '1.0',
      algorithm: ENCRYPTION_ALGORITHM
    }

    return JSON.stringify(result)
  }

  /**
   * Decrypt configuration data using AES-256-CBC with proper IV
   */
  private decryptConfig(encryptedData: string): AppConfig {
    const key = this.generateEncryptionKey()
    const parsed = JSON.parse(encryptedData)

    const iv = Buffer.from(parsed.iv, 'hex')
    const algorithm = parsed.algorithm || ENCRYPTION_ALGORITHM

    const decipher = crypto.createDecipheriv(algorithm, key, iv)

    let decrypted = decipher.update(parsed.data, 'hex', 'utf8')
    decrypted += decipher.final('utf8')

    return JSON.parse(decrypted)
  }

  /**
   * Create production-ready configuration with Windows Authentication
   */
  createProductionConfig(baseConfig: Partial<AppConfig>): AppConfig {
    const productionConfig: AppConfig = {
      venueId: baseConfig.venueId || '',
      posType: 'softrestaurant',
      posVersion: baseConfig.posVersion || '11.0',
      rabbitMqUrl: baseConfig.rabbitMqUrl || '',
      logLevel: 'info',
      sqlConfig: {
        server: 'localhost', // Always localhost in production
        instanceName: 'NATIONALSOFT',
        database: baseConfig.sqlConfig?.database || 'softrestaurant11',
        // Production: Use Windows Authentication (no credentials)
        user: '',
        password: '',
        options: {
          instanceName: 'NATIONALSOFT',
          encrypt: true, // Always enabled in production
          trustServerCertificate: false, // Don't trust self-signed certs
        }
      }
    }

    return productionConfig
  }

  /**
   * Save configuration with encryption and backup
   */
  async saveConfig(config: AppConfig): Promise<void> {
    try {
      // Create backup of existing config
      if (fs.existsSync(this.configPath)) {
        fs.copyFileSync(this.configPath, this.backupPath)
        log.info('📋 Configuration backup created')
      }

      // Validate configuration
      this.validateConfig(config)

      // Encrypt and save
      const encryptedConfig = this.encryptConfig(config)
      fs.writeFileSync(this.configPath, encryptedConfig, { mode: 0o600 }) // Restrict file permissions

      log.info('💾 Configuration saved securely')
    } catch (error) {
      log.error('Failed to save configuration:', error)
      throw error
    }
  }

  /**
   * Load configuration with decryption
   */
  async loadConfig(): Promise<AppConfig> {
    try {
      if (!fs.existsSync(this.configPath)) {
        throw new Error(`Configuration file not found: ${this.configPath}`)
      }

      const encryptedData = fs.readFileSync(this.configPath, 'utf8')

      // Try to decrypt (new format) or parse as JSON (legacy format)
      let config: AppConfig
      try {
        config = this.decryptConfig(encryptedData)
        log.info('🔓 Configuration decrypted successfully')
      } catch (decryptError) {
        // Fallback to legacy unencrypted format
        log.warn('⚠️  Using legacy unencrypted configuration format')
        config = JSON.parse(encryptedData)
      }

      this.validateConfig(config)
      return config

    } catch (error) {
      log.error('Failed to load configuration:', error)

      // Try to restore from backup
      if (fs.existsSync(this.backupPath)) {
        log.info('🔄 Attempting to restore from backup...')
        try {
          const backupData = fs.readFileSync(this.backupPath, 'utf8')
          const backupConfig = this.decryptConfig(backupData)
          this.validateConfig(backupConfig)

          log.info('✅ Configuration restored from backup')
          return backupConfig
        } catch (backupError) {
          log.error('Backup restore failed:', backupError)
        }
      }

      throw new Error('Configuration loading failed and no valid backup available')
    }
  }

  /**
   * Validate configuration completeness and security
   */
  private validateConfig(config: AppConfig): void {
    const required = ['venueId', 'rabbitMqUrl', 'sqlConfig']

    for (const field of required) {
      if (!config[field as keyof AppConfig]) {
        throw new Error(`Missing required configuration field: ${field}`)
      }
    }

    // Production security validations
    if (process.env.NODE_ENV === 'production') {
      if (config.sqlConfig.server !== 'localhost') {
        log.warn('⚠️  Production should use localhost for SQL Server connection')
      }

      if (!config.sqlConfig.options?.encrypt) {
        throw new Error('Production configuration must enable SQL Server encryption')
      }

      if (config.sqlConfig.options?.trustServerCertificate !== false) {
        log.warn('⚠️  Production should not trust self-signed certificates')
      }

      // Check for hardcoded credentials (should be empty for Windows Auth)
      if (config.sqlConfig.user && config.sqlConfig.password) {
        log.warn('⚠️  Consider using Windows Authentication instead of SQL credentials')
      }
    }

    log.info('✅ Configuration validation passed')
  }

  /**
   * Update configuration with validation
   */
  async updateConfig(updates: Partial<AppConfig>): Promise<AppConfig> {
    const currentConfig = await this.loadConfig()
    const updatedConfig = { ...currentConfig, ...updates }

    // Deep merge sqlConfig if provided
    if (updates.sqlConfig) {
      updatedConfig.sqlConfig = {
        ...currentConfig.sqlConfig,
        ...updates.sqlConfig,
        options: {
          ...currentConfig.sqlConfig.options,
          ...updates.sqlConfig.options
        }
      }
    }

    await this.saveConfig(updatedConfig)
    return updatedConfig
  }

  /**
   * Get configuration status and recommendations
   */
  getConfigurationStatus(): {
    isSecure: boolean
    isEncrypted: boolean
    hasBackup: boolean
    recommendations: string[]
  } {
    const recommendations: string[] = []
    let isSecure = true
    let isEncrypted = false
    const hasBackup = fs.existsSync(this.backupPath)

    try {
      if (fs.existsSync(this.configPath)) {
        const configData = fs.readFileSync(this.configPath, 'utf8')

        // Check if encrypted
        try {
          JSON.parse(configData)
          const parsed = JSON.parse(configData)
          isEncrypted = !!(parsed.iv && parsed.tag && parsed.data)
        } catch {
          isEncrypted = false
        }

        if (!isEncrypted) {
          recommendations.push('Migrate to encrypted configuration format')
          isSecure = false
        }
      }

      if (!hasBackup) {
        recommendations.push('Create configuration backup')
      }

      if (process.env.NODE_ENV === 'production') {
        recommendations.push('Verify Windows Authentication is configured')
        recommendations.push('Ensure SQL Server encryption is enabled')
      }

    } catch (error) {
      log.error('Error checking configuration status:', error)
      isSecure = false
      recommendations.push('Fix configuration file issues')
    }

    return {
      isSecure,
      isEncrypted,
      hasBackup,
      recommendations
    }
  }
}

export const secureConfigManager = new SecureConfigManager()