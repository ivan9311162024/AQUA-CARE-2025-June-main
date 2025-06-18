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
pip install ansible #requests joblib tqdm

# 啟用虛擬環境
source .venv/bin/activate

echo "✅ Virtual environment and Ansible are ready."  # 提示環境準備完成

