
                                                                                                                                                                                                                                                             
CREATE TRIGGER Trg_Avoqado_Orders ON dbo.tempcheques AFTER INSERT, UPDATE, DELETE AS
                                                                                                                                                                         
BEGIN
                                                                                                                                                                                                                                                        
    SET NOCOUNT ON
                                                                                                                                                                                                                                           

                                                                                                                                                                                                                                                             
    DECLARE @changeReason VARCHAR(100)
                                                                                                                                                                                                                       
    DECLARE @entityId VARCHAR(200)
                                                                                                                                                                                                                           
    DECLARE @workspaceId UNIQUEIDENTIFIER
                                                                                                                                                                                                                    
    DECLARE @idturno BIGINT
                                                                                                                                                                                                                                  
    DECLARE @folio BIGINT
                                                                                                                                                                                                                                    

                                                                                                                                                                                                                                                             
    -- Procesar INSERT/UPDATE
                                                                                                                                                                                                                                
    IF EXISTS(SELECT 1 FROM inserted)
                                                                                                                                                                                                                        
    BEGIN
                                                                                                                                                                                                                                                    
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN 'order_updated' ELSE 'order_created' END
                                                                                                                                            

                                                                                                                                                                                                                                                             
        DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR
                                                                                                                                                                                                   
            SELECT folio, idturno,
                                                                                                                                                                                                                           
                   CASE WHEN COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                                                                                                                                                                            
                        THEN WorkspaceId
                                                                                                                                                                                                                     
                        ELSE NULL
                                                                                                                                                                                                                            
                   END as WorkspaceId
                                                                                                                                                                                                                        
            FROM inserted
                                                                                                                                                                                                                                    

                                                                                                                                                                                                                                                             
        OPEN order_cursor
                                                                                                                                                                                                                                    
        FETCH NEXT FROM order_cursor INTO @folio, @idturno, @workspaceId
                                                                                                                                                                                     

                                                                                                                                                                                                                                                             
        WHILE @@FETCH_STATUS = 0
                                                                                                                                                                                                                             
        BEGIN
                                                                                                                                                                                                                                                
            -- Generar Entity ID usando el stored procedure
                                                                                                                                                                                                  
            EXEC sp_GenerateEntityId 'order', @workspaceId, @idturno, @folio, NULL, @entityId OUTPUT
                                                                                                                                                         
            EXEC sp_TrackEntityChange 'order', @entityId, @changeReason
                                                                                                                                                                                      
            FETCH NEXT FROM order_cursor INTO @folio, @idturno, @workspaceId
                                                                                                                                                                                 
        END
                                                                                                                                                                                                                                                  

                                                                                                                                                                                                                                                             
        CLOSE order_cursor
                                                                                                                                                                                                                                   
        DEALLOCATE order_cursor
                                                                                                                                                                                                                              
    END
                                                                                                                                                                                                                                                      

                                                                                                                                                                                                                                                             
    -- Procesar DELETE
                                                                                                                                                                                                                                       
    ELSE IF EXISTS(SELECT 1 FROM deleted)
                                                                                                                                                                                                                    
    BEGIN
                                                                                                                                                                                                                                                    
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
                                                                                                                                                                                                  
            SELECT folio, idturno,
                                                                                                                                                                                                                           
                   CASE WHEN COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                                                                                                                                                                            
                        THEN WorkspaceId
                                                                                                                                                                                                                     
                        ELSE NULL
                                                                                                                                                                                                                            
                   END as WorkspaceId
                                                                                                                                                                                                                        
            FROM deleted
                                                                                                                                                                                                                                     

                                                                                                                                                                                                                                                             
        OPEN delete_cursor
                                                                                                                                                                                                                                   
        FETCH NEXT FROM delete_cursor INTO @folio, @idturno, @workspaceId
                                                                                                                                                                                    

                                                                                                                                                                                                                                                             
        WHILE @@FETCH_STATUS = 0
                                                                                                                                                                                                                             
        BEGIN
                                                                                                                                                                                                                                                
            EXEC sp_GenerateEntityId 'order', @workspaceId, @idturno, @folio, NULL, @entityId OUTPUT
                                                                                                                                                         
            EXEC sp_TrackEntityChange 'order', @entityId, 'order_deleted'
                                                                                                                                                                                    
            FETCH NEXT FROM delete_cursor INTO @folio, @idturno, @workspaceId
                                                                                                                                                                                
        END
                                                                                                                                                                                                                                                  

                                                                                                                                                                                                                                                             
        CLOSE delete_cursor
                                                                                                                                                                                                                                  
        DEALLOCATE delete_cursor
                                                                                                                                                                                                                             
    END
                                                                                                                                                                                                                                                      
END                                                                                                                                                                                                                                                            
