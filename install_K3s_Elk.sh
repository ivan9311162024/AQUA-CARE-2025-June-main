#!/bin/bash
set -e  # 一旦遇到錯誤指令就終止腳本執行，避免後續錯誤連鎖發生

sudo systemctl disable unattended-upgrades  # 停用自動更新，避免在安裝過程中出現意外更新導致問題

bash tools/install_ansbile.sh  # 安裝 Ansible 與虛擬環境

# 啟用虛擬環境
source .venv/bin/activate

ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml  # 安裝 k3s

echo "✅ 已設定 KUBECONFIG 與 kubectl alias"
# 安裝完 K3s 後，複製 kubeconfig 並設定權限
mkdir -p ~/.k3s
sudo cp /etc/rancher/k3s/k3s.yaml ~/.k3s/config
sudo chown $USER:$USER ~/.k3s/config

# 永久設定（只寫一次進 .bashrc）
grep -q 'export KUBECONFIG=$HOME/.k3s/config' ~/.bashrc || echo 'export KUBECONFIG=$HOME/.k3s/config' >> ~/.bashrc

if [ ! -f "$HOME/.k3s/config" ]; then
  echo "❌ 找不到 $HOME/.k3s/config，請檢查 K3s 是否成功安裝"
  exit 1
fi

# 立即生效
export KUBECONFIG=$HOME/.k3s/config

source ~/.bashrc

# 等待所有 pod 都準備好（最多等 3 分鐘）
echo "⏳ 等待所有 Pod 進入 Ready 或 Completed 狀態..."

TIMEOUT=180  # 最多等待秒數
SLEEP=5      # 每次間隔
ELAPSED=0

while true; do
  NOT_READY=$(kubectl get pods -A | awk 'NR>1 && $4 != "Running" && $4 != "Completed"')
  
  if [ -z "$NOT_READY" ]; then
    echo "✅ 所有 Pod 都 Ready 或 Completed。"
    break
  fi

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "❌ 超過 $TIMEOUT 秒仍有未就緒的 Pod："
    echo "$NOT_READY"
    exit 1
  fi

  sleep "$SLEEP"
  ELAPSED=$((ELAPSED + SLEEP))
done



cd elk/

# 安裝 Elastic Stack 的 Helm Charts
helm search repo elastic
# 安裝 Elastic Stack 的 Helm Charts（每個安裝後等待 Ready 或 Completed）

# 函數：等待指定 label 的 pod Ready 或 Completed
wait_for_pod_ready() {
  local label="$1"
  local timeout=600
  local sleep_time=5
  local elapsed=0

  echo "⏳ 等待 Pod ($label) Ready 或 Completed 中..."

  while true; do
    NOT_READY=$(kubectl get pods -A -l "$label" 2>/dev/null | awk 'NR>1 && $4 != "Running" && $4 != "Completed"')
    if [ -z "$NOT_READY" ]; then
      echo "✅ [$label] 所有 Pod 就緒！"
      break
    fi

    if [ "$elapsed" -ge "$timeout" ]; then
      echo "❌ [$label] 超過 $timeout 秒仍有未就緒 Pod："
      echo "$NOT_READY"

      # 超過 timeout 時，強制刪除 Pod 並重新部署
      echo "🚀 正在重新部署 Pod..."
      kubectl delete pod -l "$label" -n default  # 刪除所有符合標籤的 Pod
      sleep 10  # 等待 10 秒鐘，讓 Kubernetes 重新部署 Pod

      # 重新檢查 Pod 的狀態
      echo "⏳ 等待重新部署的 Pod ..."
      elapsed=0  # 重置計時器
      continue  # 重新進行等待檢查
    fi

    sleep "$sleep_time"
    elapsed=$((elapsed + sleep_time))
  done
}

# 安裝 elasticsearch 並等待
helm upgrade --install elasticsearch elastic/elasticsearch -f elasticsearch/values.yml --timeout 600s
wait_for_pod_ready "app=elasticsearch-master"

# 安裝 filebeat 並等待
helm upgrade --install filebeat elastic/filebeat -f filebeat/values.yml --timeout 600s
wait_for_pod_ready "app=filebeat-filebeat"

# 安裝 logstash 並等待
helm upgrade --install logstash elastic/logstash -f logstash/values.yml --timeout 600s
wait_for_pod_ready "app=logstash-logstash"

# 安裝 kibana 並等待
helm upgrade --install kibana elastic/kibana -f kibana/values.yml --timeout 600s --force
wait_for_pod_ready "app=kibana"
helm list

# 安裝 Filebeat
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/9.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-9.x.list
sudo apt-get update && sudo apt-get install filebeat
sudo systemctl enable filebeat


ES_PASS=$(kubectl get secret elasticsearch-master-credentials -o jsonpath="{.data.password}" | base64 --decode) # 取得 Elasticsearch 密碼並解碼存入變數
sudo sed -i '25s|.*|  id: ubuntu|' /etc/filebeat/filebeat.yml  # 修改 filebeat.yml 的 id 欄位（第 25 行）
sudo sed -i '28s|.*|  enabled: true|' /etc/filebeat/filebeat.yml # 啟用設定（第 28 行）
sudo sed -i '171s|.*|  protocol: "https"|' /etc/filebeat/filebeat.yml  # 修改 protocol（第 171 行）
sudo sed -i '175s|.*|  username: "elastic"|' /etc/filebeat/filebeat.yml # 設定 username（第 175 行）
sudo sed -i "176s|.*|  password: \"$ES_PASS\"|" /etc/filebeat/filebeat.yml  # 設定 password，注意：這裡用雙引號讓變數展開！
# 在 protocol: "https" 下方插入 SSL 段
sudo sed -i '/protocol: "https"/a\  ssl:\n    verification_mode: "none"' /etc/filebeat/filebeat.yml


sudo filebeat test config # 測試 Filebeat 配置是否正確
sudo filebeat test output # 測試輸出是否正確
sudo systemctl restart filebeat # 重啟 Filebeat 服務

cd elasticsearch
bash go.sh
bash create_api_key.sh
bash test_api_key.sh
pip install requests joblib tqdm
#source .venv/bin/activate
python ~/AQUA-CARE-2025-June-main/elk/dataset/import_dataset.py | tee import.log

sudo systemctl enable unattended-upgrades  # 啟用自動更新
sudo systemctl status unattended-upgrades  # 確認自動更新服務狀態


echo "$ES_PASS"
echo "✅ K3s 與 Elastic Stack 安裝完成！"