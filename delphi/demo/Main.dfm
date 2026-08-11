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
      Left = 316
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
  end
  object memMarkdown: TMemo
    Left = 0
    Top = 49
    Width = 904
    Height = 533
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssBoth
    TabOrder = 1
    WordWrap = False
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
