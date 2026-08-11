// anydoc VCL 데모 — 문서를 GitHub Flavored Markdown 으로 변환해 보여준다.
//
// 화면에 노출되는 문구는 모두 영문이다. 실패 문구는 TSCAnydoc 이 조립한 한글
// Message 대신 EAnydocError 의 Status 와 Detail(코어가 준 영문 원문)로 직접 만든다.
//
// 이 샘플이 보여주는 것
//   * TSCAnydoc 로 파일/바이트 변환과 포맷 감지
//   * 변환은 동기 blocking 이므로 워커 스레드에서 수행하고 UI 갱신만 TThread.Queue 로 위임
//   * EAnydocError 의 Status 로 실패 원인 구분
//   * 탐색기에서 파일을 끌어다 놓기 (WM_DROPFILES)
unit Main;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls;
{$ENDREGION}

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    btnOpen: TButton;
    btnSave: TButton;
    lblFile: TLabel;
    memMarkdown: TMemo;
    sbStatus: TStatusBar;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnOpenClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FBusy: Boolean;
    FFileName: string;
    procedure ConvertFile(const AFileName: string);
    procedure ShowFailure(const AFileName, AError: string);
    procedure ShowSuccess(const AFileName, AMarkdown, AFormat: string; const AElapsedMs: Int64);
    procedure UpdateControls;
    procedure WMDropFiles(var AMessage: TWMDropFiles); message WM_DROPFILES;
  protected
    procedure CreateWnd; override;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

{$REGION 'uses'}
uses
  System.IOUtils,
  System.Diagnostics,
  Winapi.ShellAPI,
  SCAnydoc;
{$ENDREGION}

const
  // 상태바 패널 인덱스
  PANEL_STATE = 0;
  PANEL_FORMAT = 1;
  PANEL_ELAPSED = 2;
  PANEL_VERSION = 3;

// 화면 표기용 영문 상태명. SCAnydoc 의 TAnydocStatus.ToString 은 한글이므로
// 영문 UI 인 이 데모에서는 여기서 따로 매핑한다.
function StatusText(const AStatus: TAnydocStatus): string;
begin
  case AStatus of
    asOk:
      Result := 'OK';
    asUnsupported:
      Result := 'Unsupported format';
    asMalformed:
      Result := 'Malformed document';
    asEncrypted:
      Result := 'Encrypted document';
    asResourceLimit:
      Result := 'Resource limit exceeded';
    asMissingPart:
      Result := 'Missing required part';
    asIo:
      Result := 'I/O error';
    asInvalidArg:
      Result := 'Invalid argument';
    asPanic:
      Result := 'Conversion engine panic';
  else
    Result := 'Unknown error';
  end;
end;

{$REGION 'TfrmMain'}
procedure TfrmMain.btnOpenClick(Sender: TObject);
begin
  if not dlgOpen.Execute(Handle) then
  begin
    Exit;
  end;

  ConvertFile(dlgOpen.FileName);
end;

procedure TfrmMain.btnSaveClick(Sender: TObject);
begin
  dlgSave.FileName := TPath.GetFileNameWithoutExtension(FFileName) + '.md';
  if not dlgSave.Execute(Handle) then
  begin
    Exit;
  end;

  // 마크다운은 UTF-8 로 저장한다.
  TFile.WriteAllText(dlgSave.FileName, memMarkdown.Lines.Text, TEncoding.UTF8);
  sbStatus.Panels[PANEL_STATE].Text := 'Saved: ' + TPath.GetFileName(dlgSave.FileName);
end;

procedure TfrmMain.ConvertFile(const AFileName: string);
var
  LFileName: string;   // 익명 메서드가 캡처하므로 var 블록에 선언 (인라인 변수 캡처 불가)
begin
  if FBusy then
  begin
    Exit;
  end;

  LFileName := AFileName;
  FBusy := True;
  UpdateControls;

  lblFile.Caption := TPath.GetFileName(LFileName);
  sbStatus.Panels[PANEL_STATE].Text := 'Converting...';
  sbStatus.Panels[PANEL_FORMAT].Text := '';
  sbStatus.Panels[PANEL_ELAPSED].Text := '';

  TThread.CreateAnonymousThread(
    procedure
    var
      LMarkdown: string;
      LFormat: string;
      LError: string;
      LElapsedMs: Int64;
    begin
      var LWatch := TStopwatch.StartNew;
      try
        // 파일 읽기를 델파이가 담당 → DLL 에 경로를 넘기지 않으므로 유니코드 경로에 안전
        var LBytes := TFile.ReadAllBytes(LFileName);
        LFormat := TSCAnydoc.DetectFormat(LBytes);
        LMarkdown := TSCAnydoc.ToMarkdown(LBytes, TPath.GetExtension(LFileName));

        // 시그니처가 없는 CSV 는 감지되지 않지만 확장자 힌트로 변환된다
        if LFormat = '' then
        begin
          LFormat := TPath.GetExtension(LFileName).TrimLeft(['.']).ToLower + ' (by extension)';
        end;
      except
        on E: EAnydocError do
        begin
          // 한글로 조립된 Message 대신 Status + Detail(코어 원문, 영문)로 직접 만든다.
          LError := Format('%s'#13#10#13#10'%s', [StatusText(E.Status), E.Detail]);
        end;
        on E: Exception do
        begin
          LError := Format('%s'#13#10#13#10'%s', [E.ClassName, E.Message]);
        end;
      end;

      LElapsedMs := LWatch.ElapsedMilliseconds;

      // UI 갱신은 반드시 메인 스레드에서. 폼이 닫히는 중이면 실행되지 않도록
      // FormCloseQuery 가 변환 중 종료를 막는다.
      TThread.Queue(nil,
        procedure
        begin
          FBusy := False;
          if LError <> '' then
          begin
            ShowFailure(LFileName, LError);
          end
          else
          begin
            ShowSuccess(LFileName, LMarkdown, LFormat, LElapsedMs);
          end;

          UpdateControls;
        end);
    end).Start;
end;

procedure TfrmMain.CreateWnd;
begin
  inherited;

  // 핸들이 재생성될 때마다(DPI 변경 등) 다시 등록해야 드롭이 계속 동작한다.
  DragAcceptFiles(Handle, True);
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // 변환 중 폼이 파괴되면 Queue 로 넘긴 코드가 죽은 폼을 건드려 AV 가 난다.
  CanClose := not FBusy;
  if not CanClose then
  begin
    MessageDlg('Please wait until the conversion finishes.', mtInformation, [mbOK], 0);
  end;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  dlgOpen.Filter :=
    'All supported documents|*.doc;*.docx;*.docm;*.odt;*.rtf;*.epub;*.pdf;' +
    '*.ppt;*.pptx;*.pptm;*.odp;*.xls;*.xlsx;*.xlsm;*.xlsb;*.ods;*.csv|' +
    'Word documents|*.doc;*.docx;*.docm;*.odt;*.rtf|' +
    'Presentations|*.ppt;*.pptx;*.pptm;*.odp|' +
    'Spreadsheets|*.xls;*.xlsx;*.xlsm;*.xlsb;*.ods;*.csv|' +
    'PDF|*.pdf|' +
    'EPUB|*.epub|' +
    'All files|*.*';
  dlgSave.Filter := 'Markdown|*.md|All files|*.*';

  if TSCAnydoc.IsAvailable then
  begin
    sbStatus.Panels[PANEL_VERSION].Text :=
      Format('anydoc %s / ABI %d', [TSCAnydoc.CoreVersion, TSCAnydoc.AbiVersion]);
    sbStatus.Panels[PANEL_STATE].Text := 'Open a document, or drop one onto this window.';

    // 실행 파일에 문서를 끌어다 놓거나 '연결 프로그램'으로 열었을 때 바로 변환한다.
    if (ParamCount > 0) and TFile.Exists(ParamStr(1)) then
    begin
      ConvertFile(ParamStr(1));
    end;
  end
  else
  begin
    sbStatus.Panels[PANEL_VERSION].Text := 'DLL not found';
    sbStatus.Panels[PANEL_STATE].Text := 'sc_anydoc.dll could not be loaded.';
    memMarkdown.Lines.Text :=
      'sc_anydoc.dll could not be loaded.' + sLineBreak + sLineBreak +
      'Place it next to this executable, or add its folder to PATH:' + sLineBreak +
      '  64-bit: C:\Works\lib\dll\sc_anydoc.dll' + sLineBreak +
      '  32-bit: C:\Works\lib\dll\win32\sc_anydoc.dll' + sLineBreak + sLineBreak +
      'Build the DLL with build_anydoc.ps1.';
    btnOpen.Enabled := False;
  end;
end;

procedure TfrmMain.ShowFailure(const AFileName, AError: string);
begin
  FFileName := '';
  memMarkdown.Lines.Text := AError;
  sbStatus.Panels[PANEL_STATE].Text := 'Conversion failed: ' + TPath.GetFileName(AFileName);
  sbStatus.Panels[PANEL_FORMAT].Text := '';
  sbStatus.Panels[PANEL_ELAPSED].Text := '';
end;

procedure TfrmMain.ShowSuccess(const AFileName, AMarkdown, AFormat: string;
  const AElapsedMs: Int64);
begin
  FFileName := AFileName;

  memMarkdown.Lines.BeginUpdate;
  try
    memMarkdown.Lines.Text := AMarkdown;
  finally
    memMarkdown.Lines.EndUpdate;
  end;

  memMarkdown.SelStart := 0;
  memMarkdown.Perform(EM_SCROLLCARET, 0, 0);

  sbStatus.Panels[PANEL_STATE].Text := Format('Converted - %d chars', [AMarkdown.Length]);
  sbStatus.Panels[PANEL_FORMAT].Text := 'Format: ' + AFormat;
  sbStatus.Panels[PANEL_ELAPSED].Text := Format('%d ms', [AElapsedMs]);
end;

procedure TfrmMain.UpdateControls;
begin
  btnOpen.Enabled := not FBusy and TSCAnydoc.IsAvailable;
  btnSave.Enabled := not FBusy and (FFileName <> '');

  if FBusy then
  begin
    Screen.Cursor := crHourGlass;
  end
  else
  begin
    Screen.Cursor := crDefault;
  end;
end;

procedure TfrmMain.WMDropFiles(var AMessage: TWMDropFiles);
begin
  inherited;

  var LCount := DragQueryFile(AMessage.Drop, $FFFFFFFF, nil, 0);
  try
    if LCount = 0 then
    begin
      Exit;
    end;

    // 여러 개를 놓아도 첫 번째만 변환한다 (샘플이므로 단순하게).
    var LNeeded := DragQueryFile(AMessage.Drop, 0, nil, 0);
    var LBuffer: string;
    SetLength(LBuffer, LNeeded);
    DragQueryFile(AMessage.Drop, 0, PChar(LBuffer), LNeeded + 1);

    ConvertFile(LBuffer);
  finally
    DragFinish(AMessage.Drop);
  end;

  AMessage.Result := 0;
end;
{$ENDREGION}

end.
