# TgllFileSystemMonitor Component

A comprehensive Delphi visual component for monitoring file system changes, part of the GITLAKLib Component Library.

## Overview

TgllFileSystemMonitor provides real-time monitoring of files and directories with support for creation, modification, deletion, and rename events. Built as a visual component wrapper around PyScripter's FileSystemMonitor interface, it offers both simple property-based configuration and advanced collection-based monitoring.

## Features

- **Visual Component**: Drop onto forms and configure at design-time
- **Multiple Configuration Levels**: Simple properties, collections, or programmatic control
- **Built-in Deduplication**: Filters rapid-fire duplicate events automatically
- **Path Macros**: Support for application and system path variables
- **Cross-Platform Compatibility**: Windows 7+ / Server 2012 R2+, Win32/Win64
- **Thread-Safe**: Uses Windows I/O Completion Ports for efficient monitoring
- **Flexible Notification**: Configurable change types and buffer sizes

## Requirements

- **Delphi**: Version XE2+ (minimum), Version 12+ (recommended for compilation)
- **Dependencies**: 
  - FileSystemMonitor.pas (original interface implementation)
  - Windows APIs: ReadDirectoryChangesW, I/O Completion Ports
- **Operating System**: Windows 7+ / Windows Server 2012 R2+
- **Architecture**: Win32 and Win64

### Delphi Version Compatibility

**Delphi XE2+**: Full compatibility without modification
**Delphi XE**: Requires unit name changes (System.Classes → Classes, etc.)
**Delphi 2009-2010**: Requires unit name changes and TPath replacement
**Delphi 2007 and earlier**: Not supported (lacks generics and anonymous methods)

**Note**: While the component can be made compatible with Delphi XE2+, it's designed and tested for Delphi 12+ compilation to ensure optimal performance and modern language feature support.

## Installation

1. Add both `gllFileSystemMonitor.pas` and `FileSystemMonitor.pas` to your project
2. Install the component package or add to your component library
3. The component will appear in the "GITLAKLib" palette tab

## Basic Usage

### Simple File Monitoring

```pascal
// Design-time: Set properties in Object Inspector
gllFileSystemMonitor1.FilePath := 'C:\MyApp\config.ini';
gllFileSystemMonitor1.MonitorFile := True;
gllFileSystemMonitor1.Active := True;

// Runtime: Use direct methods
gllFileSystemMonitor1.AddFile('C:\MyApp\data.txt', [nfLastWrite, nfSize]);
```

### Simple Directory Monitoring

```pascal
// Monitor a directory with subdirectories
gllFileSystemMonitor1.DirectoryPath := 'C:\MyApp\Data';
gllFileSystemMonitor1.MonitorDirectory := True;
gllFileSystemMonitor1.WatchSubtree := True;
gllFileSystemMonitor1.Active := True;
```

### Using Path Macros

```pascal
// Instead of hardcoded paths, use macros
gllFileSystemMonitor1.FilePath := '{%AppPath%}\AlertMessage.txt';
gllFileSystemMonitor1.DirectoryPath := '{%Temp%}\MyApp';
```

### Event Handling

```pascal
procedure TForm1.gllFileSystemMonitor1Change(Sender: TObject; 
  const Path: string; ChangeType: TFileChangeType);
begin
  case ChangeType of
    fcAdded:    ShowMessage('File created: ' + Path);
    fcModified: ShowMessage('File modified: ' + Path);
    fcRemoved:  ShowMessage('File deleted: ' + Path);
  end;
end;
```

## Properties

### Basic Configuration
- **Active** (Boolean): Enable/disable monitoring
- **BufferSize** (Integer): Internal buffer size for events (default: 65536)

### Simple Monitoring
- **FilePath** (String): Path to single file (supports macros)
- **MonitorFile** (Boolean): Enable single file monitoring
- **DirectoryPath** (String): Path to single directory (supports macros)
- **MonitorDirectory** (Boolean): Enable single directory monitoring  
- **WatchSubtree** (Boolean): Include subdirectories in monitoring

### Advanced Configuration
- **MonitorItems** (Collection): Multiple files/directories with individual settings
- **EnableDeduplication** (Boolean): Filter duplicate events (default: True)
- **DeduplicationWindow** (Integer): Time window in milliseconds (default: 500)

### Events
- **OnChange** (TMonitorChangeHandler): Fired when file system changes occur

## Supported Macros

### Application Paths
- `{%AppPath%}`, `{%AppDir%}` - Application directory
- `{%ExePath%}`, `{%ExeDir%}` - Executable directory

### System Paths
- `{%AppData%}`, `{%UserProfile%}` - User home directory
- `{%Temp%}`, `{%TempDir%}` - Temporary files directory
- `{%Public%}` - Public documents directory
- `{%Documents%}` - User documents directory

### Environment Variables
- `{%USERPROFILE%}` - User profile path
- `{%PROGRAMDATA%}` - Program data directory
- `{%LOCALAPPDATA%}` - Local application data
- `{%APPDATA%}` - Roaming application data

## Change Types

- **fcAdded** - File/directory created
- **fcRemoved** - File/directory deleted
- **fcModified** - File/directory modified
- **fcRenamedOld** - Old name in rename operation
- **fcRenamedNew** - New name in rename operation

## Notification Flags

Control what changes trigger events:

- **nfFileName** - File name changes (creation/deletion/rename)
- **nfDirName** - Directory name changes
- **nfAttributes** - File attribute changes
- **nfSize** - File size changes
- **nfLastWrite** - Last write time changes
- **nfLastAccess** - Last access time changes
- **nfCreation** - Creation time changes
- **nfSecurity** - Security descriptor changes

## Collection-Based Monitoring

For complex scenarios, use the MonitorItems collection:

```pascal
// Add through collection editor at design-time, or programmatically:
var
  Item: TMonitorItem;
begin
  Item := gllFileSystemMonitor1.MonitorItems.Add;
  Item.Path := 'C:\Logs\app.log';
  Item.IsFile := True;
  Item.NotifyFlags := [nfSize, nfLastWrite];
  Item.Enabled := True;
end;
```

## Performance Considerations

### Minimal Impact Scenarios
- Monitoring single files or small directories
- Infrequent file changes
- Simple event processing

### Optimization Tips
- Use specific NotifyFlags rather than monitoring all changes
- Enable deduplication for high-activity directories
- Process heavy operations asynchronously in event handlers
- Avoid monitoring entire drive roots or system directories

### Database Applications
For database applications, the component adds minimal overhead when monitoring specific files like configuration or alert files. Avoid monitoring active database files or transaction logs.

## Thread Safety

The component is thread-safe with automatic marshaling to the main thread:
- File system events are detected on background threads
- OnChange events are fired on the main UI thread
- No additional synchronization required in event handlers

## Error Handling

The component handles common scenarios gracefully:
- Non-existent paths are ignored during startup
- Directory deletion stops monitoring for that path automatically
- Invalid macro expansion falls back to original path
- Component state is maintained across monitoring restart

## Example: Alert Message Monitoring

```pascal
// Monitor for alert messages with automatic cleanup
procedure TForm1.FormCreate(Sender: TObject);
begin
  gllFileSystemMonitor1.FilePath := '{%AppPath%}\AlertMessage.txt';
  gllFileSystemMonitor1.MonitorFile := True;
  gllFileSystemMonitor1.EnableDeduplication := True;
  gllFileSystemMonitor1.Active := True;
end;

procedure TForm1.gllFileSystemMonitor1Change(Sender: TObject; 
  const Path: string; ChangeType: TFileChangeType);
begin
  case ChangeType of
    fcAdded: ProcessNewAlert(Path);
    fcModified: UpdateAlert(Path);
    fcRemoved: ClearAlert;
  end;
end;
```

## License

MIT License - Same as the original FileSystemMonitor implementation by PyScripter.

## Dependencies

- **FileSystemMonitor.pas** - Original interface implementation
- **System.Classes, System.SysUtils** - Standard Delphi RTL
- **System.IOUtils** - For path macro expansion
- **Vcl.Forms** - For Application global access
- **Windows API** - ReadDirectoryChangesW, I/O Completion Ports

## Version History

- **v1.0** - Initial release with basic monitoring
- **v1.1** - Added deduplication and macro support
- **v1.2** - Enhanced collection support and path macros

---

*Part of the GITLAKLib Component Library*