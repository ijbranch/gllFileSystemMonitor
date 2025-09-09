unit gllFileSystemMonitor;

{
  =============================================================================
  gllFileSystemMonitor
  -----------------------------------------------------------------------------
 Unit Name: gllFileSystemMonitor
 Author:    Based on PyScripter's FileSystemMonitor
 License;  MIT per PyScripter's FileSystemMonitor
 Purpose:   Visual Component for monitoring changes in files and/or directories
 Library:   Private GITLAKLib Component Library
 Compatibility:
 - Delphi Version XE2+ (minimum), Version 12+ (recommended for compilation)
 - Windows 7+ / Windows Server 2012 R2+
 - Win32 & Win64
  Visual component for monitoring changes in files and/or directories, with
  debounced aggregation to avoid duplicate notifications during bursty I/O.
  Key features
  • Monitor a file, a directory (optionally recursive), or multiple items
  • Debounce events per path within a quiet window (milliseconds)
  • Macro expansion for common folders
  • Win32 & Win64; Windows 7 SP1 / Windows Server 2012 R2+
  Notes
  • British spelling throughout
  • Define USE_RAPID_GENERICS to use TRapidDictionary; otherwise uses TDictionary
  =============================================================================
}

interface

{$DEFINE USE_RAPID_GENERICS}

{$IFDEF WIN32}
{$DEFINE WINDOWS_COMPATIBLE}
{$ENDIF}
{$IFDEF WIN64}
{$DEFINE WINDOWS_COMPATIBLE}
{$ENDIF}

{$IFNDEF WINDOWS_COMPATIBLE}
{$MESSAGE ERROR 'This component is only compatible with Windows platforms'}
{$ENDIF}

uses
  Winapi.Windows,
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs, // for System.TMonitor
  Vcl.Forms,
  Vcl.ExtCtrls,
{$IFDEF USE_RAPID_GENERICS}
  Rapid.Generics,
{$ELSE}
  System.Generics.Collections,
{$ENDIF}
  FileSystemMonitor;

type
  // Re-export types for component users
  TFileChangeType = FileSystemMonitor.TFileChangeType;
  TNotifyFlag = FileSystemMonitor.TNotifyFlag;
  TNotifyFlags = FileSystemMonitor.TNotifyFlags;

  // Collection item describing what to watch
  TMonitorItem = class(TCollectionItem)
  private
    FPath: string;
    FWatchSubtree: Boolean;
    FIsFile: Boolean;
    FNotifyFlags: TNotifyFlags;
    FEnabled: Boolean;
  public
    constructor Create(Collection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    property Path: string read FPath write FPath;
    property WatchSubtree: Boolean read FWatchSubtree write FWatchSubtree default False;
    property IsFile: Boolean read FIsFile write FIsFile default False;
    property NotifyFlags: TNotifyFlags read FNotifyFlags write FNotifyFlags default DefaultNotifyFlags;
    property Enabled: Boolean read FEnabled write FEnabled default True;
  end;

  TMonitorItems = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TMonitorItem;
    procedure SetItem(Index: Integer; const Value: TMonitorItem);
  public
    constructor Create(AOwner: TPersistent);
    function Add: TMonitorItem;
    property Items[Index: Integer]: TMonitorItem read GetItem write SetItem; default;
  end;

  TgllFileSystemMonitor = class(TComponent)
  private
    // Underlying monitor
    FMonitor: IFileSystemMonitor;

    // Design-time collection
    FMonitorItems: TMonitorItems;

    // Simple properties
    FActive: Boolean;
    FBufferSize: Integer;
    FOnChange: TMonitorChangeHandler;

    FFilePath: string;
    FMonitorFile: Boolean;

    FDirectoryPath: string;
    FMonitorDirectory: Boolean;

    FWatchSubtree: Boolean;

    // Debounce configuration
    FEnableDeduplication: Boolean;
    FDeduplicationWindow: Integer; // milliseconds

    // Optional legacy, kept for completeness (not used directly now)
    FLastChangeTime: TDateTime;
    FLastChangePath: string;
    FLastChangeType: TFileChangeType;

    // New: preference for Added vs Modified within the window
    FPreferAddedOnCreate: Boolean;

    // Debouncing aggregator
    FAggregateTimer: TTimer;
{$IFDEF USE_RAPID_GENERICS}
    FPending: TRapidDictionary<string, TFileChangeType>;
{$ELSE}
    FPending: TDictionary<string, TFileChangeType>;
{$ENDIF}
    FPendingLock: TObject; // used with System.TMonitor.Enter/Exit

    procedure SetActive(const Value: Boolean);
    procedure SetBufferSize(const Value: Integer);
    procedure SetMonitorItems(const Value: TMonitorItems);
    procedure SetFilePath(const Value: string);
    procedure SetMonitorFile(const Value: Boolean);
    procedure SetDirectoryPath(const Value: string);
    procedure SetMonitorDirectory(const Value: Boolean);
    procedure SetWatchSubtree(const Value: Boolean);
    procedure SetEnableDeduplication(const Value: Boolean);
    procedure SetDeduplicationWindow(const Value: Integer);

    procedure InternalOnChange(Sender: TObject; const Path: string; ChangeType: TFileChangeType);

    // Aggregation helpers
    procedure EnqueueChange(const Path: string; ChangeType: TFileChangeType);
    procedure FlushPending(Sender: TObject);
    function MergeChange(const OldT, NewT: TFileChangeType): TFileChangeType; // instance-level (uses preference)

    // Utility
    function ExpandMacros(const Path: string): string;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Manual control methods
    function AddDirectory(const Directory: string; WatchSubtree: Boolean = False;
      NotifyFlags: TNotifyFlags = DefaultNotifyFlags): Boolean;
    function AddFile(const FilePath: string;
      NotifyFlags: TNotifyFlags = DefaultNotifyFlags): Boolean;
    function RemoveDirectory(const Directory: string): Boolean;
    function RemoveFile(const FilePath: string): Boolean;

    // Helper methods
    procedure StartMonitoring;
    procedure StopMonitoring;
    function IsMonitoring: Boolean;

  published
    property Active: Boolean read FActive write SetActive default False;
    property BufferSize: Integer read FBufferSize write SetBufferSize default 65536;

    property MonitorItems: TMonitorItems read FMonitorItems write SetMonitorItems;

    property FilePath: string read FFilePath write SetFilePath;
    property MonitorFile: Boolean read FMonitorFile write SetMonitorFile default False;

    property DirectoryPath: string read FDirectoryPath write SetDirectoryPath;
    property MonitorDirectory: Boolean read FMonitorDirectory write SetMonitorDirectory default False;

    property WatchSubtree: Boolean read FWatchSubtree write SetWatchSubtree default False;

    // Debounce settings (ms)
    property EnableDeduplication: Boolean read FEnableDeduplication write SetEnableDeduplication default True;
    property DeduplicationWindow: Integer read FDeduplicationWindow write SetDeduplicationWindow default 500;

    // Preference: when Added & Modified occur within the same debounce window,
    // keep Added by default (can be flipped to False to prefer Modified).
    property PreferAddedOnCreate: Boolean
      read FPreferAddedOnCreate
      write FPreferAddedOnCreate
      default True;

    property OnChange: TMonitorChangeHandler read FOnChange write FOnChange;
  end;

procedure Register;

implementation

{============================= TMonitorItem ===================================}

constructor TMonitorItem.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FWatchSubtree := False;
  FIsFile := False;
  FNotifyFlags := DefaultNotifyFlags;
  FEnabled := True; // matches published default
end;

procedure TMonitorItem.Assign(Source: TPersistent);
begin
  if Source is TMonitorItem then
  begin
    FPath := TMonitorItem(Source).Path;
    FWatchSubtree := TMonitorItem(Source).WatchSubtree;
    FIsFile := TMonitorItem(Source).IsFile;
    FNotifyFlags := TMonitorItem(Source).NotifyFlags;
    FEnabled := TMonitorItem(Source).Enabled;
  end
  else
    inherited Assign(Source);
end;

{============================= TMonitorItems ==================================}

constructor TMonitorItems.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TMonitorItem);
end;

function TMonitorItems.Add: TMonitorItem;
begin
  Result := TMonitorItem(inherited Add);
end;

function TMonitorItems.GetItem(Index: Integer): TMonitorItem;
begin
  Result := TMonitorItem(inherited GetItem(Index));
end;

procedure TMonitorItems.SetItem(Index: Integer; const Value: TMonitorItem);
begin
  inherited SetItem(Index, Value);
end;

{========================== TgllFileSystemMonitor =============================}

constructor TgllFileSystemMonitor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FMonitor := CreateFileSystemMonitor;
  FMonitorItems := TMonitorItems.Create(Self);

  FActive := False;
  FBufferSize := 65536;

  FFilePath := '';
  FMonitorFile := False;

  FDirectoryPath := '';
  FMonitorDirectory := False;

  FWatchSubtree := False;

  // Debounce defaults
  FEnableDeduplication := True;
  FDeduplicationWindow := 500; // ms

  // Legacy placeholders
  FLastChangeTime := 0;
  FLastChangePath := '';
  FLastChangeType := fcModified;

  // Preference: Added vs Modified within window
  FPreferAddedOnCreate := True; // default as requested

  // Aggregator state
  FPendingLock := TObject.Create;
{$IFDEF USE_RAPID_GENERICS}
  FPending := TRapidDictionary<string, TFileChangeType>.Create;
{$ELSE}
  FPending := TDictionary<string, TFileChangeType>.Create;
{$ENDIF}

  FAggregateTimer := TTimer.Create(Self);
  FAggregateTimer.Enabled := False;
  FAggregateTimer.Interval := FDeduplicationWindow;
  FAggregateTimer.OnTimer := FlushPending;
end;

destructor TgllFileSystemMonitor.Destroy;
begin
  Active := False;

  FreeAndNil(FAggregateTimer);

  System.TMonitor.Enter(FPendingLock);
  try
    FPending.Clear;
  finally
    System.TMonitor.Exit(FPendingLock);
  end;
  FreeAndNil(FPending);
  FreeAndNil(FPendingLock);

  FreeAndNil(FMonitorItems);
  FMonitor := nil;

  inherited Destroy;
end;

procedure TgllFileSystemMonitor.Loaded;
begin
  inherited Loaded;

  if FActive and not (csDesigning in ComponentState) then
    StartMonitoring;
end;

procedure TgllFileSystemMonitor.SetActive(const Value: Boolean);
begin
  if FActive = Value then
    Exit;

  FActive := Value;

  if (csLoading in ComponentState) or (csDesigning in ComponentState) then
    Exit;

  if FActive then
    StartMonitoring
  else
    StopMonitoring;
end;

procedure TgllFileSystemMonitor.SetBufferSize(const Value: Integer);
begin
  if FBufferSize = Value then
    Exit;

  FBufferSize := Value;

  if Assigned(FMonitor) then
    FMonitor.BufferSize := Value;
end;

procedure TgllFileSystemMonitor.SetMonitorItems(const Value: TMonitorItems);
begin
  FMonitorItems.Assign(Value);
end;

procedure TgllFileSystemMonitor.SetFilePath(const Value: string);
begin
  if FFilePath = Value then
    Exit;

  FFilePath := Value;

  if FActive and not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
  begin
    StopMonitoring;
    StartMonitoring;
  end;
end;

procedure TgllFileSystemMonitor.SetMonitorFile(const Value: Boolean);
begin
  if FMonitorFile = Value then
    Exit;

  FMonitorFile := Value;

  if FActive and not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
  begin
    StopMonitoring;
    StartMonitoring;
  end;
end;

procedure TgllFileSystemMonitor.SetDirectoryPath(const Value: string);
begin
  if FDirectoryPath = Value then
    Exit;

  FDirectoryPath := Value;

  if FActive and not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
  begin
    StopMonitoring;
    StartMonitoring;
  end;
end;

procedure TgllFileSystemMonitor.SetMonitorDirectory(const Value: Boolean);
begin
  if FMonitorDirectory = Value then
    Exit;

  FMonitorDirectory := Value;

  if FActive and not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
  begin
    StopMonitoring;
    StartMonitoring;
  end;
end;

procedure TgllFileSystemMonitor.SetWatchSubtree(const Value: Boolean);
begin
  if FWatchSubtree = Value then
    Exit;

  FWatchSubtree := Value;

  if FActive and not (csLoading in ComponentState) and not (csDesigning in ComponentState) then
  begin
    StopMonitoring;
    StartMonitoring;
  end;
end;

procedure TgllFileSystemMonitor.SetEnableDeduplication(const Value: Boolean);
begin
  FEnableDeduplication := Value;
end;

procedure TgllFileSystemMonitor.SetDeduplicationWindow(const Value: Integer);
begin
  if Value < 0 then
    Exit;

  FDeduplicationWindow := Value;

  if Assigned(FAggregateTimer) then
    FAggregateTimer.Interval := FDeduplicationWindow;
end;

procedure TgllFileSystemMonitor.InternalOnChange(Sender: TObject;
  const Path: string; ChangeType: TFileChangeType);
begin
  // Marshal to main thread and aggregate; avoids multiple modal pop-ups
  TThread.Queue(nil,
    procedure
    begin
      EnqueueChange(Path, ChangeType);
    end);
end;

procedure TgllFileSystemMonitor.EnqueueChange(const Path: string; ChangeType: TFileChangeType);
var
  Existing: TFileChangeType;
  HasExisting: Boolean;
begin
  System.TMonitor.Enter(FPendingLock);
  try
    HasExisting := FPending.TryGetValue(Path, Existing);

    if HasExisting then
      FPending[Path] := MergeChange(Existing, ChangeType)
    else
      FPending.Add(Path, ChangeType);

    // Restart the quiet timer
    FAggregateTimer.Enabled := False;
    FAggregateTimer.Enabled := True;
  finally
    System.TMonitor.Exit(FPendingLock);
  end;
end;

procedure TgllFileSystemMonitor.FlushPending(Sender: TObject);
var
  Snapshot: TArray<TPair<string, TFileChangeType>>;
  Pair: TPair<string, TFileChangeType>;
  I: Integer;
begin
  // Quiet period elapsed for the batch
  FAggregateTimer.Enabled := False;

  System.TMonitor.Enter(FPendingLock);
  try
    // Build a snapshot without relying on .ToArray (works for Rapid & RTL)
    SetLength(Snapshot, FPending.Count);
    I := 0;
    for Pair in FPending do
    begin
      Snapshot[I] := Pair;
      Inc(I);
    end;
    FPending.Clear;
  finally
    System.TMonitor.Exit(FPendingLock);
  end;

  if Assigned(FOnChange) then
    for Pair in Snapshot do
      FOnChange(Self, Pair.Key, Pair.Value);
end;

function TgllFileSystemMonitor.MergeChange(
  const OldT, NewT: TFileChangeType): TFileChangeType;

  function Rank(T: TFileChangeType): Integer;
  begin
    case T of
      fcRemoved: Exit(5);
      fcRenamedOld,
        fcRenamedNew: Exit(4);
      fcModified: Exit(3);
      fcAdded: Exit(2);
    else
      Exit(1);
    end;
  end;

begin
  // Preference: if both Added and Modified arrive within the window, keep Added when configured
  if FPreferAddedOnCreate then
  begin
    if ((OldT = fcAdded) and (NewT = fcModified)) or
      ((OldT = fcModified) and (NewT = fcAdded)) then
      Exit(fcAdded);
  end;

  if Rank(NewT) >= Rank(OldT) then
    Result := NewT
  else
    Result := OldT;
end;

function TgllFileSystemMonitor.AddDirectory(const Directory: string; WatchSubtree: Boolean;
  NotifyFlags: TNotifyFlags): Boolean;
begin
  Result := False;

  if Assigned(FMonitor) then
    Result := FMonitor.AddDirectory(Directory, WatchSubtree, InternalOnChange, NotifyFlags);
end;

function TgllFileSystemMonitor.AddFile(const FilePath: string; NotifyFlags: TNotifyFlags): Boolean;
begin
  Result := False;

  if Assigned(FMonitor) then
    Result := FMonitor.AddFile(FilePath, InternalOnChange, NotifyFlags);
end;

function TgllFileSystemMonitor.RemoveDirectory(const Directory: string): Boolean;
begin
  Result := False;

  if Assigned(FMonitor) then
    Result := FMonitor.RemoveDirectory(Directory, InternalOnChange);
end;

function TgllFileSystemMonitor.RemoveFile(const FilePath: string): Boolean;
begin
  Result := False;

  if Assigned(FMonitor) then
    Result := FMonitor.RemoveFile(FilePath, InternalOnChange);
end;

procedure TgllFileSystemMonitor.StartMonitoring;
var
  I: Integer;
  Item: TMonitorItem;
  ExpandedPath: string;
begin
  if not Assigned(FMonitor) then
    Exit;

  FMonitor.BufferSize := FBufferSize;

  // Add file monitor if enabled
  if FMonitorFile and (FFilePath <> '') then
  begin
    ExpandedPath := ExpandMacros(FFilePath);
    AddFile(ExpandedPath, [nfFileName, nfLastWrite, nfSize, nfCreation]);
  end;

  // Add directory monitor if enabled
  if FMonitorDirectory and (FDirectoryPath <> '') then
  begin
    ExpandedPath := ExpandMacros(FDirectoryPath);
    AddDirectory(ExpandedPath, FWatchSubtree, [nfFileName, nfDirName, nfSize, nfLastWrite, nfCreation]);
  end;

  // Add collection items
  for I := 0 to FMonitorItems.Count - 1 do
  begin
    Item := FMonitorItems[I];

    if Item.Enabled and (Item.Path <> '') then
    begin
      ExpandedPath := ExpandMacros(Item.Path);

      if Item.IsFile then
        AddFile(ExpandedPath, Item.NotifyFlags)
      else
        AddDirectory(ExpandedPath, Item.WatchSubtree, Item.NotifyFlags);
    end;
  end;
end;

procedure TgllFileSystemMonitor.StopMonitoring;
var
  I: Integer;
  Item: TMonitorItem;
  ExpandedPath: string;
begin
  if not Assigned(FMonitor) then
    Exit;

  // Remove property-based watchers first
  if FMonitorFile and (FFilePath <> '') then
  begin
    ExpandedPath := ExpandMacros(FFilePath);
    RemoveFile(ExpandedPath);
  end;

  if FMonitorDirectory and (FDirectoryPath <> '') then
  begin
    ExpandedPath := ExpandMacros(FDirectoryPath);
    RemoveDirectory(ExpandedPath);
  end;

  // Remove collection-based watchers
  for I := 0 to FMonitorItems.Count - 1 do
  begin
    Item := FMonitorItems[I];

    if Item.Enabled and (Item.Path <> '') then
    begin
      ExpandedPath := ExpandMacros(Item.Path);

      if Item.IsFile then
        RemoveFile(ExpandedPath)
      else
        RemoveDirectory(ExpandedPath);
    end;
  end;

  // Also clear any pending aggregated events
  System.TMonitor.Enter(FPendingLock);
  try
    FPending.Clear;
  finally
    System.TMonitor.Exit(FPendingLock);
  end;

  FAggregateTimer.Enabled := False;
end;

function TgllFileSystemMonitor.IsMonitoring: Boolean;
begin
  Result := False;

  if Assigned(FMonitor) then
    Result := FMonitor.IsMonitoring;
end;

function TgllFileSystemMonitor.ExpandMacros(const Path: string): string;
var
  WorkingPath: string;
begin
  Result := Path;
  WorkingPath := Result;

  // Replace common path macros
  WorkingPath := StringReplace(WorkingPath, '{%AppPath%}', ExtractFilePath(ParamStr(0)), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%AppDir%}', ExtractFilePath(ParamStr(0)), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%ExePath%}', ExtractFilePath(Application.ExeName), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%ExeDir%}', ExtractFilePath(Application.ExeName), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%AppData%}', TPath.GetHomePath, [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%UserProfile%}', TPath.GetHomePath, [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%Temp%}', TPath.GetTempPath, [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%TempDir%}', TPath.GetTempPath, [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%Public%}', TPath.GetPublicPath, [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%Documents%}', TPath.GetDocumentsPath, [rfReplaceAll, rfIgnoreCase]);

  // Environment variables
  WorkingPath := StringReplace(WorkingPath, '{%USERPROFILE%}', GetEnvironmentVariable('USERPROFILE'), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%PROGRAMDATA%}', GetEnvironmentVariable('PROGRAMDATA'), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%LOCALAPPDATA%}', GetEnvironmentVariable('LOCALAPPDATA'), [rfReplaceAll, rfIgnoreCase]);
  WorkingPath := StringReplace(WorkingPath, '{%APPDATA%}', GetEnvironmentVariable('APPDATA'), [rfReplaceAll, rfIgnoreCase]);

  Result := WorkingPath;
end;

procedure Register;
begin
  RegisterComponents('GITLAKLib', [TgllFileSystemMonitor]);
end;

end.
