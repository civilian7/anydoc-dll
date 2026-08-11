// TEdgeBrowser 를 마크다운 프리뷰어로 운전하는 어댑터.
//
// 셸 페이지(preview.html + marked.min.js)는 리소스에서 조립해 NavigateToString 으로
// 딱 한 번만 띄운다. 이후 마크다운은 PostWebMessageAsString 으로 원문 그대로 넘기므로
// 재탐색도, JS 문자열 이스케이프도 필요 없다.
//
// 생명주기가 3단계로 비동기라는 점이 이 유닛의 전부다.
//   1) CreateWebView        -> OnCreateWebViewCompleted (WebView2 런타임 없으면 여기서 실패)
//   2) NavigateToString(셸) -> 셸의 스크립트가 'ready' 메시지를 보냄
//   3) 그 이후에야 PostWebMessage 가 유실 없이 전달된다
// 준비 전에 들어온 갱신 요청은 FPending 으로 보류했다가 3) 시점에 흘려보낸다.
unit Preview;

interface

{$REGION 'uses'}
uses
  System.Classes,
  Winapi.Windows,
  Winapi.WebView2,
  Vcl.Edge;
{$ENDREGION}

type
  /// <summary>프리뷰를 쓸 수 없을 때 알리는 이벤트.</summary>
  TPreviewUnavailableEvent = procedure(Sender: TObject; const AMessage: string) of object;

  /// <summary>
  /// TEdgeBrowser 하나를 마크다운 프리뷰 화면으로 운전한다.
  /// WebView2 초기화는 <see cref="Show"/> 를 처음 부를 때까지 미뤄지므로,
  /// 프리뷰를 열지 않는 사용자는 초기화 비용을 전혀 치르지 않는다.
  /// </summary>
  TMarkdownPreview = class
  private
    FBrowser: TEdgeBrowser;
    FMarkdown: string;
    FPending: Boolean;
    FShellReady: Boolean;
    FStarted: Boolean;
    FUnavailable: Boolean;

    FOnUnavailable: TPreviewUnavailableEvent;
    procedure BrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure BrowserNavigationCompleted(Sender: TCustomEdgeBrowser; AIsSuccess: Boolean;
      AWebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure BrowserNavigationStarting(Sender: TCustomEdgeBrowser; AArgs: TNavigationStartingEventArgs);
    procedure BrowserWebMessageReceived(Sender: TCustomEdgeBrowser; AArgs: TWebMessageReceivedEventArgs);
    function  BuildShellHtml: string;
    procedure DoUnavailable(const AMessage: string);
    procedure Flush;
  public
    /// <summary>주어진 브라우저 컨트롤에 프리뷰 동작을 붙인다. 컨트롤의 수명은 폼이 관리한다.</summary>
    /// <param name="ABrowser">프리뷰를 표시할 TEdgeBrowser. nil 이면 안 된다.</param>
    constructor Create(const ABrowser: TEdgeBrowser);

    /// <summary>브라우저에 걸어 둔 콜백을 떼어낸다. 컨트롤보다 먼저 해제돼도 안전하다.</summary>
    destructor Destroy; override;

    /// <summary>표시할 마크다운을 지정한다. 실제 렌더는 <see cref="Show"/> 에서 일어난다.</summary>
    /// <param name="AMarkdown">GitHub Flavored Markdown 원문</param>
    procedure SetMarkdown(const AMarkdown: string);

    /// <summary>프리뷰가 화면에 드러날 때 호출한다. 첫 호출에서 WebView2 를 초기화하고,
    /// 준비가 끝나 있으면 대기 중인 마크다운을 렌더한다.</summary>
    procedure Show;

    /// <summary>WebView2 를 쓸 수 없어 프리뷰가 불가능한 상태인지.</summary>
    property IsUnavailable: Boolean read FUnavailable;

    /// <summary>프리뷰 초기화에 실패했을 때 발생한다. 호출 측이 안내 문구를 띄우는 용도.</summary>
    property OnUnavailable: TPreviewUnavailableEvent read FOnUnavailable write FOnUnavailable;
  end;

implementation

{$REGION 'uses'}
uses
  System.SysUtils,
  System.IOUtils,
  Winapi.ActiveX,
  Winapi.ShellAPI;
{$ENDREGION}

const
  // AnydocDemo.rc 가 묶어 넣은 RCDATA 이름
  RES_PREVIEW_HTML = 'PREVIEW_HTML';
  RES_MARKED_JS = 'MARKED_JS';

  // 셸 HTML 안에서 marked.js 가 들어갈 자리
  MARKED_PLACEHOLDER = '{{MARKED_JS}}';

  // 셸 페이지가 로드를 마쳤음을 알리는 신호
  SHELL_READY_MESSAGE = 'ready';

// RCDATA 리소스를 UTF-8 텍스트로 읽는다. 편집기가 붙였을 수 있는 BOM 은 걷어낸다.
function LoadResourceText(const AResourceName: string): string;
begin
  var LStream := TResourceStream.Create(HInstance, AResourceName, RT_RCDATA);
  try
    var LBytes: TBytes;
    SetLength(LBytes, LStream.Size);
    LStream.ReadBuffer(LBytes, Length(LBytes));
    Result := TEncoding.UTF8.GetString(LBytes);
  finally
    LStream.Free;
  end;

  if Result.StartsWith(#$FEFF) then
  begin
    Delete(Result, 1, 1);
  end;
end;

// COM 이 할당해 돌려준 문자열을 Delphi 문자열로 옮기고 원본을 해제한다.
function TakeComString(const AValue: PWideChar): string;
begin
  if AValue = nil then
  begin
    Exit('');
  end;

  Result := string(AValue);
  CoTaskMemFree(AValue);
end;

{$REGION 'TMarkdownPreview'}
constructor TMarkdownPreview.Create(const ABrowser: TEdgeBrowser);
begin
  inherited Create;

  FBrowser := ABrowser;
  FBrowser.OnCreateWebViewCompleted := BrowserCreateWebViewCompleted;
  FBrowser.OnNavigationCompleted := BrowserNavigationCompleted;
  FBrowser.OnNavigationStarting := BrowserNavigationStarting;
  FBrowser.OnWebMessageReceived := BrowserWebMessageReceived;

  // 기본값은 실행 파일 옆이라 Program Files 아래에서는 초기화가 실패한다.
  // 쓰기가 보장된 사용자 로컬 폴더로 돌린다.
  FBrowser.UserDataFolder := TPath.Combine(TPath.GetCachePath, 'AnydocDemo\WebView2');
end;

destructor TMarkdownPreview.Destroy;
begin
  // 이 객체가 사라진 뒤 컨트롤이 콜백을 쏘면 해제된 메서드를 호출하게 된다.
  FBrowser.OnCreateWebViewCompleted := nil;
  FBrowser.OnNavigationCompleted := nil;
  FBrowser.OnNavigationStarting := nil;
  FBrowser.OnWebMessageReceived := nil;

  inherited;
end;

procedure TMarkdownPreview.BrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  if not Succeeded(AResult) then
  begin
    DoUnavailable(Format('WebView2 could not be initialized (0x%.8x). ' +
      'Install the Microsoft Edge WebView2 Runtime to enable the preview.', [AResult]));
    Exit;
  end;

  FBrowser.NavigateToString(BuildShellHtml);
end;

// 셸 로드의 성패를 여기서 확정한다. 실패하면 화면이 빈 채로 남으므로 이유를 드러내고,
// 성공하면 셸의 'ready' 메시지가 유실되더라도 준비된 것으로 본다 — 탐색이 끝났다는 것은
// 셸의 스크립트가 이미 실행됐다는 뜻이다.
procedure TMarkdownPreview.BrowserNavigationCompleted(Sender: TCustomEdgeBrowser;
  AIsSuccess: Boolean; AWebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
  if FShellReady then
  begin
    Exit;
  end;

  if not AIsSuccess then
  begin
    DoUnavailable(Format('The preview page failed to load (WebView2 error status %d).',
      [Integer(AWebErrorStatus)]));
    Exit;
  end;

  FShellReady := True;
  Flush;
end;

// 문서 안의 링크만 기본 브라우저로 넘긴다.
//
// 셸 자체의 로드는 절대 막으면 안 된다. NavigateToString 이 만들어내는 주소는
// 런타임 버전에 따라 about:blank 일 수도, data: 일 수도 있어 화이트리스트로 걸러내면
// 셸 로드가 취소되어 화면이 까맣게 남는다. 그래서 조건을 뒤집어, 셸이 준비된 뒤에
// 나타나는 http/https 만 외부 링크로 간주한다.
procedure TMarkdownPreview.BrowserNavigationStarting(Sender: TCustomEdgeBrowser;
  AArgs: TNavigationStartingEventArgs);
var
  LUri: PWideChar;
begin
  if not FShellReady then
  begin
    Exit;
  end;

  if not Succeeded(AArgs.ArgsInterface.Get_uri(LUri)) then
  begin
    Exit;
  end;

  var LTarget := TakeComString(LUri);
  if not (LTarget.StartsWith('http://', True) or LTarget.StartsWith('https://', True)) then
  begin
    Exit;
  end;

  AArgs.ArgsInterface.Set_Cancel(1);
  ShellExecute(0, 'open', PChar(LTarget), nil, nil, SW_SHOWNORMAL);
end;

procedure TMarkdownPreview.BrowserWebMessageReceived(Sender: TCustomEdgeBrowser;
  AArgs: TWebMessageReceivedEventArgs);
var
  LMessage: PWideChar;
begin
  if not Succeeded(AArgs.ArgsInterface.TryGetWebMessageAsString(LMessage)) then
  begin
    Exit;
  end;

  if TakeComString(LMessage) <> SHELL_READY_MESSAGE then
  begin
    Exit;
  end;

  FShellReady := True;
  Flush;
end;

// 셸 HTML 에 marked.js 를 통째로 인라인한다. 외부 파일을 참조하지 않으므로
// CSP 를 조이고도 완전히 오프라인으로 동작한다.
function TMarkdownPreview.BuildShellHtml: string;
begin
  // 첫 항목만 치환한다 — 자리 표시자가 두 번 나오면 엉뚱한 곳에 끼워진다.
  Result := LoadResourceText(RES_PREVIEW_HTML)
    .Replace(MARKED_PLACEHOLDER, LoadResourceText(RES_MARKED_JS), []);

  // 치환에 실패하면 화면이 조용히 백지가 되므로 여기서 드러낸다.
  if Result.Contains(MARKED_PLACEHOLDER) then
  begin
    raise Exception.CreateFmt('셸 페이지에 %s 자리 표시자가 둘 이상 있습니다 (preview.html 확인 필요)',
      [MARKED_PLACEHOLDER]);
  end;
end;

procedure TMarkdownPreview.DoUnavailable(const AMessage: string);
begin
  FUnavailable := True;
  if Assigned(FOnUnavailable) then
  begin
    FOnUnavailable(Self, AMessage);
  end;
end;

// 셸이 준비된 뒤에만 실제로 보낸다. 그 전 호출은 FPending 으로 남아 여기서 소화된다.
procedure TMarkdownPreview.Flush;
begin
  if not (FPending and FShellReady) then
  begin
    Exit;
  end;

  if not Assigned(FBrowser.DefaultInterface) then
  begin
    Exit;
  end;

  FBrowser.DefaultInterface.PostWebMessageAsString(PChar(FMarkdown));
  FPending := False;
end;

procedure TMarkdownPreview.SetMarkdown(const AMarkdown: string);
begin
  FMarkdown := AMarkdown;
  FPending := True;
end;

procedure TMarkdownPreview.Show;
begin
  if FUnavailable then
  begin
    Exit;
  end;

  if not FStarted then
  begin
    FStarted := True;

    // 런타임이 없으면 여기서 예외가 나기도 하고, 비동기로 실패가 돌아오기도 한다.
    try
      FBrowser.CreateWebView;
    except
      on E: Exception do
      begin
        DoUnavailable(Format('WebView2 could not be initialized (%s: %s). ' +
          'Install the Microsoft Edge WebView2 Runtime to enable the preview.', [E.ClassName, E.Message]));
      end;
    end;

    Exit;
  end;

  Flush;
end;
{$ENDREGION}

end.
