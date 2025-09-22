
                                                                                                                                                                                                                                                             
CREATE TRIGGER Trg_Avoqado_Shifts ON dbo.turnos AFTER INSERT, UPDATE, DELETE AS
                                                                                                                                                                              
BEGIN
                                                                                                                                                                                                                                                        
    SET NOCOUNT ON
                                                                                                                                                                                                                                           

                                                                                                                                                                                                                                                             
    DECLARE @changeReason VARCHAR(100)
                                                                                                                                                                                                                       
    DECLARE @entityId VARCHAR(200)
                                                                                                                                                                                                                           
    DECLARE @workspaceId UNIQUEIDENTIFIER
                                                                                                                                                                                                                    
    DECLARE @idturno BIGINT
                                                                                                                                                                                                                                  

                                                                                                                                                                                                                                                             
    -- Procesar INSERT/UPDATE
                                                                                                                                                                                                                                
    IF EXISTS(SELECT 1 FROM inserted)
                                                                                                                                                                                                                        
    BEGIN
                                                                                                                                                                                                                                                    
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN 'shift_updated' ELSE 'shift_created' END
                                                                                                                                            

                                                                                                                                                                                                                                                             
        DECLARE shift_cursor CURSOR LOCAL FAST_FORWARD FOR
                                                                                                                                                                                                   
            SELECT idturno,
                                                                                                                                                                                                                                  
                   CASE WHEN COL_LENGTH('turnos', 'WorkspaceId') IS NOT NULL
                                                                                                                                                                                 
                        THEN WorkspaceId
                                                                                                                                                                                                                     
                        ELSE NULL
                                                                                                                                                                                                                            
                   END as WorkspaceId
                                                                                                                                                                                                                        
            FROM inserted
                                                                                                                                                                                                                                    

                                                                                                                                                                                                                                                             
        OPEN shift_cursor
                                                                                                                                                                                                                                    
        FETCH NEXT FROM shift_cursor INTO @idturno, @workspaceId
                                                                                                                                                                                             

                                                                                                                                                                                                                                                             
        WHILE @@FETCH_STATUS = 0
                                                                                                                                                                                                                             
        BEGIN
                                                                                                                                                                                                                                                
            EXEC sp_GenerateEntityId 'shift', @workspaceId, @idturno, NULL, NULL, @entityId OUTPUT
                                                                                                                                                           
            EXEC sp_TrackEntityChange 'shift', @entityId, @changeReason
                                                                                                                                                                                      
            FETCH NEXT FROM shift_cursor INTO @idturno, @workspaceId
                                                                                                                                                                                         
        END
                                                                                                                                                                                                                                                  

                                                                                                                                                                                                                                                             
        CLOSE shift_cursor
                                                                                                                                                                                                                                   
        DEALLOCATE shift_cursor
                                                                                                                                                                                                                              
    END
                                                                                                                                                                                                                                                      

                                                                                                                                                                                                                                                             
    -- Procesar DELETE
                                                                                                                                                                                                                                       
    ELSE IF EXISTS(SELECT 1 FROM deleted)
                                                                                                                                                                                                                    
    BEGIN
                                                                                                                                                                                                                                                    
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
                                                                                                                                                                                                  
            SELECT idturno,
                                                                                                                                                                                                                                  
                   CASE WHEN COL_LENGTH('turnos', 'WorkspaceId') IS NOT NULL
                                                                                                                                                                                 
                        THEN WorkspaceId
                                                                                                                                                                                                                     
                        ELSE NULL
                                                                                                                                                                                                                            
                   END as WorkspaceId
                                                                                                                                                                                                                        
            FROM deleted
                                                                                                                                                                                                                                     

                                                                                                                                                                                                                                                             
        OPEN delete_cursor
                                                                                                                                                                                                                                   
        FETCH NEXT FROM delete_cursor INTO @idturno, @workspaceId
                                                                                                                                                                                            

                                                                                                                                                                                                                                                             
        WHILE @@FETCH_STATUS = 0
                                                                                                                                                                                                                             
        BEGIN
                                                                                                                                                                                                                                                
            EXEC sp_GenerateEntityId 'shift', @workspaceId, @idturno, NULL, NULL, @entityId OUTPUT
                                                                                                                                                           
            EXEC sp_TrackEntityChange 'shift', @entityId, 'shift_deleted'
                                                                                                                                                                                    
            FETCH NEXT FROM delete_cursor INTO @idturno, @workspaceId
                                                                                                                                                                                        
        END
                                                                                                                                                                                                                                                  

                                                                                                                                                                                                                                                             
        CLOSE delete_cursor
                                                                                                                                                                                                                                  
        DEALLOCATE delete_cursor
                                                                                                                                                                                                                             
    END
                                                                                                                                                                                                                                                      
END                                                                                                                                                                                                                                                            
