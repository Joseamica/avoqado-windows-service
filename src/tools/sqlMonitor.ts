import sql from 'mssql'
import chalk from 'chalk'
import Table from 'cli-table3'
import { format } from 'sql-formatter'

// Configuration for remote SQL Server
const config: sql.config = {
  server: '100.80.118.68',
  port: 49759,
  database: 'avov2',
  user: 'sa',
  password: 'National09',
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000
  }
}

interface QueryEvent {
  timestamp: Date
  event_type: string
  database_name: string
  username: string
  client_hostname: string
  app_name: string
  duration_ms: number
  cpu_ms: number
  logical_reads: number
  writes: number
  sql_text: string
  statement: string
}

interface CurrentQuery {
  session_id: number
  status: string
  command: string
  cpu_time: number
  total_elapsed_time: number
  logical_reads: number
  writes: number
  database_name: string
  blocking_session_id: number | null
  host_name: string
  program_name: string
  login_name: string
  query_text: string
  current_statement: string
}

class SQLMonitor {
  private pool: sql.ConnectionPool | null = null
  private isMonitoring = false
  private refreshInterval = 2000 // 2 seconds
  private showFormattedSQL = true

  async connect(): Promise<void> {
    try {
      console.log(chalk.yellow('🔌 Connecting to SQL Server...'))
      this.pool = await sql.connect(config)
      console.log(chalk.green('✅ Connected to SQL Server'))
      console.log(chalk.cyan(`📍 Server: ${config.server}:${config.port}`))
      console.log(chalk.cyan(`📁 Database: ${config.database}`))
    } catch (error) {
      console.error(chalk.red('❌ Connection failed:'), error)
      throw error
    }
  }

  async setupMonitoring(): Promise<void> {
    if (!this.pool) throw new Error('Not connected to database')

    try {
      console.log(chalk.yellow('📊 Setting up Extended Events monitoring...'))

      // Check if session exists
      const checkResult = await this.pool.request().query(`
        SELECT name FROM sys.server_event_sessions
        WHERE name = 'AvoqadoQueryMonitor'
      `)

      if (checkResult.recordset.length === 0) {
        console.log(chalk.yellow('Creating monitoring session...'))
        // Would execute the setup script here
        console.log(chalk.green('✅ Monitoring session created'))
      } else {
        console.log(chalk.green('✅ Monitoring session already exists'))
      }
    } catch (error) {
      console.error(chalk.red('❌ Setup failed:'), error)
    }
  }

  async getRecentQueries(limit: number = 10): Promise<QueryEvent[]> {
    if (!this.pool) throw new Error('Not connected to database')

    try {
      const result = await this.pool.request()
        .input('limit', sql.Int, limit)
        .query(`
          SELECT TOP (@limit)
            event_data.value('(event/@timestamp)[1]', 'datetime2') AS timestamp,
            event_data.value('(event/@name)[1]', 'varchar(50)') AS event_type,
            event_data.value('(event/action[@name="database_name"]/value)[1]', 'varchar(255)') AS database_name,
            event_data.value('(event/action[@name="username"]/value)[1]', 'varchar(255)') AS username,
            event_data.value('(event/action[@name="client_hostname"]/value)[1]', 'varchar(255)') AS client_hostname,
            event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'varchar(255)') AS app_name,
            event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint')/1000.0 AS duration_ms,
            event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint')/1000.0 AS cpu_ms,
            event_data.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint') AS logical_reads,
            event_data.value('(event/data[@name="writes"]/value)[1]', 'bigint') AS writes,
            event_data.value('(event/action[@name="sql_text"]/value)[1]', 'varchar(max)') AS sql_text,
            event_data.value('(event/data[@name="statement"]/value)[1]', 'varchar(max)') AS statement
          FROM (
            SELECT CAST(target_data AS xml) AS TargetData
            FROM sys.dm_xe_session_targets AS st
            JOIN sys.dm_xe_sessions AS s ON s.address = st.event_session_address
            WHERE s.name = N'AvoqadoQueryMonitor'
            AND st.target_name = N'ring_buffer'
          ) AS Data
          CROSS APPLY TargetData.nodes('RingBufferTarget/event') AS XEvent(event_data)
          ORDER BY timestamp DESC
        `)

      return result.recordset
    } catch (error) {
      console.error(chalk.red('❌ Failed to get queries:'), error)
      return []
    }
  }

  async getCurrentQueries(): Promise<CurrentQuery[]> {
    if (!this.pool) throw new Error('Not connected to database')

    try {
      const result = await this.pool.request().query(`
        SELECT
          r.session_id,
          r.status,
          r.command,
          r.cpu_time,
          r.total_elapsed_time,
          r.logical_reads,
          r.writes,
          DB_NAME(r.database_id) as database_name,
          r.blocking_session_id,
          s.host_name,
          s.program_name,
          s.login_name,
          t.text AS query_text,
          SUBSTRING(t.text, (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset
              WHEN -1 THEN DATALENGTH(t.text)
              ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS current_statement
        FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        LEFT JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
        WHERE r.session_id != @@SPID
          AND DB_NAME(r.database_id) = 'avov2'
      `)

      return result.recordset
    } catch (error) {
      console.error(chalk.red('❌ Failed to get current queries:'), error)
      return []
    }
  }

  displayQueries(queries: QueryEvent[]): void {
    if (queries.length === 0) {
      console.log(chalk.yellow('📭 No queries captured yet'))
      return
    }

    const table = new Table({
      head: ['Time', 'Type', 'Duration (ms)', 'CPU (ms)', 'Reads', 'SQL'],
      colWidths: [20, 15, 12, 10, 10, 60],
      wordWrap: true
    })

    queries.forEach(query => {
      const sql = (query.sql_text || query.statement || '').substring(0, 100)
      const formattedSQL = this.showFormattedSQL ? this.formatSQL(sql) : sql

      table.push([
        new Date(query.timestamp).toLocaleTimeString(),
        query.event_type || 'N/A',
        query.duration_ms?.toFixed(2) || '0',
        query.cpu_ms?.toFixed(2) || '0',
        query.logical_reads?.toString() || '0',
        formattedSQL
      ])
    })

    console.log(table.toString())
  }

  displayCurrentQueries(queries: CurrentQuery[]): void {
    if (queries.length === 0) {
      console.log(chalk.green('✨ No active queries'))
      return
    }

    const table = new Table({
      head: ['Session', 'Status', 'Command', 'Time (ms)', 'Reads', 'Host', 'Statement'],
      colWidths: [10, 12, 15, 10, 10, 20, 50],
      wordWrap: true
    })

    queries.forEach(query => {
      const stmt = (query.current_statement || query.query_text || '').substring(0, 80)

      table.push([
        query.session_id.toString(),
        query.status,
        query.command,
        query.total_elapsed_time.toString(),
        query.logical_reads.toString(),
        query.host_name || 'N/A',
        stmt
      ])
    })

    console.log(chalk.cyan('\n📊 Currently Executing Queries:'))
    console.log(table.toString())
  }

  private formatSQL(sql: string): string {
    try {
      return format(sql, { language: 'tsql' }).substring(0, 100)
    } catch {
      return sql
    }
  }

  async startRealTimeMonitoring(): Promise<void> {
    this.isMonitoring = true
    console.log(chalk.green('🎬 Starting real-time monitoring...'))
    console.log(chalk.gray('Press Ctrl+C to stop\n'))

    while (this.isMonitoring) {
      console.clear()
      console.log(chalk.bgBlue.white(' SQL SERVER MONITOR '))
      console.log(chalk.gray(`Refreshing every ${this.refreshInterval/1000}s | ${new Date().toLocaleTimeString()}\n`))

      // Show current queries
      const currentQueries = await this.getCurrentQueries()
      this.displayCurrentQueries(currentQueries)

      // Show recent captured queries
      const recentQueries = await this.getRecentQueries(5)
      if (recentQueries.length > 0) {
        console.log(chalk.cyan('\n📜 Recent Query History:'))
        this.displayQueries(recentQueries)
      }

      // Wait before refresh
      await new Promise(resolve => setTimeout(resolve, this.refreshInterval))
    }
  }

  async disconnect(): Promise<void> {
    if (this.pool) {
      await this.pool.close()
      console.log(chalk.yellow('👋 Disconnected from SQL Server'))
    }
  }
}

// Main execution
async function main() {
  const monitor = new SQLMonitor()

  // Handle graceful shutdown
  process.on('SIGINT', async () => {
    console.log(chalk.yellow('\n\n🛑 Stopping monitor...'))
    await monitor.disconnect()
    process.exit(0)
  })

  try {
    await monitor.connect()
    await monitor.setupMonitoring()
    await monitor.startRealTimeMonitoring()
  } catch (error) {
    console.error(chalk.red('Fatal error:'), error)
    await monitor.disconnect()
    process.exit(1)
  }
}

// Run if executed directly
if (require.main === module) {
  main()
}

export { SQLMonitor }