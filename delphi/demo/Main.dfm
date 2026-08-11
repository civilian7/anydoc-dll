object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'anydoc Demo - Convert documents to Markdown'
  ClientHeight = 601
  ClientWidth = 904
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 904
    Height = 49
    Align = alTop
    BevelOuter = bvNone
    Padding.Left = 12
    Padding.Top = 10
    Padding.Right = 12
    Padding.Bottom = 10
    TabOrder = 0
    object lblFile: TLabel
      Left = 436
      Top = 17
      Width = 226
      Height = 15
      Caption = '(or drop a document onto this window)'
    end
    object btnOpen: TButton
      Left = 12
      Top = 10
      Width = 140
      Height = 29
      Caption = 'Open Document...'
      TabOrder = 0
      OnClick = btnOpenClick
    end
    object btnSave: TButton
      Left = 160
      Top = 10
      Width = 140
      Height = 29
      Caption = 'Save Markdown...'
      Enabled = False
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object chkUtf8Bom: TCheckBox
      Left = 312
      Top = 16
      Width = 110
      Height = 17
      Hint = 'Write a UTF-8 byte order mark (EF BB BF) at the start of the file'
      Caption = 'UTF-8 BOM'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 2
    end
  end
  object pgcMain: TPageControl
    Left = 0
    Top = 49
    Width = 904
    Height = 533
    ActivePage = tabSource
    Align = alClient
    TabOrder = 1
    OnChange = pgcMainChange
    object tabSource: TTabSheet
      Caption = 'Source'
      object memMarkdown: TMemo
        Left = 0
        Top = 0
        Width = 896
        Height = 503
        Align = alClient
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -13
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        ScrollBars = ssBoth
        TabOrder = 0
        WordWrap = False
        OnChange = memMarkdownChange
      end
    end
    object tabPreview: TTabSheet
      Caption = 'Preview'
      ImageIndex = 1
      object lblPreviewNotice: TLabel
        Left = 0
        Top = 0
        Width = 896
        Height = 45
        Align = alTop
        Alignment = taCenter
        AutoSize = False
        Caption = 'Preview is unavailable.'
        Layout = tlCenter
        Visible = False
        WordWrap = True
        ExplicitWidth = 116
      end
      object edgePreview: TEdgeBrowser
        Left = 0
        Top = 0
        Width = 896
        Height = 503
        Align = alClient
        TabOrder = 0
      end
    end
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 582
    Width = 904
    Height = 19
    Panels = <
      item
        Width = 380
      end
      item
        Width = 190
      end
      item
        Width = 90
      end
      item
        Width = 200
      end>
  end
  object dlgOpen: TOpenDialog
    Options = [ofHideReadOnly, ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Select a document to convert'
    Left = 620
    Top = 100
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'md'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofPathMustExist, ofEnableSizing]
    Title = 'Save Markdown'
    Left = 620
    Top = 168
  end
end
