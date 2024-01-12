unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, ListViewFilterEdit, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ComCtrls, ExtCtrls, Menus, IniPropStorage, Windows,
  ActiveX, Comobj, Clipbrd, process, LCLVersion, PairSplitter;

const
  icoOnline = 5;
  icoOffline = 6;

type

  TCustomStr = class
  private
    fId: string;
    fIcon: integer;
  public
    property Id: string read fId write fId;
    property Icon: integer read fIcon write fIcon;
    constructor Create(_Id: string; _Icon: integer);
  end;

  { TfMain }

  TfMain = class(TForm)
    cbShowFiles: TCheckBox;
    cbShowFolders: TCheckBox;
    ilSmall: TImageList;
    iniSettings: TIniPropStorage;
    lfFiles: TListViewFilterEdit;
    lvFiles: TListView;
    MenuItem1: TMenuItem;
    miCopy: TMenuItem;
    miDisconnectFile: TMenuItem;
    miDisconnectUser: TMenuItem;
    miOpen: TMenuItem;
    miReload: TMenuItem;
    miSelectAll: TMenuItem;
    N1: TMenuItem;
    psMain: TPairSplitter;
    pssMainLeft: TPairSplitterSide;
    pssMainRight: TPairSplitterSide;
    pmMain: TPopupMenu;
    pR: TProcess;
    sbMain: TStatusBar;
    stInfo: TStaticText;
    procedure cbShowFilesChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure lfFilesAfterFilter(Sender: TObject);
    procedure lvFilesSelectItem(Sender: TObject; Item: TListItem;
      Selected: boolean);
    procedure miCopyClick(Sender: TObject);
    procedure miDisconnectFileClick(Sender: TObject);
    procedure miDisconnectUserClick(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure miReloadClick(Sender: TObject);
    procedure miSelectAllClick(Sender: TObject);
    procedure sbMainClick(Sender: TObject);
    procedure sbMainDrawPanel(StatusBar: TStatusBar; Panel: TStatusPanel;
      const Rect: TRect);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  fMain: TfMain;
  AppDir, TmpDir: string;
  ServerOnline: boolean = False;
  sLOpenFiles: TStringList;

implementation

{$R *.lfm}

{ TfMain }

function RunCmdFile(CmdLine: string): boolean;
begin
  with fMain do
  try
    pR.Executable := 'cmd.exe';
    pR.Parameters.Text := '/c ' + CmdLine;
    pR.Options := [Process.poWaitOnExit];
    pR.ShowWindow := swoHIDE;
    pR.Execute;
    Result := True;
  except
    Result := False;
  end;
end;

function RunCmdFile(aLine: array of string): boolean;
var
  i: integer;
  CmdFile: string;
  sL: TStringList;
begin
  CmdFile := TmpDir + 'cross.bat';
  sL := TStringList.Create;
  for i := Low(aLine) to High(aLine) do
    sL.Add(aLine[i]);
  sL.SaveToFile(CmdFile);
  sL.Free;
  with fMain do
  try
    pR.Executable := 'cmd.exe';
    pR.Parameters.Text := '/c ' + CmdFile;
    pR.Options := [Process.poWaitOnExit];
    pR.ShowWindow := swoHIDE;
    pR.Execute;
    Result := True;
  except
    Result := False;
  end;
end;

function WmiPing(const Address: string; const BufferSize, Timeout: word): integer;
const
  WmiUser = '';
  WmiPassword = '';
  WmiComputer = 'localhost';
  WmiFlagForwardOnly = $00000020;
var
  WmiLocator: olevariant;
  WmiService: olevariant;
  WmiObjectSet: olevariant;
  WmiObject: olevariant;
  oEnum: ActiveX.IEnumvariant;
  WmiQuery: string[250];
  _Nil: longword;
begin
  Result := -1;
  CoInitialize(nil);
  try
    WmiLocator := ComObj.CreateOleObject('WbemScripting.SWbemLocator');
    WmiService := WmiLocator.ConnectServer(WmiComputer, 'root\CIMV2',
      WmiUser, WmiPassword);
    WmiQuery := Format('Select * From Win32_PingStatus ' +
      'Where Address=%s And BufferSize=%d And TimeOut=%d',
      [QuotedStr(Address), BufferSize, Timeout]);
    WmiObjectSet := WmiService.ExecQuery(WmiQuery, 'WQL', WmiFlagForwardOnly);
    oEnum := IUnknown(WmiObjectSet._NewEnum) as IEnumVariant;
    _Nil := 0;
    while oEnum.Next(1, WmiObject, _Nil) = 0 do
    begin
      try
        Result := longint(WmiObject.Properties_.Item('StatusCode').Value);
      except
        Result := -1;
      end;
      WmiObject := Unassigned;
    end;
  finally
    CoUninitialize;
  end;
end;

procedure StringSplit(Delimiter: char; Str: string; ListOfStrings: TStrings);
begin
  ListOfStrings.Clear;
  ListOfStrings.Delimiter := Delimiter;
  ListOfStrings.StrictDelimiter := True;
  ListOfStrings.DelimitedText := Str;
end;

constructor TCustomStr.Create(_Id: string; _Icon: integer);
begin
  fId := _Id;
  fIcon := _Icon;
end;

procedure TfMain.sbMainDrawPanel(StatusBar: TStatusBar; Panel: TStatusPanel;
  const Rect: TRect);
var
  IconStatus: byte;
begin
  if Panel.Index > -1 then
  begin
    with StatusBar.Canvas do
    begin
      Brush.Color := clDefault;
      FillRect(Rect);
      Font.Color := clDefault;
      StatusBar.Canvas.TextRect(Rect, Rect.Left + 18, Rect.Top + 2, Panel.Text);
      if ServerOnline then
        IconStatus := icoOnline
      else
        IconStatus := icoOffline;
      ilSmall.Draw(StatusBar.Canvas, Rect.Left + 2, Rect.Top + 2, IconStatus, True);
    end;
  end;
end;

procedure TfMain.miReloadClick(Sender: TObject);
var
  sFilter, sServer, sFile, sCmd: string;
begin
  Screen.Cursor := crHourGlass;
  sbMain.Refresh;
  sServer := sbMain.Panels[0].Text;
  sbMain.Panels[1].Text := '0 sessions';
  sbMain.Panels[2].Text := '0 filtered';
  sbMain.Panels[3].Text := '0 selected';

  sFilter := lfFiles.Text;
  lfFiles.Text := '';
  lfFiles.Items.Clear;
  lfFiles.FilteredListview := nil;
  lvFiles.Items.BeginUpdate;
  lvFiles.Items.Clear;

  ServerOnline := WmiPing(sServer, 32, 100) = 0;
  sbMain.Refresh;
  if ServerOnline then
  begin
    sFile := TmpDir + 'cross.csv';
    sCmd := 'openfiles /query /s %s /fo csv > "%s"';
    //if RunCmdFile('openfiles /query /s ' + sServer + ' /fo csv > "' + TmpDir + 'cross.csv' + '"') then
    if RunCmdFile(Format(sCmd, [sServer, sFile])) then
      sLOpenFiles.LoadFromFile(TmpDir + 'cross.csv')
    else
      sLOpenFiles.Clear;

    cbShowFilesChange(Sender);
  end;
  lvFiles.Items.EndUpdate;
  lfFiles.FilteredListview := lvFiles;
  sbMain.Panels[1].Text := Format('%d sessions', [lvFiles.Items.Count]);
  lfFiles.Text := sFilter;
  Screen.Cursor := crDefault;
  //lvFiles.StateImages := ilSmall;
  //for i := 1 to lvFiles.Items.Count do
  //  lvFiles.Items[i - 1].StateIndex := 3;
  // Remote Unlock Shared Open Session
end;

procedure TfMain.miSelectAllClick(Sender: TObject);
begin
  lvFiles.SelectAll;
end;

procedure TfMain.sbMainClick(Sender: TObject);
var
  Server: string;
var
  mpt: TPoint;
  x, i, Panel: integer;
  //  b: boolean;
  //  s: string;
begin
  //no StatusPanels defined
  if (sbMain.SimplePanel) or (sbMain.Panels.Count = 0) then
  begin
    //Clicked on a StatusBar, no Panels
    Exit;
  end;
  mpt := sbMain.ScreenToClient(Mouse.CursorPos);

  Panel := -1;
  x := 0;
  for i := 1 to sbMain.Panels.Count do
  begin
    x := x + sbMain.Panels[i - 1].Width;
    if mpt.X < x then
    begin
      Panel := i - 1;
      Break;
    end;
  end;
  //clicked "after" the last panel
  if Panel = -1 then
    Panel := sbMain.Panels.Count - 1;
  if Panel = 0 then
  begin
    Server := sbMain.Panels[0].Text;
    if InputQuery('Server', 'Server to scan:', Server) then
    begin
      sbMain.Panels[0].Text := Server;
      miReloadClick(Sender);
    end;
  end;
end;

procedure TfMain.miDisconnectFileClick(Sender: TObject);
var
  sServer, sFile, sCmd: string;
  aCmd: array of string;
  i: integer;
begin
  sServer := sbMain.Panels[0].Text;
  sCmd := 'openfiles /s %s /disconnect /ID %s';
  SetLength(aCmd, 0);
  for i := 1 to lvFiles.Items.Count do
    if lvFiles.Items[i - 1].Selected then
    begin
      sFile := TCustomStr(lvFiles.Items[i - 1].Data).Id;
      SetLength(aCmd, Length(aCmd) + 1);
      aCmd[Length(aCmd) - 1] := Format(sCmd, [sServer, sFile]);
    end;
  if Length(aCmd) > 0 then
    if RunCmdFile(aCmd) then
      miReloadClick(Sender);
end;

procedure TfMain.miCopyClick(Sender: TObject);
var
  i, j, k: integer;
  s: string;
  sL: TStringList;
begin
  sL := TStringList.Create;
  s := '';
  for j := 1 to lvFiles.Columns.Count do
    s := s + #9 + lvFiles.Column[j - 1].DisplayName;
  Delete(s, 1, 1);
  sL.Add(s);
  k := 0;
  for i := 1 to lvFiles.Items.Count do
    if lvFiles.Items[i - 1].Selected then
    begin
      Inc(k);
      s := lvFiles.Items[i - 1].Caption;
      for j := 2 to lvFiles.Columns.Count do
        s := s + #9 + lvFiles.Items[i - 1].SubItems[j - 2];
      sL.Add(s);
    end;
  if k > 0 then
    Clipboard.AsText := sL.Text;
end;

procedure TfMain.FormCreate(Sender: TObject);
begin
  stInfo.Caption := Format('Lazarus %s - FPC %s - CPU %s - %s  '#13'%s  ',
    [lcl_version, {$I %FPCVersion%}, {$I %FPCTarget%},
    FormatDateTime('yyyymmdd-hhnn', FileDateToDateTime(FileAge(Application.ExeName))),
    'created by Ștefan Arhip']);
  sbMain.Panels[0].Style := psOwnerDraw;
end;

procedure TfMain.cbShowFilesChange(Sender: TObject);
var
  sLine, sFilter: string;
  sLSplit: TStringList;
  //i: integer;
  boolFile, boolFolder: boolean;
begin
  Screen.Cursor := crHourGlass;
  sbMain.Refresh;
  sbMain.Panels[1].Text := '0 sessions';
  sbMain.Panels[2].Text := '0 filtered';
  sbMain.Panels[3].Text := '0 selected';

  sFilter := lfFiles.Text;
  lfFiles.Text := '';
  lfFiles.Items.Clear;
  lfFiles.FilteredListview := nil;
  lvFiles.Items.BeginUpdate;
  lvFiles.Items.Clear;

  sLSplit := TStringList.Create;
  for sLine in sLOpenFiles do
  begin
    StringSplit(',', sLine, sLSplit);
    if (sLSplit.Count = 4) and (sLSplit[0] <> 'ID') then
    begin
      boolFolder := False;
      boolFile := False;
      if DirectoryExists(sLSplit[3]) then
        boolFolder := True
      else //FileExists(sLSplit[3]) then
        boolFile := True;
      if (cbShowFiles.Checked and boolFile) or
        (cbShowFolders.Checked and boolFolder) then
        with lvFiles.Items.Add do
        begin
          //StateIndex := 0;
          Caption := sLSplit[1];
          if boolFolder then
          begin
            StateIndex := 7;
            SubItems.Add('');
            SubItems.Add(sLSplit[3]);
          end
          else
          begin
            StateIndex := 8;
            SubItems.Add(ExtractFileName(sLSplit[3]));
            SubItems.Add(ExtractFileDir(sLSplit[3]));
          end;
          Data := TCustomStr.Create(sLSplit[0], StateIndex);
        end;
    end;
  end;
  sLSplit.Free;

  lvFiles.Items.EndUpdate;
  lfFiles.FilteredListview := lvFiles;
  sbMain.Panels[1].Text := Format('%d sesions', [lvFiles.Items.Count]);
  lfFiles.Text := sFilter;
  Screen.Cursor := crDefault;
end;

procedure TfMain.FormShow(Sender: TObject);
begin
  lfFiles.FilteredListview := lvFiles;
  miReloadClick(Sender);
end;

procedure TfMain.lfFilesAfterFilter(Sender: TObject);
var
  i: integer;
begin
  sbMain.Panels[2].Text := Format('%d filtered', [lvFiles.Items.Count]);
  for i := 1 to lvFiles.Items.Count do
    ///if DirectoryExists(lvFiles.Items[i - 1].SubItems[0]) then
    if Length(lvFiles.Items[i - 1].SubItems[0]) = 0 then
      lvFiles.Items[i - 1].StateIndex := 7
    else
      lvFiles.Items[i - 1].StateIndex := 8;
end;

procedure TfMain.lvFilesSelectItem(Sender: TObject; Item: TListItem; Selected: boolean);
var
  i, j: integer;
begin
  j := 0;
  for i := 1 to lvFiles.Items.Count do
    if lvFiles.Items[i - 1].Selected then
      Inc(j);
  sbMain.Panels[3].Text := Format('%d selected', [j]);
end;

procedure TfMain.miDisconnectUserClick(Sender: TObject);
var
  sServer, sUser, sCmd: string;
  aCmd: array of string;
  i, j: integer;
  b: boolean;
begin
  sServer := sbMain.Panels[0].Text;
  sCmd := 'openfiles /s %s /disconnect /a %s';
  SetLength(aCmd, 0);
  for i := 1 to lvFiles.Items.Count do
    if lvFiles.Items[i - 1].Selected then
    begin
      sUser := lvFiles.Items[lvFiles.ItemIndex].Caption;
      b := False;
      for j := Low(aCmd) to High(aCmd) do
        if Format(sCmd, [sServer, sUser]) = aCmd[j] then
        begin
          b := True;
          Break;
        end;
      if not b then
      begin
        SetLength(aCmd, Length(aCmd) + 1);
        aCmd[Length(aCmd) - 1] := Format(sCmd, [sServer, sUser]);
      end;
    end;
  if Length(aCmd) > 0 then
    if RunCmdFile(aCmd) then
      miReloadClick(Sender);
end;

procedure TfMain.miOpenClick(Sender: TObject);
var
  sFile, sResult: string;
begin
  if lvFiles.ItemIndex > -1 then
  begin
    sFile := lvFiles.Items[lvFiles.ItemIndex].SubItems[1];
    //if sFile[2] = ':' then
    //  sFile[2] := '$';
    //sFile := '\\' + sbMain.Panels[0].Text + '\' + sFile;
    RunCommand('explorer.exe', [sFile], sResult);
    //RunAsAdmin(fMain.Handle, sFile, '');
  end;
end;

initialization
  AppDir := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));
  TmpDir := IncludeTrailingPathDelimiter(SysUtils.GetTempDir + 'laz-cross\');
  ForceDirectories(TmpDir);
  sLOpenFiles := TStringList.Create;

finalization
  sLOpenFiles.Free;

end.
