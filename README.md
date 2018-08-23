# 7ZipArchiveDsc


----
## 実装作業の流れ
実装はWIP Pull Requestフローで進めることとします
https://qiita.com/numa08/items/b676e38e3dbabfd39d18

- このリポジトリの`master`ブランチをローカルにクローンします
```
git clone xxxx
```

- 作業用にトピックブランチ`dev`を切ります
```
git checkout -b dev
```

- 空のコミットを作ります  
この空コミットは実装作業開始後すみやかに消してください
```
git commit --allow-empty -m '[WIP]First commit'
```

- リモートにプッシュします
```
git push origin dev
```

- Pull Requestを作ります
  + タイトルに`[WIP]`をつけてください
  + ↓のほうにあるTask listをコピペしてタスクリストを作ってください

- `dev`ブランチ上で実装作業を進めます
  + 適度な粒度でコミットすることを心がけてください

- 実装・テスト・レビューが完了したら`master`ブランチにマージします

### Task List
- [ ] x7ZipArchiveリソースの実装  
- [ ] ドキュメンテーション整備 in README.md  
- [ ] テストコード整備・追加（必要に応じて）  
    ヘルパ関数などを追加した場合は必ずテストコードも追加すること  
- [ ] 単体テスト通過確認  
- [ ] 統合テスト通過確認  
- [ ] テスト自動化実装  
    VSTSのYAML Buildで実装すること  
    https://docs.microsoft.com/en-us/vsts/pipelines/build/yaml?view=vsts


----
## テスト実行

```PowerShell
#テストモジュールのインストール
Install-Module Pester -Force -SkipPublisherCheck -MinimumVersion '4.2.0'
#テスト実行
Invoke-Pester
```


----
## ライセンス
7ZipArchiveDscモジュールは7-Zipライブラリを使用しています

+ [7-Zip](https://www.7-zip.org/)
    - Copyright (C) Igor Pavlov.
    - Licensed under the **GNU LGPL** and **BSD 3-clause License**.
