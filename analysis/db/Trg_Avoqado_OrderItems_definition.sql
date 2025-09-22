
CREATE TRIGGER Trg_Avoqado_OrderItems ON dbo.tempcheqdet AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    DECLARE @itemEntityId VARCHAR(200)
    DECLARE @changeReason VARCHAR(100)
    DECLARE @workspaceId UNIQUEIDENTIFIER
    DECLARE @movimiento NUMERIC(3,0)
    DECLARE @folio BIGINT
    DECLARE @idturno BIGINT

    -- Tabla temporal para cambios
    DECLARE @changes TABLE (
        folio BIGINT,
        WorkspaceId UNIQUEIDENTIFIER,
        movimiento NUMERIC(3,0),
        ChangeType VARCHAR(20)
    )

    -- Detectar todos los cambios
    ;WITH AllChanges AS (
        SELECT
            COALESCE(i.foliodet, d.foliodet) as folio,
            CASE WHEN COL_LENGTH('tempcheqdet', 'WorkspaceId') IS NOT NULL
                 THEN COALESCE(i.WorkspaceId, d.WorkspaceId)
                 ELSE NULL
            END as WorkspaceId,
            COALESCE(i.movimiento, d.movimiento) as movimiento,
            CASE
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN 'item_updated'
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NULL THEN 'item_created'
                WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL THEN 'item_deleted'
            END as ChangeType
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    )
    INSERT INTO @changes (folio, WorkspaceId, movimiento, ChangeType)
    SELECT folio, WorkspaceId, movimiento, ChangeType FROM AllChanges WHERE ChangeType IS NOT NULL

    -- Procesar cada cambio
    DECLARE item_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT folio, WorkspaceId, movimiento, ChangeType FROM @changes

    OPEN item_cursor
    FETCH NEXT FROM item_cursor INTO @folio, @workspaceId, @movimiento, @changeReason

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Obtener idturno de la orden padre
        SELECT @idturno = idturno FROM tempcheques WHERE folio = @folio

        -- Generar Entity ID usando el stored procedure
        EXEC sp_GenerateEntityId 'orderitem', @workspaceId, @idturno, @folio, @movimiento, @itemEntityId OUTPUT
        EXEC sp_TrackEntityChange 'orderitem', @itemEntityId, @changeReason
        FETCH NEXT FROM item_cursor INTO @folio, @workspaceId, @movimiento, @changeReason
    END

    CLOSE item_cursor
    DEALLOCATE item_cursor
END                                                                                                                                                                                                                                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                                                                                                                                                
                                                                                                                                                                                                                                                                                                                                                                                                                
                                                                                                                                                                                                                                                                                                                                                                                                                
                                                                                               

(1 rows affected)
