#!/bin/bash
# 《聲畫合鳴》Demo 启动脚本

cd "$(dirname "$0")"

echo "========================================"
echo "《聲畫合鳴》Echo & Etch - Demo 启动"
echo "========================================"
echo ""
echo "1. 安装依赖（首次运行）"
echo "2. 启动后端服务"
echo "3. 打开浏览器访问"
echo ""

# 安装依赖
echo ">>> 安装 Python 依赖..."
cd backend
pip install -r requirements.txt -q

# 启动后端
echo ""
echo ">>> 启动后端服务 (http://localhost:8721) ..."
echo ">>> 按 Ctrl+C 停止服务"
echo ""
python app.py
