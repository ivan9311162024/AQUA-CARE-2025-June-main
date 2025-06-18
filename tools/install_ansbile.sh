#!/bin/bash
set -e  # 一旦遇到錯誤指令就終止腳本執行，避免後續錯誤連鎖發生

# 更新套件清單（從 APT 套件庫抓取最新資訊）
sudo apt update

# 安裝 Python 3.12 的 venv 模組（用來建立虛擬環境）
sudo apt install -y python3.12-venv

# 如果目前目錄下沒有 .venv 資料夾，就建立一個虛擬環境
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

# 以下建議手動輸入指令（或者也可以取消註解來自動執行）

# # 啟用虛擬環境（會切換到 .venv 環境）
source .venv/bin/activate

# # 升級 pip 版本，避免安裝套件時出現警告
pip install --upgrade pip

# # 安裝 Ansible 與其他輔助工具（requests: API 操作，joblib/tqdm: 並行與進度條）
pip install ansible requests joblib tqdm

# 啟用虛擬環境
source .venv/bin/activate

echo "✅ Virtual environment and Ansible are ready."  # 提示環境準備完成

ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml  # 安裝 k3s

source ~/.bashrc  # 重新載入 bash 設定檔
k get po -A # 列出所有 Kubernetes Pod
cd elk/

# 安裝 Elastic Stack 的 Helm Charts
helm search repo elastic
helm install elasticsearch elastic/elasticsearch -f elasticsearch/values.yml   
helm install filebeat elastic/filebeat -f filebeat/values.yml
helm install logstash elastic/logstash -f  logstash/values.yml
helm install kibana elastic/kibana -f kibana/values.yml 
helm list

# 安裝 Filebeat
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/9.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-9.x.list
sudo apt-get update && sudo apt-get install filebeat
sudo systemctl enable filebeat


ES_PASS=$(kubectl get secret elasticsearch-master-credentials -o jsonpath="{.data.password}" | base64 --decode) # 取得 Elasticsearch 密碼並解碼存入變數
sudo sed -i '25s|.*|id: ubuntu|' /etc/filebeat/filebeat.yml  # 修改 filebeat.yml 的 id 欄位（第 25 行）
sudo sed -i '28s|.*|enabled: true|' /etc/filebeat/filebeat.yml # 啟用設定（第 28 行）
sudo sed -i '171s|.*|protocol: "https"|' /etc/filebeat/filebeat.yml  # 修改 protocol（第 171 行）
sudo sed -i '175s|.*|  username: "elastic"|' /etc/filebeat/filebeat.yml # 設定 username（第 175 行）
sudo sed -i "176s|.*|  password: \"$ES_PASS\"|" /etc/filebeat/filebeat.yml  # 設定 password，注意：這裡用雙引號讓變數展開！
sudo sed -i '172a\  ssl:\n    verification_mode: "none"' /etc/filebeat/filebeat.yml # 在第 30 行後插入 ssl 段（兩行），注意要有正確縮排

sudo filebeat test config # 測試 Filebeat 配置是否正確
sudo filebeat test output # 測試輸出是否正確
sudo systemctl restart filebeat # 重啟 Filebeat 服務

cd elasticsearch
bash go.sh
bash create_api_key.sh
bash test_api_key.sh
python import_dataset.py