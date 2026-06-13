-- =====================================================
-- SQL Server Query Monitoring Setup (Like SQL Profiler)
-- For SQL Server 2014 and later
-- =====================================================

-- Drop existing session if it exists
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'AvoqadoQueryMonitor')
    DROP EVENT SESSION [AvoqadoQueryMonitor] ON SERVER;
GO

-- Create Extended Events session for query monitoring
CREATE EVENT SESSION [AvoqadoQueryMonitor] ON SERVER
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.sql_text,
        sqlserver.tsql_stack
    )
    WHERE ([database_name] = N'avov2')
),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.sql_text,
        sqlserver.tsql_stack
    )
    WHERE ([database_name] = N'avov2')
),
ADD EVENT sqlserver.sp_statement_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.sql_text
    )
    WHERE ([database_name] = N'avov2' AND [duration] > 1000)  -- Only capture statements longer than 1ms
)
ADD TARGET package0.ring_buffer(SET max_memory=4096)
WITH (
    MAX_MEMORY=4096 KB,
    EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY=30 SECONDS,
    MAX_EVENT_SIZE=0 KB,
    MEMORY_PARTITION_MODE=NONE,
    TRACK_CAUSALITY=OFF,
    STARTUP_STATE=ON  -- Auto-start with SQL Server
);
GO

-- Start the session
ALTER EVENT SESSION [AvoqadoQueryMonitor] ON SERVER STATE = START;
GO

-- =====================================================
-- Query to VIEW captured events (run this to see queries)
-- =====================================================
SELECT
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
ORDER BY timestamp DESC;
GO

-- =====================================================
-- Alternative: Real-time monitoring view
-- =====================================================
CREATE OR ALTER VIEW vw_CurrentQueries AS
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
WHERE r.session_id != @@SPID  -- Exclude this session
    AND DB_NAME(r.database_id) = 'avov2';
GO

-- View currently executing queries
SELECT * FROM vw_CurrentQueries;
GO

-- =====================================================
-- Stop monitoring (when you want to disable it)
-- =====================================================
-- ALTER EVENT SESSION [AvoqadoQueryMonitor] ON SERVER STATE = STOP;
-- DROP EVENT SESSION [AvoqadoQueryMonitor] ON SERVER;