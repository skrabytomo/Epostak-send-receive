object FormMain: TFormMain
  Left = 150
  Top = 60
  Width = 950
  Height = 920
  Caption = 'Epostak SAPI-SK - InTime Integration'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13

  object Label1: TLabel
    Left = 10
    Top = 12
    Width = 49
    Height = 13
    Caption = 'Base URL'
  end
  object Label2: TLabel
    Left = 400
    Top = 12
    Width = 88
    Height = 13
    Caption = 'Moje Participant Id'
  end
  object Label3: TLabel
    Left = 10
    Top = 42
    Width = 35
    Height = 13
    Caption = 'ClientId'
  end
  object Label4: TLabel
    Left = 400
    Top = 42
    Width = 57
    Height = 13
    Caption = 'ClientSecret'
  end
  object edtBaseURL: TEdit
    Left = 60
    Top = 9
    Width = 330
    Height = 21
    TabOrder = 0
  end
  object edtParticipantId: TEdit
    Left = 495
    Top = 9
    Width = 200
    Height = 21
    TabOrder = 1
  end
  object edtClientId: TEdit
    Left = 60
    Top = 39
    Width = 330
    Height = 21
    TabOrder = 2
  end
  object edtClientSecret: TEdit
    Left = 495
    Top = 39
    Width = 380
    Height = 21
    TabOrder = 3
  end
  object btnSaveConfig: TButton
    Left = 10
    Top = 70
    Width = 100
    Height = 25
    Caption = 'Ulozit config'
    TabOrder = 4
    OnClick = btnSaveConfigClick
  end
  object btnUseFirmA: TButton
    Left = 120
    Top = 70
    Width = 130
    Height = 25
    Caption = 'Demo: Firma A (send)'
    TabOrder = 5
    OnClick = btnUseFirmAClick
  end
  object btnUseFirmB: TButton
    Left = 260
    Top = 70
    Width = 130
    Height = 25
    Caption = 'Demo: Firma B (recv)'
    TabOrder = 6
    OnClick = btnUseFirmBClick
  end
  object btnUseSandbox: TButton
    Left = 400
    Top = 70
    Width = 90
    Height = 25
    Caption = 'URL: Sandbox'
    TabOrder = 7
    OnClick = btnUseSandboxClick
  end
  object btnUseProduction: TButton
    Left = 500
    Top = 70
    Width = 100
    Height = 25
    Caption = 'URL: Produkcia'
    TabOrder = 8
    OnClick = btnUseProductionClick
  end

  object lblDBConn: TLabel
    Left = 10
    Top = 108
    Width = 200
    Height = 13
    Caption = 'InTime DB — 192.168.1.15  (auto-pripojena)'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object btnConnectDB: TButton
    Left = 780
    Top = 103
    Width = 100
    Height = 25
    Caption = 'Znovu pripojit'
    TabOrder = 9
    OnClick = btnConnectDBClick
  end

  object lblIDSpolLic: TLabel
    Left = 10
    Top = 140
    Width = 75
    Height = 13
    Caption = 'Spolocnost'
  end
  object cmbSpolLic: TComboBox
    Left = 90
    Top = 137
    Width = 400
    Height = 21
    Style = csDropDownList
    TabOrder = 10
  end
  object btnLoadInvoices: TButton
    Left = 500
    Top = 135
    Width = 160
    Height = 25
    Caption = 'Nacitaj faktury (FV)'
    TabOrder = 11
    OnClick = btnLoadInvoicesClick
  end

  object lvInvoices: TListView
    Left = 10
    Top = 170
    Width = 870
    Height = 180
    Columns = <>
    ReadOnly = True
    RowSelect = True
    TabOrder = 12
    ViewStyle = vsReport
    OnDblClick = btnLoadFromDBClick
  end

  object btnLoadFromDB: TButton
    Left = 10
    Top = 358
    Width = 200
    Height = 25
    Caption = 'Pripravit XML zo vybratej faktury'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 13
    OnClick = btnLoadFromDBClick
  end

  object Label5: TLabel
    Left = 10
    Top = 398
    Width = 184
    Height = 13
    Caption = 'XML subor (prazdne = pouzije sa DB XML)'
  end
  object edtXMLFile: TEdit
    Left = 10
    Top = 415
    Width = 600
    Height = 21
    TabOrder = 14
  end
  object btnBrowseXML: TButton
    Left = 618
    Top = 413
    Width = 100
    Height = 25
    Caption = 'Prehlad...'
    TabOrder = 15
    OnClick = btnBrowseXMLClick
  end
  object Label6: TLabel
    Left = 10
    Top = 450
    Width = 111
    Height = 13
    Caption = 'Prijemca (Participant Id)'
  end
  object edtReceiverId: TEdit
    Left = 150
    Top = 447
    Width = 250
    Height = 21
    TabOrder = 16
  end
  object btnSend: TButton
    Left = 618
    Top = 445
    Width = 100
    Height = 25
    Caption = 'ODOSLAT'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 17
    OnClick = btnSendClick
  end

  object Label7: TLabel
    Left = 10
    Top = 482
    Width = 26
    Height = 13
    Caption = 'Inbox'
  end
  object lvInbox: TListView
    Left = 10
    Top = 498
    Width = 870
    Height = 160
    Columns = <>
    MultiSelect = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 18
    ViewStyle = vsReport
  end
  object Label8: TLabel
    Left = 10
    Top = 668
    Width = 114
    Height = 13
    Caption = 'Priecinok na stahovanie'
  end
  object edtSaveFolder: TEdit
    Left = 130
    Top = 665
    Width = 420
    Height = 21
    TabOrder = 19
  end
  object btnBrowseFolder: TButton
    Left = 558
    Top = 663
    Width = 100
    Height = 25
    Caption = 'Prehlad...'
    TabOrder = 20
    OnClick = btnBrowseFolderClick
  end
  object btnCheckInbox: TButton
    Left = 10
    Top = 696
    Width = 130
    Height = 28
    Caption = 'Skontrolovat inbox'
    TabOrder = 21
    OnClick = btnCheckInboxClick
  end
  object btnDownloadSelected: TButton
    Left = 150
    Top = 696
    Width = 150
    Height = 28
    Caption = 'Stiahnut vybrany'
    TabOrder = 22
    OnClick = btnDownloadSelectedClick
  end
  object btnAcknowledgeSelected: TButton
    Left = 310
    Top = 696
    Width = 160
    Height = 28
    Caption = 'Potvrdit vsetky vybrate'
    TabOrder = 23
    OnClick = btnAcknowledgeSelectedClick
  end
  object memLog: TMemo
    Left = 10
    Top = 736
    Width = 870
    Height = 150
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 24
    WordWrap = False
  end
  object dlgOpenXML: TOpenDialog
    Left = 820
    Top = 10
  end
end
