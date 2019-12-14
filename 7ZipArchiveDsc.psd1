#
# モジュール '7ZipArchiveDsc' のモジュール マニフェスト
#
# 生成日: 2018/08/08
#

@{

    # このマニフェストに関連付けられているスクリプト モジュール ファイルまたはバイナリ モジュール ファイル。
    RootModule           = '7ZipArchiveDsc.psm1'

    # このモジュールのバージョン番号です。
    ModuleVersion        = '1.3.3'

    # サポートされている PSEditions
    # CompatiblePSEditions = @()

    # このモジュールを一意に識別するために使用される ID
    GUID                 = '9c9688ed-1172-4d5a-9c80-772e086edda6'

    # このモジュールの作成者
    Author               = 'mkht'

    # このモジュールの会社またはベンダー
    CompanyName          = ''

    # このモジュールの著作権情報
    Copyright            = '(c) 2019 mkht. All rights reserved.'

    # このモジュールの機能の説明
    Description          = 'PowerShell DSC Resource to expand an archive file to a specific path. '

    # このモジュールに必要な Windows PowerShell エンジンの最小バージョン
    PowerShellVersion    = '5.0'

    # このモジュールに必要な Windows PowerShell ホストの名前
    # PowerShellHostName = ''

    # このモジュールに必要な Windows PowerShell ホストの最小バージョン
    # PowerShellHostVersion = ''

    # このモジュールに必要な Microsoft .NET Framework の最小バージョン。 この前提条件は、PowerShell Desktop エディションについてのみ有効です。
    # DotNetFrameworkVersion = ''

    # このモジュールに必要な共通言語ランタイム (CLR) の最小バージョン。 この前提条件は、PowerShell Desktop エディションについてのみ有効です。
    # CLRVersion = ''

    # このモジュールに必要なプロセッサ アーキテクチャ (なし、X86、Amd64)
    # ProcessorArchitecture = ''

    # このモジュールをインポートする前にグローバル環境にインポートされている必要があるモジュール
    # RequiredModules = @()

    # このモジュールをインポートする前に読み込まれている必要があるアセンブリ
    # RequiredAssemblies = @()

    # このモジュールをインポートする前に呼び出し元の環境で実行されるスクリプト ファイル (.ps1)。
    # ScriptsToProcess = @()

    # このモジュールをインポートするときに読み込まれる型ファイル (.ps1xml)
    # TypesToProcess = @()

    # このモジュールをインポートするときに読み込まれる書式ファイル (.ps1xml)
    # FormatsToProcess = @()

    # RootModule/ModuleToProcess に指定されているモジュールの入れ子になったモジュールとしてインポートするモジュール
    # NestedModules = @()

    # このモジュールからエクスポートする関数です。最適なパフォーマンスを得るには、ワイルドカードを使用せず、エクスポートする関数がない場合は、エントリを削除しないで空の配列を使用してください。
    FunctionsToExport    = @(
        'Expand-7ZipArchive',
        'Compress-7ZipArchive'
    )

    # このモジュールからエクスポートするコマンドレットです。最適なパフォーマンスを得るには、ワイルドカードを使用せず、エクスポートするコマンドレットがない場合は、エントリを削除しないで空の配列を使用してください。
    CmdletsToExport      = @()

    # このモジュールからエクスポートする変数
    VariablesToExport    = '*'

    # このモジュールからエクスポートするエイリアスです。最適なパフォーマンスを得るには、ワイルドカードを使用せず、エクスポートするエイリアスがない場合は、エントリを削除しないで空の配列を使用してください。
    AliasesToExport      = @()

    # このモジュールからエクスポートする DSC リソース
    DscResourcesToExport = @('x7ZipArchive')

    # このモジュールに同梱されているすべてのモジュールのリスト
    # ModuleList = @()

    # このモジュールに同梱されているすべてのファイルのリスト
    # FileList = @()

    # RootModule/ModuleToProcess に指定されているモジュールに渡すプライベート データ。これには、PowerShell で使用される追加のモジュール メタデータを含む PSData ハッシュテーブルが含まれる場合もあります。
    PrivateData          = @{

        PSData = @{

            # このモジュールに適用されているタグ。オンライン ギャラリーでモジュールを検出する際に役立ちます。
            Tags       = @('DSC', 'ZIP', '7-Zip')

            # このモジュールのライセンスの URL。
            LicenseUri = 'https://github.com/mkht/7ZipArchiveDsc/blob/master/LICENSE'

            # このプロジェクトのメイン Web サイトの URL。
            ProjectUri = 'https://github.com/mkht/7ZipArchiveDsc'

            # このモジュールを表すアイコンの URL。
            # IconUri = ''

            # このモジュールの ReleaseNotes
            # ReleaseNotes = ''

        } # PSData ハッシュテーブル終了

    } # PrivateData ハッシュテーブル終了

    # このモジュールの HelpInfo URI
    # HelpInfoURI = ''

    # このモジュールからエクスポートされたコマンドの既定のプレフィックス。既定のプレフィックスをオーバーライドする場合は、Import-Module -Prefix を使用します。
    # DefaultCommandPrefix = ''

}

