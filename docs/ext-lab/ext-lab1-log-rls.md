# Ext-Lab 1 — Log Analytics きめ細かい RBAC（行レベルアクセス制御）

## ゴール

本 Lab では、Azure ABAC（属性ベースのアクセス制御）条件を Log Analytics ワークスペースのロール割り当てに付与し、  
**SHGW 経由リクエストの行（`AppRoleName` = `apim-aigw-<id> aws-ap-northeast-1`）のみを参照できるユーザー** を作成して検証します。

| 検証項目 | 内容 |
|---|---|
| テーブルレベル | `AppRequests` テーブルのみアクセス許可、`AppDependencies` は拒否 |
| 行レベル | `AppRoleName` 列の値で **SHGW 行のみ**表示（cloud APIM 行は非表示） |
| 監査 | `LAQueryLogs.ConditionalDataAccess` で ABAC 条件の適用を確認 |

### 本 Lab の検証シナリオ

```
log-aigw-<id> ワークスペース
 └ AppRequests テーブル
     ├ AppRoleName = "apim-aigw-<id>"          ← cloud APIM 行 (非表示)
     └ AppRoleName = "apim-aigw-<id> <gwName>" ← SHGW 行     (表示)
```

- **講師アカウント（Owner）**: AppRequests の全行 + AppDependencies も参照可
- **テストユーザー（制限あり）**: AppRequests の SHGW 行のみ参照可

---

## 前提条件

- Lab 5（SHGW 構築）・Lab 6（テレメトリ確認）が完了していること
- `AppRequests` テーブルに cloud APIM 行と SHGW 行の両方が存在すること  
  （Lab 6 §6-3 の KQL `AppRequests | summarize count() by AppRoleName` で確認済み）
- Azure Portal でユーザー作成・ロール割り当てができる権限  
  （**ユーザー管理者** + **ロールベースのアクセス制御管理者** または **ユーザー アクセス管理者**）
- `<id>` は各自の受講者番号（例: `user99`）に読み替えてください

---

## EL1-1. ワークスペースのアクセス制御モード確認

ABAC 条件が有効に機能するために、ワークスペースのアクセス制御モードが  
**「ワークスペースのアクセス許可が必要」** になっている必要があります。

「リソースまたはワークスペースのアクセス許可を使用する」設定では、  
リソースレベルの読み取り権限が ABAC 条件を上書きするため、行レベルフィルタが機能しません。

1. Azure Portal → `log-aigw-<id>` (Log Analytics ワークスペース) を開く
2. 左サイドバー → **設定** → **プロパティ** をクリック
3. **アクセス制御モード** を確認する

| プロパティ画面の表示 | 意味 | 対応 |
|---|---|---|
| `ワークスペースのアクセス許可が必要 (クリックして変更)` | 既に正しい状態 | そのまま進む ✅ |
| `リソースまたはワークスペースのアクセス許可を使用 (クリックして変更)` | 変更が必要 | 下記手順で変更する |

> **ℹ️ 補足**: 「(クリックして変更)」はどちらの状態でも表示されます。  
> 現在の値がリンクとして表示されており、クリックすると切り替えパネルが開きます。

**変更手順（必要な場合のみ）**:
1. `リソースまたはワークスペースのアクセス許可を使用 (クリックして変更)` のリンクをクリックすると、即座に切り替わる

> **⚠️ 注意**: この変更は、リソースコンテキスト（例: VM の診断ログ）でワークスペースにアクセスしているユーザーの権限に影響します。  
> 本ハンズオン環境以外で変更する場合は事前に影響範囲を確認してください。

**確認 KQL**（変更後 1-2 分で有効）:

```kql
// ワークスペース全体のアクセス統計（講師アカウントで実行）
AppRequests
| summarize count() by AppRoleName
| order by count_ desc
```

> **ℹ️ 情報**: cloud APIM（`apim-aigw-<id>`）と SHGW（`apim-aigw-<id> <gwName>`）両方の行が  
> 確認できていれば前提データは揃っています。

---

## EL1-2. テストユーザーの作成

ABAC 条件の検証のために、専用のテストユーザーを作成します。

1. **Azure Portal** → **Microsoft Entra ID** → **ユーザー** を開く
2. **＋ 新しいユーザー** → **新しいユーザーの作成** をクリック

   | 項目 | 値 |
   |---|---|
   | ユーザー プリンシパル名 | `rls-test@<yourtenantdomain>` |
   | 表示名 | `RLS Test User` |
   | パスワード | （自動生成をコピーしておく） |

3. **確認と作成** → **作成** をクリック

**または PowerShell（Azure Cloud Shell）でも作成可能**:

```powershell
$domain = (az ad signed-in-user show --query 'userPrincipalName' -o tsv).Split('@')[1]
az ad user create `
  --display-name "RLS Test User" `
  --user-principal-name "rls-test@$domain" `
  --password "Test@1234567" `
  --force-change-password-next-sign-in false
```

---

## EL1-3. カスタムロールの作成

Log Analytics のきめ細かい RBAC には、以下の 2 種類のアクションを持つロールが必要です。

| アクション種別 | アクション名 | 用途 |
|---|---|---|
| Action | `Microsoft.OperationalInsights/workspaces/read` | ワークスペースのポータル表示 |
| Action | `Microsoft.OperationalInsights/workspaces/query/read` | KQL クエリ実行 |
| Action | `Microsoft.Resources/subscriptions/resources/read` | ポータルナビゲーション（リソース一覧取得） |
| Action | `Microsoft.Resources/subscriptions/resourceGroups/read` | ポータルナビゲーション（RG 表示） |
| DataAction | `Microsoft.OperationalInsights/workspaces/tables/data/read` | テーブルデータ読み取り（ABAC 条件適用先） |

### ポータルでカスタムロールを作成する

1. Azure Portal → リソースグループ `rg-aigw-handson-<id>` → **アクセス制御 (IAM)**
2. **＋ 追加** → **カスタム ロールの追加** をクリック
3. **最初から始める** を選択し、以下を入力:

   | 項目 | 値 |
   |---|---|
   | カスタム ロール名 | `Log Analytics SHGW Viewer` |
   | 説明 | `AppRequests の SHGW 行のみ参照可（ABAC 条件付き）` |
   | ベース アクセス許可 | 最初から始める |

4. **アクセス許可** タブ → **アクセス許可の追加** → 以下を追加:
   - `Microsoft.OperationalInsights/workspaces/read`（Actions）
   - `Microsoft.OperationalInsights/workspaces/query/read`（Actions）
   - `Microsoft.Resources/subscriptions/resources/read`（Actions）
   - `Microsoft.Resources/subscriptions/resourceGroups/read`（Actions）
   - `Microsoft.OperationalInsights/workspaces/tables/data/read`（DataActions）
5. **割り当て可能なスコープ** タブ → **＋ スコープの追加** をクリックし、サブスクリプションを選択（RG のみではサブスクリプションレベルのナビゲーションに使えないため）
6. **確認と作成** → **作成**

> **ℹ️ ロール作成は 2-3 分かかります。** 次の手順に進む前に少し待ってください。

---

## EL1-4. 条件付きロール割り当て

作成したカスタムロールを、ABAC 条件付きでテストユーザーに割り当てます。

### ロール割り当て手順

1. Azure Portal → **サブスクリプション** → **アクセス制御 (IAM)**
2. **＋ ロールの割り当ての追加** をクリック
3. **ロール** タブ: `Log Analytics SHGW Viewer` を検索して選択 → **次へ**
4. **メンバー** タブ: `rls-test@<yourtenantdomain>` を選択 → **次へ**
5. **条件** タブ → **条件を追加する** をクリック

### ABAC 条件の設定

画面タイトルが **「ロールの割り当て条件を追加する」** になっていることを確認します。  
**エディターの種類** は **「ビジュアル」** を選択してください。

#### 1. アクションを追加します

6. **「操作の選択」** リンクをクリック
7. 右パネルで **「Read workspace data」** にチェックを入れる → **選択**
8. アクションの一覧に `Microsoft.OperationalInsights/workspaces/tables/data/read`（データ アクション）が表示されることを確認

#### 2. 式を作成します（テーブル名の制限）

9. **「＋ 式の追加」** をクリック
10. 以下の値を設定:

    | 項目 | 値 |
    |---|---|
    | 属性ソース | **リソース** |
    | 属性 | **テーブル名** |
    | 演算子 | **StringEquals** |
    | 値または属性 | **値**（ラジオボタン「● 値 ○ 属性」→「値」を選択） |
    | 値 | `AppRequests` |

#### 2. 式を作成します（AppRoleName の制限）

11. **「＋ 式の追加」** をクリック
12. 以下の値を設定:

    | 項目 | 値 |
    |---|---|
    | 属性ソース | **リソース** |
    | 属性 | **列の値 (キーは列名)** |
    | キー | `AppRoleName` |
    | 演算子 | **StringEquals** |
    | 値 | `apim-aigw-<id> <gwName>`（Lab 6 §6-3 で確認した SHGW の AppRoleName） |

    > **ℹ️ 例**: `apim-aigw-user99 aws-ap-northeast-1`  
    > Lab 6 §6-3 の KQL `AppRequests | summarize count() by AppRoleName` で確認した値を使用してください。

#### 式をグループ化（AND 条件）

13. 式 #1 と式 #2 の間に **「● AND ○ OR」** が表示されていることを確認（デフォルトは AND）
14. 式 #1 と式 #2 の左端チェックボックスを両方オン → ツールバーの **「グループ化」** をクリック

#### 確認（コードで検証）

15. **エディターの種類** を **「コード」** に切り替えて、以下の条件式になっていることを確認:

```
(
  (
    !(ActionMatches{'Microsoft.OperationalInsights/workspaces/tables/data/read'})
  )
  OR
  (
    @Resource[Microsoft.OperationalInsights/workspaces/tables:name] StringEquals 'AppRequests'
    AND
    @Resource[Microsoft.OperationalInsights/workspaces/tables/record:AppRoleName<$key_case_sensitive$>] StringEquals 'apim-aigw-<id> aws-ap-northeast-1'
  )
)
```

16. **「保存」** をクリック（条件が確定し、ロール割り当てウィザードに戻る）
17. **「レビューと割り当て」** をクリック

> **⚠️ 加算式モデルに注意**: テストユーザーに同スコープ以上で `Log Analytics 閲覧者` や `閲覧者` などのロールが  
> 既に割り当てられていると、ABAC 条件が無効化されます。既存の広範なロール割り当てを先に削除してください。

> **⏳ 有効化まで最大 15 分かかります。** 次の手順に進む前に少し待ってください。

---

## EL1-5. テストユーザーで KQL 検証

テストユーザーとしてログインし、ABAC 条件が正しく機能していることを確認します。

### ログイン手順

1. InPrivate/シークレットウィンドウを開く
2. `https://portal.azure.com` へアクセス
3. `rls-test@<yourtenantdomain>` でサインイン
4. 上部検索バー（`G+/`）に `log-aigw-<id>` と入力 → Log Analytics ワークスペースをクリック
5. 左メニュー → **ログ** を開く
6. 以下の KQL を順に実行して結果を確認する

### 検証 1: AppRequests の全件確認

```kql
// 結果: SHGW 行のみ表示されるはず（cloud APIM 行は見えない）
AppRequests
| project TimeGenerated, AppRoleName, Name, ResultCode
| order by TimeGenerated desc
| take 20
```

**期待される結果**:

| AppRoleName | 表示 |
|---|---|
| `apim-aigw-<id>` | ❌ 0 件（非表示） |
| `apim-aigw-<id> <gwName>` | ✅ 表示される |

---

### 検証 2: AppDependencies へのアクセス試行

```kql
// 結果: エラーまたは 0 件になるはず（テーブルアクセス不可）
AppDependencies
| take 5
```

**期待される結果**: `0 行` または アクセス拒否エラー

---

### 検証 3: AppRoleName で集計

```kql
// SHGW の AppRoleName のみが集計される
AppRequests
| summarize count() by AppRoleName
```

**期待される結果**:

```
AppRoleName                          count_
-----------------------------------------
apim-aigw-<id> aws-ap-northeast-1   XX
```

cloud APIM の `apim-aigw-<id>` は集計結果に表れないことを確認します。

---

## EL1-6. LAQueryLogs で ABAC 適用を監査

**講師アカウントに戻り**、`LAQueryLogs` テーブルでテストユーザーが実行した KQL に  
ABAC 条件が適用されたかどうかを確認します。

> **ℹ️ 前提**: `LAQueryLogs` の収集を有効にするには、ワークスペースの **診断設定** で  
> `LAQueryLogs` カテゴリを有効にする必要があります。未設定の場合は下記「診断設定の確認」を先に実施してください。

### 診断設定の確認と有効化

1. `log-aigw-<id>` → **監視** → **診断設定** を開く
2. `LAQueryLogs` カテゴリが含まれていない場合:
   - **診断設定の追加** をクリック
   - カテゴリ `Audit` または `LAQueryLogs` を選択
   - 宛先: `log-aigw-<id>` 自身を選択（ワークスペースへ送信）
   - **保存**

### 監査 KQL

```kql
// テストユーザーが実行したクエリに ABAC 条件が適用されたか確認
LAQueryLogs
| where TimeGenerated > ago(1h)
| where AADEmail contains "rls-test"
| project TimeGenerated, AADEmail, QueryText, ConditionalDataAccess, ResponseCode
| order by TimeGenerated desc
```

**`ConditionalDataAccess` 列の値の意味**:

| 値 | 意味 |
|---|---|
| `true` | ABAC 条件が適用された（正常） |
| `false` | ABAC 条件が適用されなかった（上位ロールが存在する可能性） |
| `null` | 条件が設定されていない通常クエリ |

> **ℹ️ `ConditionalDataAccess = true` が確認できれば ABAC が正常に機能しています。**

---

## EL1-7. （参考）CLI で条件付きロール割り当てを行う方法

ポータル GUI の代わりに Azure CLI でロール割り当て + 条件を設定する場合の参考コマンドです。

```powershell
# 環境変数を設定
$SUB_ID    = (az account show --query id -o tsv)
$SCOPE     = "/subscriptions/$SUB_ID/resourceGroups/rg-aigw-handson-<id>/providers/Microsoft.OperationalInsights/workspaces/log-aigw-<id>"
$ROLE_NAME = "Log Analytics SHGW Viewer"
$USER_UPN  = "rls-test@<yourtenantdomain>"
$USER_ID   = (az ad user show --id $USER_UPN --query id -o tsv)
$ROLE_ID   = (az role definition list --name $ROLE_NAME --query "[0].name" -o tsv)

# ABAC 条件文字列（ファイルに書き出し）
$CONDITION = @"
(
  (
    !(ActionMatches{'Microsoft.OperationalInsights/workspaces/tables/data/read'})
  )
  OR
  (
    @Resource[Microsoft.OperationalInsights/workspaces/tables:name] StringEquals 'AppRequests'
    AND
    @Resource[Microsoft.OperationalInsights/workspaces/tables/record:AppRoleName<`$key_case_sensitive`$>] StringEquals 'apim-aigw-<id> aws-ap-northeast-1'
  )
)
"@

# ロール割り当て（ABAC 条件付き）
az role assignment create `
  --assignee-object-id $USER_ID `
  --assignee-principal-type User `
  --role $ROLE_ID `
  --scope $SCOPE `
  --condition $CONDITION `
  --condition-version "2.0"
```

> **⚠️ CLI での条件文字列は大文字小文字・スペースが厳格です。**  
> エラーが発生した場合はポータルの「コードの編集」でエクスポートした条件文字列を使用してください。

---

## EL1-8. クリーンアップ

検証が完了したら、テストリソースを削除してください。

```powershell
# テストユーザーの削除
$USER_UPN = "rls-test@<yourtenantdomain>"
az ad user delete --id $USER_UPN
Write-Host "テストユーザー削除完了"

# ロール割り当てを確認（必要なら手動で削除）
az role assignment list --scope "/subscriptions/$(az account show --query id -o tsv)" `
  --query "[?principalName=='$USER_UPN']" -o table
```

または Azure Portal → `log-aigw-<id>` → **アクセス制御 (IAM)** → ロールの割り当てタブ → `rls-test` を検索して削除。

---

## トラブルシューティング

### テストユーザーにデータが全件表示されてしまう

| 確認事項 | 対処 |
|---|---|
| テストユーザーに上位ロール（閲覧者、Log Analytics 閲覧者など）が割り当てられていないか | IAM でロール割り当て一覧を確認し、上位ロールを削除 |
| ワークスペースのアクセス制御モードが「リソースまたはワークスペース」になっていないか | EL1-1 の手順でモードを変更 |
| ロール割り当て変更が反映されていない（最大 15 分） | 少し待ってからブラウザをリロード |

### `AppRequests` にデータが何も表示されない（0 件）

- ABAC 条件の `AppRoleName` の値が実際のデータと一致しているか確認  
  → Lab 6 §6-3 の KQL で現在の AppRoleName 値を再確認する
- テーブル名・列名の大文字小文字が正確か確認（**大文字小文字区別あり**）

### `ConditionalDataAccess` 列が null / false

- `LAQueryLogs` 診断設定が有効になっているか確認（EL1-6 を参照）
- テストユーザーに上位ロールが残っている可能性（加算式モデル）

---

## チェックリスト

- [ ] ワークスペースのアクセス制御モードが「ワークスペースのアクセス許可を要求する」であることを確認
- [ ] テストユーザー `rls-test@<domain>` を作成
- [ ] カスタムロール `Log Analytics SHGW Viewer` を作成（DataAction 含む）
- [ ] テストユーザーに ABAC 条件付きロール割り当てを実施
  - テーブル名: `AppRequests`
  - 列値: `AppRoleName = apim-aigw-<id> <gwName>`
- [ ] テストユーザーで KQL を実行:
  - [ ] `AppRequests` → SHGW 行のみ表示、cloud APIM 行は非表示
  - [ ] `AppDependencies` → 0 件 / エラー
- [ ] `LAQueryLogs.ConditionalDataAccess = true` を確認
- [ ] テストユーザー・ロール割り当てをクリーンアップ

---

## 参考リンク

- [Azure Monitor でのきめ細かい RBAC（概念）](https://learn.microsoft.com/ja-jp/azure/azure-monitor/logs/granular-rbac-log-analytics)
- [Azure Monitor でのきめ細かい RBAC の構成（ユースケース）](https://learn.microsoft.com/ja-jp/azure/azure-monitor/logs/granular-rbac-use-case)
- [ABAC 条件の追加または編集（REST API）](https://learn.microsoft.com/ja-jp/azure/role-based-access-control/conditions-role-assignments-rest)
- [LAQueryLogs テーブルリファレンス](https://learn.microsoft.com/ja-jp/azure/azure-monitor/reference/tables/laquerylogs)
