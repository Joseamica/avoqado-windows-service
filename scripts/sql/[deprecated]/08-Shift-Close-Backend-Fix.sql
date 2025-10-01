-- =============================================
-- Shift Close Backend Fix Documentation
-- Date: 2025-09-23
-- Author: Claude
-- =============================================

/*
PROBLEM DESCRIPTION:
--------------------
When closing a shift from the POS, the backend was receiving shift.closed events
but failing to process them with error: "Argument `externalId` is missing"

The payload contained the correct data but the backend couldn't extract it properly.

ROOT CAUSE:
-----------
In avoqado-server/src/services/pos-sync/posSyncShift.service.ts:
- Variable scoping issue: shiftExternalId was declared inside if (event === 'closed') block
- But was being referenced outside the block for the externalId variable
- This caused undefined values when processing shift.closed events

SOLUTION:
---------
1. Moved shiftExternalId declaration outside the if block:
   const shiftExternalId = shiftData.externalId || shiftData.WorkspaceId || shiftData.EntityId

2. This ensures the variable is accessible throughout the function scope

3. The extraction logic handles both v10 and v11 Entity ID formats:
   - v10: Uses numeric idturno
   - v11: Uses GUID WorkspaceId

FILES MODIFIED:
---------------
- avoqado-server/src/services/pos-sync/posSyncShift.service.ts (lines 75-107)

TESTING:
--------
1. Created test shift in external database (100.80.118.68,49759)
2. Closed shift using: UPDATE turnos SET cierre = GETDATE()
3. Verified Windows service detected and published shift.closed event
4. Confirmed backend received and processed event with correct externalId
5. Shift status successfully updated to CLOSED in backend database

COMPATIBILITY:
--------------
✅ Works with SoftRestaurant v10 (numeric idturno)
✅ Works with SoftRestaurant v11 (GUID WorkspaceId)

VERIFICATION QUERIES:
--------------------*/

-- Check shift tracking in v11 database
SELECT TOP 10
    EntityId,
    Operation,
    Timestamp,
    ProcessedAt
FROM AvoqadoTracking
WHERE EntityType = 'shift'
ORDER BY Timestamp DESC;

-- Verify shift status in backend
-- Run in PostgreSQL:
-- SELECT
--     id,
--     "externalId",
--     status,
--     "endTime",
--     "totalSales",
--     "totalOrders"
-- FROM shifts
-- WHERE "externalId" = '5DBFDBAE-E81B-4A4C-9954-A4A0EDD35707';

/*
NOTES:
------
- The external test database uses AvoqadoTracking table (older version)
- Local database would use AvoqadoEntityTracking table (newer version)
- Both are supported by the Windows service producer
- Backend now correctly handles both v10 and v11 Entity ID formats
*/