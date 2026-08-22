# Slot Data Viewer

店舗ごとのスロット実績データを表示し、過去2日間のデータから翌日の候補台を分類するWebアプリです。

SupabaseのREST APIからデータを取得し、GitHub Pagesで公開できる静的サイトとして構成しています。

## 主な機能

- 店舗・日付・機種による絞り込み
- 台番号、BIG、REG、回転数、差枚、RANKの表示
- URLパラメータによる選択状態の保存
- 過去2日間から翌日予想を表示
- 予想の判定別集計
- 台番号・判定・ワースト順位による並べ替え
- 店舗ごとの島図表示
- スマートフォン用ミニ島図
- JavaScript・Vue・Reactの3種類の表示ページ

## ページ構成

| ファイル | 内容 |
|---|---|
| `index.html` | メインのJavaScript版。翌日予想・島図対応 |
| `vue.html` | Vue 3版 |
| `react.html` | React 18版 |
| `sql/create_predictions.sql` | 予想テーブル作成SQL |
| `sql/insert_predictions_for_source_day.sql` | 翌日予想データ作成SQL |

Vue版・React版はCDNからライブラリを読み込むため、ビルドせずに動作します。

## システム構成

```text
GitHub Pages
  └─ HTML / CSS / JavaScript
          ↓ REST API
      Supabase
          └─ PostgreSQL
```

ブラウザからSupabaseのREST APIを呼び出し、実績データと予想データを取得します。

## 使用技術

- HTML
- CSS
- JavaScript
- Vue 3
- React 18
- Supabase
- PostgreSQL
- GitHub Pages

## ローカルでの起動

リポジトリのルートでHTTPサーバーを起動します。

```bash
python -m http.server 8000
```

ブラウザで以下を開きます。

```text
http://127.0.0.1:8000/
```

## Supabaseテーブル

### 実績テーブル

実績データは`public.slot`から取得します。

主に以下の列を使用します。

```text
day
shopid
slotid
name
big
reg
count
medal
rank
```

### 予想テーブル

最初に以下のSQLをSupabase SQL Editorで実行します。

```text
sql/create_predictions.sql
```

`public.predictions`へ以下の情報を保存します。

```text
prediction_day
source_through_day
shopid
slotid
name
score
positive_probability
grade
reasons
model_version
created_at
updated_at
```

Web画面からは読み取りだけを許可し、予想データの書き込みはバッチ処理側から行う設計です。

## 翌日予想データの作成

以下のSQLをSupabase SQL Editorで実行します。

```text
sql/insert_predictions_for_source_day.sql
```

SQL先頭の`source_day`を、最新の実績日に変更します。

```sql
with params as (
  select date '2026-08-22' as source_day
)
```

この場合、次のデータが使用されます。

```text
前々日：2026-08-21
前日　：2026-08-22
予想日：2026-08-23
```

SQLはUPSERT形式のため、同じ予想日・店舗・台番号・モデルバージョンで再実行しても重複しません。

## 現在の予想対象

現在の予想ロジックは、マイジャグラーV専用です。

```sql
name ilike '%マイジャグラー%'
```

別機種を追加する場合は、機種ごとに以下の設定を分ける必要があります。

- BIG獲得枚数
- REG獲得枚数
- 50枚あたりの回転数
- 高設定傾向の判定値
- 不発判定
- モデルバージョン

## 予想判定

過去2日間の実績を、以下の4種類に分類します。

### 不発据え置き

前日のデータが以下を満たす台です。

```text
回転数が5,000以上
REG確率の分母が300以下
BIG確率の分母が300以上
```

画面では黄色で表示します。

### 上げ候補

過去2日とも以下を満たす台です。

```text
回転数が5,000以上
REG確率の分母が300より大きい
```

画面では赤色で表示します。

### スルー

過去2日のどちらかで、以下を満たす台です。

```text
回転数が5,000以上
REG確率の分母が300以下
```

画面では青色で表示します。

### 保留

上記の条件に該当しない台です。

回転数不足、履歴不足、条件の境界にある台などが含まれます。画面ではグレーで表示します。

## 推定差枚

現在の元データでは`medal`が取得できない場合があるため、BIG・REG・回転数から推定差枚を計算します。

```text
推定差枚
= BIG回数 × 240
+ REG回数 × 96
- 回転数 × 1.25
```

`1.25`は、50枚で40ゲーム回る想定から計算しています。

```text
50 ÷ 40 = 1.25枚/ゲーム
```

これは実際の差枚ではなく、小役などの誤差を含む推定値です。

## ワースト順位

前日と前々日の推定差枚を合計します。

```text
2日合計推定差枚
= 前々日推定差枚
+ 前日推定差枚
```

2日合計推定差枚が少ない台から、店舗内のワースト順位を付けます。

予想一覧は以下の項目で並べ替えできます。

- 台番号
- 判定
- ワースト順位

初期表示は台番号順です。

## 島図

現在、以下の店舗に対応しています。

### テキサス八木

```text
上段：25 → 38
下段：82 → 69
```

上下2面の間に通路を表示します。

### ZAPP高陽

```text
183 → 192
```

横一列で表示します。

島図では予想判定を色分けします。

| 色 | 判定 |
|---|---|
| 赤 | 上げ候補 |
| 黄色 | 不発据え置き |
| 青 | スルー |
| グレー | 保留 |
| 金色の枠 | ワースト10位以内 |

通常の詳細島図に加えて、スマートフォンでも全台を一度に確認できるミニ島図を表示します。

## 店舗・島図の追加

店舗ごとの島配置は`index.html`内の`layouts`へ追加します。

例：

```javascript
'ZAPP高陽': {
  title: 'ZAPP高陽 マイジャグラー島',
  top: Array.from(
    { length: 10 },
    (_, index) => 183 + index
  ),
  bottom: null
}
```

両面の島では`bottom`を指定し、一列の場合は`null`にします。

## URLパラメータ

店舗・日付・機種の選択状態はURLへ保存されます。

```text
?shop=ZAPP高陽&day=2026-08-22
```

URLを共有すると、同じ条件を復元できます。

## セキュリティ

SupabaseのPublishable Keyは、ブラウザから使用する公開用キーです。

データへのアクセス制御は、キーを隠すことではなくSupabaseのRLS（Row Level Security）で行います。

- 実績・予想データ：必要なSELECTのみ許可
- INSERT・UPDATE・DELETE：匿名ユーザーには許可しない
- Service Role Key：ブラウザへ配置しない

## デプロイ

`main`ブランチへpushすると、GitHub Pagesへ反映されます。

```bash
git add .
git commit -m "Update slot viewer"
git push origin main
```

反映には通常1～3分程度かかります。

## 注意事項

このサイトの予想は、過去データを一定のルールで分類した参考情報です。

実際の設定や翌日の結果を保証するものではありません。推定差枚にも、小役回数や実際の投入枚数による誤差が含まれます。
