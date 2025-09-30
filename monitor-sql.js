const sql = require('mssql')

// Configuration - matches your .env settings
const config = {
  server: '100.80.118.68',
  port: 49759,
  database: 'avov2',
  user: 'sa',
  password: 'National09',
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true
  }
}

let pool = null

async function connectDB() {
  try {
    pool = await sql.connect(config)
    console.log('✅ Connected to SQL Server')
    console.log(`📍 Server: ${config.server}:${config.port}`)
    console.log(`📁 Database: ${config.database}`)
    console.log('-----------------------------------\n')
  } catch (error) {
    console.error('❌ Connection failed:', error.message)
    process.exit(1)
  }
}

async function monitorQueries() {
  if (!pool) return

  try {
    // Get currently executing queries
    const result = await pool.request().query(`
      SELECT
        r.session_id as [Session],
        r.status as [Status],
        r.command as [Command],
        r.total_elapsed_time as [Time_ms],
        r.logical_reads as [Reads],
        r.writes as [Writes],
        DB_NAME(r.database_id) as [Database],
        s.host_name as [Host],
        s.program_name as [Program],
        SUBSTRING(t.text, (r.statement_start_offset/2)+1,
          ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset)/2) + 1) AS [Current_SQL]
      FROM sys.dm_exec_requests r
      CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
      LEFT JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
      WHERE r.session_id != @@SPID
        AND DB_NAME(r.database_id) = 'avov2'
      ORDER BY r.total_elapsed_time DESC
    `)

    // Clear console for clean display
    console.clear()
    console.log('🔍 SQL SERVER QUERY MONITOR')
    console.log(`⏰ ${new Date().toLocaleTimeString()}`)
    console.log('Press Ctrl+C to stop')
    console.log('=====================================\n')

    if (result.recordset.length === 0) {
      console.log('✨ No active queries on avov2 database')
    } else {
      console.log(`📊 Found ${result.recordset.length} active queries:\n`)

      result.recordset.forEach((row, index) => {
        console.log(`Query #${index + 1}:`)
        console.log(`  Session:  ${row.Session}`)
        console.log(`  Status:   ${row.Status}`)
        console.log(`  Command:  ${row.Command}`)
        console.log(`  Duration: ${row.Time_ms}ms`)
        console.log(`  Reads:    ${row.Reads}`)
        console.log(`  Host:     ${row.Host || 'N/A'}`)
        console.log(`  Program:  ${row.Program || 'N/A'}`)
        console.log(`  SQL:      ${(row.Current_SQL || '').substring(0, 200)}`)
        console.log('-------------------------------------')
      })
    }

    // Also show recent query statistics
    const statsResult = await pool.request().query(`
      SELECT TOP 10
        DB_NAME(st.dbid) as [Database],
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
          ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2) + 1) AS [Query],
        qs.execution_count as [Executions],
        qs.total_worker_time/1000 as [Total_CPU_ms],
        qs.total_logical_reads as [Total_Reads],
        qs.last_execution_time as [Last_Executed]
      FROM sys.dm_exec_query_stats qs
      CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
      WHERE DB_NAME(st.dbid) = 'avov2'
      ORDER BY qs.last_execution_time DESC
    `)

    if (statsResult.recordset.length > 0) {
      console.log('\n📈 Recent Query Statistics:')
      console.log('=====================================')
      statsResult.recordset.forEach((row, index) => {
        const query = (row.Query || '').replace(/\s+/g, ' ').substring(0, 60)
        const lastExec = new Date(row.Last_Executed).toLocaleTimeString()
        console.log(`${index + 1}. [${lastExec}] Exec:${row.Executions} CPU:${row.Total_CPU_ms}ms`)
        console.log(`   ${query}...`)
      })
    }

  } catch (error) {
    console.error('❌ Monitor error:', error.message)
  }
}

async function startMonitoring() {
  await connectDB()

  // Update every 2 seconds
  setInterval(monitorQueries, 2000)

  // Run immediately
  await monitorQueries()
}

// Handle Ctrl+C gracefully
process.on('SIGINT', async () => {
  console.log('\n\n🛑 Stopping monitor...')
  if (pool) {
    await pool.close()
    console.log('👋 Disconnected from SQL Server')
  }
  process.exit(0)
})

// Start the monitor
console.log('🚀 Starting SQL Query Monitor...')
console.log('This will show all queries running on avov2 database')
console.log('-----------------------------------\n')
startMonitoring()