// SCAnydoc — sc_anydoc.dll (anydoc 코어) 델파이 래퍼.
//
// 문서(Word/PowerPoint/Excel/OpenDocument/RTF/EPUB/CSV/PDF)를 GitHub Flavored
// Markdown 으로 변환한다. Win32/Win64 모두 동일한 선언으로 동작한다 —
// export 이름에 데코레이션이 없고, NativeUInt 가 Rust usize 와 자동으로 맞는다.
//
// DLL 배포 위치
//   64비트 : <lib>\dll\sc_anydoc.dll
//   32비트 : <lib>\dll\win32\sc_anydoc.dll   (동일명, 접미어 없음)
//
// 변환은 동기 blocking 이다. UI 프로젝트에서는 워커 스레드에서 호출하고
// 결과만 TThread.Queue 로 메인 스레드에 넘긴다.
unit SCAnydoc;

interface

{$REGION 'uses'}
uses
  System.SysUtils;
{$ENDREGION}

type
  /// <summary>변환 결과 상태. DLL 이 돌려주는 상태코드와 1:1 대응합니다.</summary>
  TAnydocStatus = (
    asOk,
    asUnsupported,
    asMalformed,
    asEncrypted,
    asResourceLimit,
    asMissingPart,
    asIo,
    asInvalidArg,
    asPanic,
    asUnknown
  );

  TAnydocStatusHelper = record helper for TAnydocStatus
    /// <summary>상태를 사람이 읽을 한글 설명으로 변환합니다.</summary>
    function ToString: string;
  end;

  /// <summary>anydoc 변환 실패 시 발생합니다. 원인은 <see cref="Status"/> 로 구분합니다.</summary>
  EAnydocError = class(Exception)
  private
    FDetail: string;
    FStatus: TAnydocStatus;
  public
    /// <summary>상태와 원본 상세 메시지로 예외를 만듭니다. Message 는 둘을 합쳐 조립됩니다.</summary>
    /// <param name="AStatus">실패 원인 분류</param>
    /// <param name="ADetail">DLL 이 돌려준 원본 상세 메시지</param>
    constructor Create(const AStatus: TAnydocStatus; const ADetail: string);

    /// <summary>
    ///   DLL 이 돌려준 원본 상세 메시지. 코어가 생성하므로 항상 영문이며 로케일에
    ///   의존하지 않습니다. 표시 문구를 직접 조립할 때 <see cref="Status"/> 와 함께 씁니다.
    /// </summary>
    property Detail: string read FDetail;

    /// <summary>실패 원인 분류.</summary>
    property Status: TAnydocStatus read FStatus;
  end;

  /// <summary>
  ///   sc_anydoc.dll 진입점. 모든 메서드가 클래스 메서드이며 내부 상태를 두지 않아
  ///   어느 스레드에서든 동시에 호출할 수 있습니다.
  /// </summary>
  TSCAnydoc = class
  private
    class function  BytesToString(const AText: PAnsiChar; const ALen: NativeUInt): string; static;
    class procedure RaiseIfFailed(const ACode: Integer; const AError: PAnsiChar;
      const AErrorLen: NativeUInt); static;
  public
    /// <summary>DLL 이 구현하는 C ABI 버전. 이 유닛은 1 을 기대합니다.</summary>
    /// <returns>ABI 버전 번호</returns>
    /// <exception cref="EAnydocError">DLL 을 로드할 수 없는 경우 발생</exception>
    class function  AbiVersion: Cardinal; static;

    /// <summary>DLL 에 링크된 anydoc 코어 버전을 반환합니다 (예: '0.1.8').</summary>
    /// <returns>코어 버전 문자열</returns>
    class function  CoreVersion: string; static;

    /// <summary>
    ///   문서 내용만으로 포맷을 감지합니다. 확장자는 보지 않습니다.
    ///   시그니처가 없는 CSV 나 인식할 수 없는 데이터는 빈 문자열을 반환합니다.
    /// </summary>
    /// <param name="AData">문서 원본 바이트</param>
    /// <returns>소문자 포맷 이름 ('docx', 'pdf', 'excel' 등). 감지 실패 시 빈 문자열</returns>
    class function  DetectFormat(const AData: TBytes): string; static;

    /// <summary>DLL 이 로드 가능한 상태인지 확인합니다. 예외를 던지지 않습니다.</summary>
    /// <returns>DLL 로드와 ABI 확인에 성공하면 True</returns>
    class function  IsAvailable: Boolean; static;

    /// <summary>
    ///   메모리에 올린 문서를 GitHub Flavored Markdown 으로 변환합니다.
    ///   포맷은 내용 감지를 먼저 시도하고, 실패하면 <paramref name="AFormatHint"/> 로 폴백합니다.
    ///   시그니처가 없는 CSV 는 힌트를 반드시 지정해야 합니다.
    /// </summary>
    /// <param name="AData">문서 원본 바이트. 비어 있으면 예외가 발생합니다.</param>
    /// <param name="AFormatHint">확장자 힌트 ('docx', '.pdf', 'csv' 등). 점은 있어도 없어도 됩니다.</param>
    /// <returns>변환된 마크다운 문자열</returns>
    /// <exception cref="EAnydocError">포맷 미지원·손상·암호화·리소스 한계 등 변환 실패 시 발생</exception>
    class function  ToMarkdown(const AData: TBytes; const AFormatHint: string = ''): string; static;

    /// <summary>
    ///   파일을 읽어 마크다운으로 변환합니다. 파일 읽기는 델파이 쪽에서 수행하고
    ///   DLL 에는 바이트만 넘기므로, 유니코드 경로에서도 안전합니다.
    ///   확장자는 포맷 힌트로 자동 사용됩니다.
    /// </summary>
    /// <param name="AFileName">변환할 문서 경로</param>
    /// <returns>변환된 마크다운 문자열</returns>
    /// <exception cref="EAnydocError">변환 실패 시 발생</exception>
    /// <exception cref="EFileNotFoundException">파일이 없는 경우 발생</exception>
    class function  ToMarkdownFile(const AFileName: string): string; static;

    /// <summary>래퍼 DLL(sc_anydoc) 자체의 버전을 반환합니다.</summary>
    /// <returns>래퍼 버전 문자열</returns>
    class function  WrapperVersion: string; static;
  end;

implementation

{$REGION 'uses'}
uses
  System.IOUtils;
{$ENDREGION}

const
  // 32/64 동일명. 32비트는 dll\win32 폴더로 분리 배포하므로 충돌하지 않는다.
  SC_ANYDOC_DLL = 'sc_anydoc.dll';

  // 이 유닛이 기대하는 ABI 버전
  SC_ANYDOC_EXPECTED_ABI = 1;

// extern "C" = cdecl. Win32 에서도 export 이름에 데코레이션이 붙지 않는다.
// delayed 로 선언해 DLL 이 없어도 프로그램 시작은 되고, 첫 호출 시점에 실패한다.
//
// delayed 는 Windows 전용 지시어라 W1002 가 뜬다. 이 유닛 자체가 Windows 전용이므로
// 아래 선언 구간에서만 국소적으로 끄고 곧바로 되돌린다 (전역 억제 아님).
{$WARN SYMBOL_PLATFORM OFF}
function anydoc_abi_version: Cardinal; cdecl;
  external SC_ANYDOC_DLL delayed;
function anydoc_core_version: PAnsiChar; cdecl;
  external SC_ANYDOC_DLL delayed;
function anydoc_wrapper_version: PAnsiChar; cdecl;
  external SC_ANYDOC_DLL delayed;
function anydoc_detect_format(AData: PByte; ALen: NativeUInt;
  out AName: PAnsiChar; out ANameLen: NativeUInt): Integer; cdecl;
  external SC_ANYDOC_DLL delayed;
function anydoc_to_markdown(AData: PByte; ALen: NativeUInt; AFormatHint: PAnsiChar;
  out AText: PAnsiChar; out ATextLen: NativeUInt;
  out AError: PAnsiChar; out AErrorLen: NativeUInt): Integer; cdecl;
  external SC_ANYDOC_DLL delayed;
procedure anydoc_free(AText: PAnsiChar; ALen: NativeUInt); cdecl;
  external SC_ANYDOC_DLL delayed;
{$WARN SYMBOL_PLATFORM ON}

// 널 종단 정적 문자열(버전) 전용. 해제하지 않는다.
function StaticPtrToString(const AText: PAnsiChar): string;
begin
  if AText = nil then
  begin
    Result := '';
    Exit;
  end;

  var LLen := 0;
  while AText[LLen] <> #0 do
  begin
    Inc(LLen);
  end;

  Result := TSCAnydoc.BytesToString(AText, NativeUInt(LLen));
end;

{$REGION 'TAnydocStatusHelper'}
function TAnydocStatusHelper.ToString: string;
begin
  case Self of
    asOk:
      Result := '성공';
    asUnsupported:
      Result := '지원하지 않는 포맷';
    asMalformed:
      Result := '손상된 문서';
    asEncrypted:
      Result := '암호화된 문서';
    asResourceLimit:
      Result := '리소스 한계 초과';
    asMissingPart:
      Result := '필수 구성요소 누락';
    asIo:
      Result := '입출력 오류';
    asInvalidArg:
      Result := '잘못된 인자';
    asPanic:
      Result := '변환 엔진 내부 오류';
  else
    Result := '알 수 없는 오류';
  end;
end;
{$ENDREGION}

{$REGION 'EAnydocError'}
constructor EAnydocError.Create(const AStatus: TAnydocStatus; const ADetail: string);
begin
  inherited Create(Format('문서 변환 실패 - %s: %s', [AStatus.ToString, ADetail]));

  FDetail := ADetail;
  FStatus := AStatus;
end;
{$ENDREGION}

{$REGION 'TSCAnydoc'}
class function TSCAnydoc.AbiVersion: Cardinal;
begin
  Result := anydoc_abi_version;
end;

class function TSCAnydoc.BytesToString(const AText: PAnsiChar; const ALen: NativeUInt): string;
begin
  if (AText = nil) or (ALen = 0) then
  begin
    Result := '';
    Exit;
  end;

  // DLL 이 돌려주는 문자열은 항상 UTF-8 이다.
  var LBytes: TBytes;
  SetLength(LBytes, ALen);
  Move(AText^, LBytes[0], ALen);

  Result := TEncoding.UTF8.GetString(LBytes);
end;

class function TSCAnydoc.CoreVersion: string;
begin
  Result := StaticPtrToString(anydoc_core_version);
end;

class function TSCAnydoc.DetectFormat(const AData: TBytes): string;
begin
  if Length(AData) = 0 then
  begin
    Result := '';
    Exit;
  end;

  var LName: PAnsiChar := nil;
  var LNameLen: NativeUInt := 0;
  var LCode := anydoc_detect_format(PByte(AData), Length(AData), LName, LNameLen);

  try
    if LCode = 0 then
    begin
      Result := BytesToString(LName, LNameLen);
    end
    else
    begin
      // 감지 실패는 오류가 아니라 '모름' 이다 (CSV 등 시그니처 없는 포맷).
      Result := '';
    end;
  finally
    anydoc_free(LName, LNameLen);
  end;
end;

class function TSCAnydoc.IsAvailable: Boolean;
begin
  try
    Result := anydoc_abi_version = SC_ANYDOC_EXPECTED_ABI;
  except
    // DLL 부재·비트수 불일치 등 로드 실패. 가용성 질의이므로 예외를 삼키고 False 를 준다.
    on E: Exception do
    begin
      Result := False;
    end;
  end;
end;

class procedure TSCAnydoc.RaiseIfFailed(const ACode: Integer; const AError: PAnsiChar;
  const AErrorLen: NativeUInt);
begin
  if ACode = 0 then
  begin
    Exit;
  end;

  var LStatus: TAnydocStatus;
  if (ACode >= Ord(Low(TAnydocStatus))) and (ACode <= Ord(asPanic)) then
  begin
    LStatus := TAnydocStatus(ACode);
  end
  else
  begin
    // 업스트림이 추가한, 이 래퍼가 아직 모르는 오류 (DLL 은 99 로 보낸다).
    LStatus := asUnknown;
  end;

  var LDetail := BytesToString(AError, AErrorLen);
  if LDetail = '' then
  begin
    LDetail := Format('status %d', [ACode]);
  end;

  raise EAnydocError.Create(LStatus, LDetail);
end;

class function TSCAnydoc.ToMarkdown(const AData: TBytes; const AFormatHint: string): string;
begin
  if Length(AData) = 0 then
  begin
    // Detail 은 로케일 독립적인 기술 정보이므로 코어 메시지와 같은 영문으로 맞춘다.
    raise EAnydocError.Create(asInvalidArg, 'empty input (0 bytes)');
  end;

  var LHint := UTF8Encode(AFormatHint);
  var LHintPtr: PAnsiChar := nil;
  if LHint <> '' then
  begin
    LHintPtr := PAnsiChar(LHint);
  end;

  var LText: PAnsiChar := nil;
  var LTextLen: NativeUInt := 0;
  var LError: PAnsiChar := nil;
  var LErrorLen: NativeUInt := 0;

  var LCode := anydoc_to_markdown(PByte(AData), Length(AData), LHintPtr,
    LText, LTextLen, LError, LErrorLen);

  try
    RaiseIfFailed(LCode, LError, LErrorLen);

    Result := BytesToString(LText, LTextLen);
  finally
    // 실패 시엔 LText 가, 성공 시엔 LError 가 nil 이다. anydoc_free 는 nil 을 무시한다.
    anydoc_free(LText, LTextLen);
    anydoc_free(LError, LErrorLen);
  end;
end;

class function TSCAnydoc.ToMarkdownFile(const AFileName: string): string;
begin
  if not TFile.Exists(AFileName) then
  begin
    raise EFileNotFoundException.CreateFmt('문서를 찾을 수 없습니다: %s', [AFileName]);
  end;

  // 파일 읽기를 델파이가 담당해 DLL 에 경로 문자열을 넘기지 않는다 → 유니코드 경로 안전.
  var LBytes := TFile.ReadAllBytes(AFileName);

  Result := ToMarkdown(LBytes, TPath.GetExtension(AFileName));
end;

class function TSCAnydoc.WrapperVersion: string;
begin
  Result := StaticPtrToString(anydoc_wrapper_version);
end;
{$ENDREGION}

end.
