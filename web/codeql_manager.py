#!/usr/bin/env python3
"""
CodeQL管理模块
提供CodeQL CLI的下载、安装和管理功能
"""

import os
import os
import subprocess
import requests
import zipfile
import shutil
from pathlib import Path
import logging

class CodeQLManager:
    def __init__(self, base_dir='/app'):
        self.base_dir = Path(base_dir)
        self.codeql_dir = self.base_dir / 'codeql'
        self.codeql_bin = self.codeql_dir / 'codeql'
        self.download_url = "https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip"
        self.file_name = "codeql-linux64.zip"
        
    def is_codeql_installed(self) -> bool:
        """检查CodeQL是否已安装"""
        return self.codeql_bin.exists() and self.codeql_bin.is_file()
    
    def get_codeql_version(self) -> str:
        """获取CodeQL版本"""
        if not self.is_codeql_installed():
            return None
        
        try:
            result = subprocess.run(
                [str(self.codeql_bin), "version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                # 提取版本号（通常在第一行）
                version_line = result.stdout.strip().split('\n')[0]
                return version_line
            else:
                logging.warning(f"获取CodeQL版本失败: {result.stderr}")
                return None
                
        except Exception as e:
            logging.error(f"获取CodeQL版本时出错: {str(e)}")
            return None
    
    def download_codeql(self, progress_callback=None) -> Dict[str, Any]:
        """
        下载CodeQL CLI
        
        Args:
            progress_callback: 进度回调函数，接收 (downloaded, total) 参数
            
        Returns:
            Dict包含下载结果信息
        """
        result = {
            "success": False,
            "message": "",
            "version": None
        }
        
        try:
            logging.info("开始下载CodeQL...")
            logging.info(f"下载地址: {self.download_url}")
            
            # 创建临时目录
            with tempfile.TemporaryDirectory() as temp_dir:
                temp_file = Path(temp_dir) / self.file_name
                
                # 下载文件
                logging.info(f"正在下载到临时文件: {temp_file}")
                
                response = requests.get(self.download_url, stream=True)
                response.raise_for_status()
                
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0
                
                with open(temp_file, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            
                            # 调用进度回调
                            if progress_callback:
                                progress_callback(downloaded, total_size)
                
                # 验证下载的文件
                if not temp_file.exists() or temp_file.stat().st_size == 0:
                    result["message"] = "下载的文件无效或为空"
                    return result
                
                logging.info(f"下载完成，文件大小: {temp_file.stat().st_size} bytes")
                
                # 确保CodeQL目录存在
                self.codeql_dir.mkdir(parents=True, exist_ok=True)
                
                # 解压文件
                logging.info(f"正在解压到: {self.codeql_dir}")
                with zipfile.ZipFile(temp_file, 'r') as zip_ref:
                    zip_ref.extractall(self.codeql_dir)
                
                # 移动文件到正确位置（如果解压后在子目录中）
                codeql_subdir = self.codeql_dir / "codeql"
                if codeql_subdir.exists() and codeql_subdir.is_dir():
                    logging.info("移动CodeQL文件到根目录")
                    for item in codeql_subdir.iterdir():
                        shutil.move(str(item), str(self.codeql_dir / item.name))
                    codeql_subdir.rmdir()
                
                # 设置执行权限
                codeql_exe = self.codeql_dir / "codeql"
                if codeql_exe.exists():
                    os.chmod(codeql_exe, 0o755)
                    logging.info("设置CodeQL可执行权限")
                
                logging.info("CodeQL下载和安装完成")
                
                # 验证安装
                if self.is_codeql_installed():
                    result["success"] = True
                    result["message"] = "CodeQL下载和安装成功"
                    result["version"] = self.get_codeql_version()
                else:
                    result["message"] = "CodeQL下载完成但安装验证失败"
                
        except requests.RequestException as e:
            result["message"] = f"下载失败: {str(e)}"
            logging.error(f"下载CodeQL时出错: {str(e)}")
        except zipfile.BadZipFile as e:
            result["message"] = f"解压失败: {str(e)}"
            logging.error(f"解压CodeQL时出错: {str(e)}")
        except Exception as e:
            result["message"] = f"安装失败: {str(e)}"
            logging.error(f"安装CodeQL时出错: {str(e)}")
        
        return result
    
    def get_status(self) -> Dict[str, Any]:
        """获取CodeQL状态信息"""
        status = {
            "installed": False,
            "version": None,
            "path": str(self.codeql_dir),
            "executable": None
        }
        
        try:
            status["installed"] = self.is_codeql_installed()
            if status["installed"]:
                status["version"] = self.get_codeql_version()
                status["executable"] = str(self.codeql_dir / "codeql")
        except Exception as e:
            logging.error(f"获取CodeQL状态时出错: {str(e)}")
        
        return status
    
    def ensure_codeql_available(self) -> Dict[str, Any]:
        """确保CodeQL可用，如果不可用则自动下载"""
        if self.is_codeql_installed():
            return {
                "success": True,
                "message": "CodeQL已安装",
                "action": "none",
                "version": self.get_codeql_version()
            }
        
        logging.info("CodeQL未安装，开始自动下载...")
        result = self.download_codeql()
        result["action"] = "download"
        return result