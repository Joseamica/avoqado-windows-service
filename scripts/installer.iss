[Setup]
AppName=Avoqado POS Sync Service
AppVersion=1.0.0
DefaultDirName={pf}\AvoqadoSync
DefaultGroupName=Avoqado Sync Service
OutputBaseFilename=AvoqadoSyncService_Installer
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
; El ejecutable que empaquetamos con pkg
Source: "..\AvoqadoSyncService.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Avoqado Sync Service Config"; Filename: "notepad.exe"; Parameters: """{commonappdata}\AvoqadoSync\config.json"""

[Run]
; Instala el servicio después de copiar los archivos
Filename: "{app}\AvoqadoSyncService.exe"; Parameters: "install"; Flags: runhidden

[Code]
// Procedimiento para crear el archivo de configuración al instalar
procedure CurStepChanged(CurStep: TSetupStep);
var
  ConfigPath: String;
  VenueID, RabbitURL, SqlConnStr: String;
  ConfigJson: TStringList;
begin
  if CurStep = ssPostInstall then
  begin
    // Crear el directorio de configuración en una ruta común
    ConfigPath := ExpandConstant('{commonappdata}\AvoqadoSync');
    if not DirExists(ConfigPath) then
      CreateDir(ConfigPath);
      
    // Preguntar al usuario por los datos de configuración
    VenueID := InputQuery('Configuración de Avoqado', 'Por favor, ingrese el ID del Venue:', False);
    RabbitURL := InputQuery('Configuración de RabbitMQ', 'Ingrese la URL de conexión de RabbitMQ:', False);
    SqlConnStr := InputQuery('Configuración de Base de Datos', 'Ingrese la cadena de conexión de SQL Server:', True);

    // Crear el objeto JSON
    ConfigJson := TStringList.Create;
    ConfigJson.Add('{');
    ConfigJson.Add('  "venueId": "' + VenueID + '",');
    ConfigJson.Add('  "rabbitMqUrl": "' + RabbitURL + '",');
    ConfigJson.Add('  "sqlConnectionString": "' + SqlConnStr + '",');
    ConfigJson.Add('  "logLevel": "info"');
    ConfigJson.Add('}');
    
    // Guardar el archivo de configuración
    ConfigJson.SaveToFile(ConfigPath + '\config.json');
    FreeAndNil(ConfigJson);
  end;
end;

// Procedimiento para desinstalar el servicio
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec(ExpandConstant('{app}\AvoqadoSyncService.exe'), 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, FAILED);
  end;
end;