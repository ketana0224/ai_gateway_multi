# Lab 7 — クリーンアップ

## ゴール

ハンズオンで作成したすべての Azure リソースを削除し、課金を停止する。

## 所要時間

約 10 分

## 事前条件

- Lab 1–6 で作成したリソース構成を把握している
- 削除して問題ないことを確認している

> :warning: **APIM Developer SKU** と **Container Apps (minReplicas=1)** は削除しない限り課金が継続します。必ず実施してください。

---

## 7-1. Container App（外部 SHGW）を停止 / 削除

一時的に課金を止めたいだけなら minReplicas=0 に、完全に消すなら 7-3 で RG ごと削除すると便利です。

### Portal 手順

#### 一時停止（課金 0 円だが設定は残る）

1. Azure Portal で `aca-shgw-<initials>` を開く
2. 左メニュー **アプリケーション > スケーリングとレプリカ** を選択
3. **最小レプリカ数 / 最大レプリカ数** を **0** に変更して **保存**

#### 完全削除

1. `aca-shgw-<initials>` リソース画面 → 上部の **削除** ボタン
2. リソース名を入力して確認 → **削除**

> :information_source: 7-3 で `rg-aigw-handson-<initials>` を RG ごと削除する場合は、この手順はスキップして構いません。

<details>
<summary>CLI で実行する場合（参考）</summary>

```pwsh
# 一時停止
az containerapp update -g rg-aigw-handson-<initials> -n aca-shgw-<initials> `
  --min-replicas 0 --max-replicas 0

# 完全削除
az containerapp delete -g rg-aigw-handson-<initials> -n aca-shgw-<initials> --yes
```

</details>

## 7-2. Azure 側 SHGW Gateway リソースの削除（任意）

Container App を消した時点で SHGW は切断されますが、APIM 側の Gateway リソースは残ります。

### Portal 手順

1. Azure Portal で `apim-aigw-<initials>` を開く
2. 左メニュー **デプロイとインフラストラクチャ > ゲートウェイ**
3. `gw-ext-tokyo-<initials>` の行を選択 → **削除**
4. 確認ダイアログで **ハイ**

> 7-3 で `rg-aigw-handson-<initials>` を RG ごと削除する場合は、この手順はスキップして構いません。

<details>
<summary>CLI で実行する場合（参考）</summary>

```pwsh
$apim = "apim-aigw-<initials>"
$rg   = "rg-aigw-handson-<initials>"
$gw   = "gw-ext-tokyo-<initials>"
$sub  = (az account show --query id -o tsv)

az rest --method delete `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/gateways/${gw}?api-version=2022-08-01"
```

</details>

## 7-3. Azure リソースグループを削除（推奨）

最も確実かつ簡単な方法です。

> :information_source: **Foundry AI Gateway preview を試した場合のみの事前作業**（Lab 3-1A は本ハンズオンでは省略されています）
>
> Lab 3-1A を参考実施して Basic v2 APIM を新規作成・Foundry リソースに紐付けた場合のみ、RG 削除の前に **Foundry portal の AI Gateway 紐付けを解除** することを推奨します:
>
> 1. Foundry portal → **操作 → 管理者 → AI Gateway** タブ
> 2. 作成した AI Gateway の行を選択 → 関連プロジェクト一覧で **ゲートウェイから削除**
> 3. AI Gateway 一覧で当該行のメニュー → **AI ゲートウェイの削除**
>
> その後で下記の RG 削除を実行すると、Foundry 紐付け Basic v2 APIM も一緒に消えます。紐付けを残したまま APIM を削除すると Foundry portal 側に **孤立した状態の AI Gateway 表示** が残ることがあります。

### Portal 手順

1. リソースグループ `rg-aigw-handson-<initials>` を開く
2. 上部の **リソース グループの削除** をクリック
3. リソース グループ名を入力して確認 → **削除**

> APIM Developer は削除に 15–30 分かかります。バックグラウンドで完了します。

<details>
<summary>CLI で実行する場合（参考）</summary>

```pwsh
az group delete -n rg-aigw-handson-<initials> --yes --no-wait
```

</details>

## 7-4. 削除確認

Azure Portal → **リソース グループ** 一覧で `rg-aigw-handson-<initials>` が表示されない（または "削除中" が消える）ことを確認します。

## チェックリスト

- [ ] Container App `aca-shgw-<initials>` を停止または削除
- [ ] （任意・Lab 3-1A 参考実施時のみ）Foundry portal の AI Gateway タブで作成した Basic v2 APIM の紐付けを解除
- [ ] Azure リソースグループ `rg-aigw-handson-<initials>` を削除

## お疲れさまでした

これで AI Gateway マルチクラウド ハンズオンは終了です。学んだ内容:

- **APIM (AI Gateway)** を 1 つの統合エンドポイントとして利用
- **複数ベンダー LLM（Azure Foundry の OpenAI + AWS Bedrock の Anthropic Claude）の APIM への一元登録**
- **Token Limit / Token Metric** などの AI Gateway ポリシー
- **外部コンテナ環境上の Self-hosted Gateway**（本番では AWS / GCP / オンプレに同じイメージをデプロイすれば同一の体験）
- **Application Insights + OpenTelemetry** による分散トレースと Workbook 可視化

実運用に進む際は以下を検討してください:

- コンテナイメージ `mcr.microsoft.com/azure-api-management/gateway` を AWS ECS Fargate / EKS / EC2 へそのままデプロイ
- **APIM SKU** を Premium に上げ、SLA / マルチリージョン / VNet 統合
- **Private Endpoint** で Functions / SHGW へのアクセスを閉域化
- **Azure AI Content Safety** や `llm-semantic-cache-store/lookup` の本格適用
- **Bicep / Terraform** による IaC 化と CI/CD（このリポジトリの `infra/` 配下に整備予定）
