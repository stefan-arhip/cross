program cross;

{$mode objfpc}{$H+}

uses {$IFDEF UNIX} {$IFDEF UseCThreads}
  cthreads, {$ENDIF} {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  lazcontrols,
  StrUtils,
  Windows,
  Dialogs,
  SysUtils,
  uMain;

{$R *.res}

  function GetUserFromWindows: string;
  var
    UserName: string;
    UserNameLen: dWord;
  begin
    UserNameLen := 255;
    SetLength(UserName, UserNameLen);
    if GetUserName(PChar(UserName), UserNameLen) then
      Result := Copy(UserName, 1, UserNameLen - 1)
    else
      Result := 'Unknown';
  end;

var
  CurrentUser: string;

begin
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  Application.Initialize;

  CurrentUser := GetUserFromWindows;
  //if not AnsiContainsText(',stefan.arhip,t1-stefan,t1-catalin,t1-radu,',
  //  ',' + CurrentUser + ',') then
  //begin
  //  MessageDlg(QuotedStr(CurrentUser) + ' has no rights to use CROSS!',
  //    mtWarning, [mbOK], 0);
  //  Application.Terminate;
  //end
  //else
  begin
    Application.CreateForm(TfMain, fMain);
    Application.Run;
  end;
end.
