#!/usr/bin/env python3
"""
CodeQL Database Builder Web Management Interface
提供Web界面来管理构建任务、查看日志和配置参数
支持Boot JDK版本选择、数据库压缩包管理、文件上传和构建中断
"""

from flask import Flask, render_template, request, jsonify, send_file, Response
import os
import json
import subprocess
import threading
import time
from datetime import datetime
import sqlite3
import logging
from pathlib import Path
from werkzeug.utils import secure_filename
import zipfile
import shutil
import signal
import tarfile
import glob
from codeql_manager import CodeQLManager

app = Flask(__name__)
app.secret_key = 'codeql_builder_secret_key'

# 路径配置
BASE_DIR = Path('/app')
DATA_DIR = BASE_DIR / 'data'
BOOTJDK_DIR = BASE_DIR / 'bootjdk'
DB_PATH = BASE_DIR / 'web' / 'build_history.db'
LOG_DIR = BASE_DIR / 'logs'

# 确保目录存在
LOG_DIR.mkdir(exist_ok=True)
DB_PATH.parent.mkdir(exist_ok=True)
BOOTJDK_DIR.mkdir(exist_ok=True)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_DIR / 'web_ui.log'),
        logging.StreamHandler()
    ]
)

def extract_boot_jdk_on_startup():
    """在Web应用启动时解压Boot JDK压缩包"""
    try:
        # 查找Boot JDK压缩包
        archive_patterns = [
            str(BOOTJDK_DIR / "*.tar.gz"),
            str(BOOTJDK_DIR / "*.tgz")
        ]
        
        archives = []
        for pattern in archive_patterns:
            archives.extend(glob.glob(pattern))
        
        if not archives:
            logging.info("No Boot JDK archives found in /app/bootjdk")
            return
        
        extract_dir = BOOTJDK_DIR / "_extracted"
        
        for archive_path in archives:
            archive_name = os.path.basename(archive_path)
            logging.info(f"Found Boot JDK archive: {archive_name}")
            
            # 检查是否已经解压过
            if extract_dir.exists() and any(extract_dir.iterdir()):
                logging.info("Boot JDK already extracted, skipping extraction")
                # 删除压缩文件
                try:
                    os.remove(archive_path)
                    logging.info(f"Deleted archive file: {archive_name}")
                except Exception as e:
                    logging.error(f"Failed to delete archive {archive_name}: {str(e)}")
                continue
            
            # 创建解压目录
            extract_dir.mkdir(exist_ok=True)
            
            # 解压压缩包
            logging.info(f"Extracting Boot JDK archive: {archive_name}")
            try:
                with tarfile.open(archive_path, 'r:gz') as tar:
                    tar.extractall(path=extract_dir)
                logging.info(f"Successfully extracted {archive_name}")
                
                # 解压成功后删除压缩文件
                os.remove(archive_path)
                logging.info(f"Deleted archive file: {archive_name}")
                
            except Exception as e:
                logging.error(f"Failed to extract {archive_name}: {str(e)}")
                # 如果解压失败，清理可能的部分解压文件
                if extract_dir.exists():
                    shutil.rmtree(extract_dir, ignore_errors=True)
                
    except Exception as e:
        logging.error(f"Error during Boot JDK extraction: {str(e)}")

# 在Web应用启动时执行Boot JDK解压
extract_boot_jdk_on_startup()

# 初始化CodeQL管理器
codeql_manager = CodeQLManager()

class BuildManager:
    def __init__(self):
        self.current_builds = {}
        self.build_processes = {}  # 存储构建进程
        self.init_database()
    
    def init_database(self):
        """初始化数据库"""
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # 创建构建历史表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS build_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                build_id TEXT UNIQUE NOT NULL,
                jdk_version TEXT NOT NULL,
                jdk_full_version TEXT,
                build_mode TEXT NOT NULL,
                db_name TEXT NOT NULL,
                boot_jdk_path TEXT,
                database_name TEXT,
                compressed INTEGER DEFAULT 0,
                status TEXT NOT NULL,
                start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                end_time TIMESTAMP,
                duration INTEGER,
                error_message TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def start_build(self, config):
        """启动构建任务"""
        build_id = f"build_{int(time.time())}"
        
        # 记录构建开始
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO build_history 
            (build_id, jdk_version, jdk_full_version, build_mode, db_name, boot_jdk_path, database_name, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            build_id,
            config['jdk_version'],
            config.get('jdk_full_version', ''),
            config['build_mode'],
            config['db_name'],
            config.get('boot_jdk_path', ''),
            config['db_name'],
            'running'
        ))
        conn.commit()
        conn.close()
        
        # 初始化构建状态
        self.current_builds[build_id] = {
            'status': 'running',
            'progress': 0,
            'start_time': datetime.now(),
            'config': config
        }
        
        # 启动构建线程
        build_thread = threading.Thread(target=self._run_build, args=(build_id, config))
        build_thread.daemon = True
        build_thread.start()
        
        return build_id
    
    def stop_build(self, build_id):
        """停止构建任务"""
        if build_id not in self.current_builds:
            return False
            
        if build_id in self.build_processes:
            try:
                process = self.build_processes[build_id]
                # 终止进程组
                os.killpg(os.getpgid(process.pid), signal.SIGTERM)
                process.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    # 强制终止
                    os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            finally:
                del self.build_processes[build_id]
        
        # 更新构建状态
        self.current_builds[build_id]['status'] = 'stopped'
        
        # 更新数据库
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE build_history 
            SET status = ?, end_time = CURRENT_TIMESTAMP,
                duration = (julianday(CURRENT_TIMESTAMP) - julianday(start_time)) * 86400
            WHERE build_id = ?
        ''', ('stopped', build_id))
        conn.commit()
        conn.close()
        
        return True
    
    def _run_build(self, build_id, config):
        """执行构建任务"""
        try:
            # 设置环境变量
            env = os.environ.copy()
            env.update({
                'JDK_VERSION': config['jdk_version'],
                'JDK_FULL_VERSION': config.get('jdk_full_version', ''),
                'BUILD_MODE': config['build_mode'],
                'DB_NAME': config['db_name']
            })
            
            if config.get('boot_jdk_path'):
                env['BOOT_JDK_PATH'] = config['boot_jdk_path']
            
            # 启动构建脚本
            cmd = ['/bin/bash', '/app/scripts/build-db.sh']
            process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                preexec_fn=os.setsid  # 创建新的进程组
            )
            
            # 保存进程引用
            self.build_processes[build_id] = process
            
            # 创建日志文件
            log_file = LOG_DIR / f'{build_id}.log'
            
            # 读取输出并更新进度
            with open(log_file, 'w') as f:
                for line in process.stdout:
                    f.write(line)
                    f.flush()
                    
                    # 检查是否被中断
                    if build_id not in self.current_builds or self.current_builds[build_id]['status'] == 'stopped':
                        break
                    
                    # 简单的进度估算
                    if 'Downloading' in line:
                        self.current_builds[build_id]['progress'] = 20
                    elif 'Compiling' in line:
                        self.current_builds[build_id]['progress'] = 50
                    elif 'Creating database' in line:
                        self.current_builds[build_id]['progress'] = 80
                    elif 'Build completed' in line:
                        self.current_builds[build_id]['progress'] = 100
            
            # 等待进程完成
            return_code = process.wait()
            
            # 清理进程引用
            if build_id in self.build_processes:
                del self.build_processes[build_id]
            
            # 检查是否被中断
            if build_id not in self.current_builds or self.current_builds[build_id]['status'] == 'stopped':
                return
            
            # 更新构建状态
            if return_code == 0:
                self.current_builds[build_id]['status'] = 'success'
                self.current_builds[build_id]['progress'] = 100
                
                # 自动压缩数据库
                try:
                    compress_cmd = ['/bin/bash', '/app/scripts/database-manager.sh', 'compress', config['db_name']]
                    subprocess.run(compress_cmd, check=True)
                    
                    # 更新压缩状态
                    conn = sqlite3.connect(DB_PATH)
                    cursor = conn.cursor()
                    cursor.execute('UPDATE build_history SET compressed = 1 WHERE build_id = ?', (build_id,))
                    conn.commit()
                    conn.close()
                    
                except Exception as e:
                    logging.error(f"Database compression failed for {build_id}: {str(e)}")
            else:
                self.current_builds[build_id]['status'] = 'failed'
            
            # 更新数据库记录
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute('''
                UPDATE build_history 
                SET status = ?, end_time = CURRENT_TIMESTAMP,
                    duration = (julianday(CURRENT_TIMESTAMP) - julianday(start_time)) * 86400
                WHERE build_id = ?
            ''', (self.current_builds[build_id]['status'], build_id))
            conn.commit()
            conn.close()
            
        except Exception as e:
            logging.error(f"Build {build_id} failed: {str(e)}")
            if build_id in self.current_builds:
                self.current_builds[build_id]['status'] = 'error'
                self.current_builds[build_id]['error'] = str(e)
            
            # 清理进程引用
            if build_id in self.build_processes:
                del self.build_processes[build_id]

build_manager = BuildManager()

@app.route('/')
def index():
    """主页面"""
    return render_template('index.html')

@app.route('/api/config')
def get_config():
    """获取当前配置"""
    config = {
        'jdk_version': os.getenv('JDK_VERSION', '17'),
        'jdk_full_version': os.getenv('JDK_FULL_VERSION', ''),
        'build_mode': os.getenv('BUILD_MODE', 'hybrid'),
        'db_name': os.getenv('DB_NAME', 'codeql_db')
    }
    return jsonify(config)

@app.route('/api/boot-jdks')
def get_boot_jdks():
    """获取可用的Boot JDK列表"""
    try:
        result = subprocess.run(['/app/scripts/jdk-manager.sh', 'list'], 
                              capture_output=True, text=True, check=True)
        jdks = json.loads(result.stdout)
        return jsonify(jdks)
    except Exception as e:
        logging.error(f"Failed to get Boot JDKs: {str(e)}")
        return jsonify([])

@app.route('/api/boot-jdks/scan', methods=['POST'])
def scan_boot_jdks():
    """扫描Boot JDK"""
    try:
        subprocess.run(['/app/scripts/jdk-manager.sh', 'scan'], check=True)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/build', methods=['POST'])
def start_build():
    """启动构建任务"""
    config = request.json
    build_id = build_manager.start_build(config)
    return jsonify({'build_id': build_id, 'status': 'started'})

@app.route('/api/build/<build_id>/status')
def get_build_status(build_id):
    """获取构建状态"""
    if build_id in build_manager.current_builds:
        build_info = build_manager.current_builds[build_id].copy()
        # 转换datetime为字符串
        if 'start_time' in build_info:
            build_info['start_time'] = build_info['start_time'].isoformat()
        return jsonify(build_info)
    
    # 从数据库查询历史构建
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT status, start_time, end_time, duration FROM build_history WHERE build_id = ?', (build_id,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        return jsonify({
            'status': row[0],
            'progress': 100 if row[0] == 'success' else 0,
            'start_time': row[1],
            'end_time': row[2],
            'duration': row[3]
        })
    
    return jsonify({'error': 'Build not found'}), 404

@app.route('/api/build/<build_id>/stop', methods=['POST'])
def stop_build(build_id):
    """停止构建任务"""
    try:
        success = build_manager.stop_build(build_id)
        if success:
            return jsonify({'status': 'success', 'message': '构建已停止'})
        else:
            return jsonify({'status': 'error', 'message': '构建不存在或已完成'})
    except Exception as e:
        logging.error(f"Stop build failed: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/builds')
def get_builds():
    """获取构建历史"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT build_id, jdk_version, jdk_full_version, boot_jdk_path, build_mode, 
               start_time, end_time, status, duration, database_name, compressed
        FROM build_history 
        ORDER BY start_time DESC 
        LIMIT 50
    ''')
    rows = cursor.fetchall()
    conn.close()
    
    builds = []
    for row in rows:
        builds.append({
            'build_id': row[0],
            'jdk_version': row[1],
            'jdk_full_version': row[2],
            'boot_jdk_path': row[3],
            'build_mode': row[4],
            'start_time': row[5],
            'end_time': row[6],
            'status': row[7],
            'duration': row[8],
            'database_name': row[9],
            'compressed': bool(row[10])
        })
    
    return jsonify(builds)

@app.route('/api/logs/<build_id>')
def get_build_log(build_id):
    """获取构建日志"""
    log_file = LOG_DIR / f"{build_id}.log"
    if log_file.exists():
        return send_file(log_file, as_attachment=False, mimetype='text/plain')
    return "Log file not found", 404

@app.route('/api/upload-source', methods=['POST'])
def upload_source():
    """上传用户源码"""
    try:
        if 'file' not in request.files:
            return jsonify({'status': 'error', 'message': '没有选择文件'})
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'status': 'error', 'message': '没有选择文件'})
        
        # 检查文件类型
        filename = secure_filename(file.filename)
        if not filename.lower().endswith(('.zip', '.jar')):
            return jsonify({'status': 'error', 'message': '只支持ZIP和JAR文件'})
        
        # 彻底清空用户源码目录（包括宿主机目录）- 使用构建脚本期望的路径
        user_source_dir = BASE_DIR / 'user-source'
        
        # 先清空容器内的目录内容（不删除挂载点目录本身）
        if user_source_dir.exists():
            logging.info(f"清空用户源码目录内容: {user_source_dir}")
            # 只删除目录内的内容，不删除目录本身（避免挂载点问题）
            for item in user_source_dir.iterdir():
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
        
        # 确保目录存在
        user_source_dir.mkdir(parents=True, exist_ok=True)
        
        # 同时清空宿主机上的映射目录（通过删除所有内容）
        try:
            # 使用shell命令确保彻底清理宿主机目录
            cleanup_cmd = [
                '/bin/bash', '-c', 
                'find /app/user-source -mindepth 1 -delete 2>/dev/null || true'
            ]
            subprocess.run(cleanup_cmd, capture_output=True, text=True)
            logging.info("已清空宿主机用户源码目录")
        except Exception as e:
            logging.warning(f"清空宿主机目录时出现警告: {str(e)}")
        
        # 保存上传的文件
        file_path = user_source_dir / filename
        file.save(file_path)
        logging.info(f"文件已保存到: {file_path}")
        
        # 处理文件
        if filename.lower().endswith('.zip'):
            # 解压ZIP文件
            logging.info(f"开始解压ZIP文件: {filename}")
            with zipfile.ZipFile(file_path, 'r') as zip_ref:
                zip_ref.extractall(user_source_dir)
            # 删除ZIP文件
            os.remove(file_path)
            logging.info("ZIP文件解压完成并已删除原文件")
            
        elif filename.lower().endswith('.jar'):
            # 处理JAR文件 - 使用反编译器将class文件转换为Java源码
            logging.info(f"开始处理JAR文件: {filename}")
            
            # 直接反编译到user-source目录，而不是子目录
            # 这样CodeQL可以直接识别和分析反编译后的源码
            
            try:
                # 获取反编译器选项（默认使用procyon）
                decompiler = request.form.get('decompiler', 'procyon')
                logging.info(f"使用反编译器: {decompiler}")
                
                # 调用反编译脚本，直接输出到user-source目录
                decompile_cmd = [
                    '/bin/bash', '/app/scripts/decompile-jar.sh',
                    str(file_path), str(user_source_dir), decompiler
                ]
                
                # 执行反编译命令
                result = subprocess.run(decompile_cmd, capture_output=True, text=True)
                
                # 检查反编译结果
                if result.returncode != 0:
                    logging.error(f"反编译失败: {result.stderr}")
                    return jsonify({
                        'status': 'error', 
                        'message': f'反编译失败: {result.stderr}'
                    })
                
                # 记录反编译输出
                logging.info(f"反编译输出: {result.stdout}")
                
                # 删除原始JAR文件
                os.remove(file_path)
                logging.info("JAR文件反编译完成并已删除原文件")
                
                # 统计反编译生成的Java文件数量
                java_files = list(user_source_dir.rglob('*.java'))
                java_count = len(java_files)
                logging.info(f"反编译生成 {java_count} 个Java文件")
                
                # 如果没有生成Java文件，可能是反编译失败或JAR包中没有class文件
                if java_count == 0:
                    logging.warning("反编译没有生成任何Java文件，尝试直接解压JAR文件")
                    
                    # 重新保存JAR文件（因为之前已删除）
                    file.seek(0)
                    file.save(file_path)
                    
                    # 使用zipfile库解压JAR文件到user-source目录
                    with zipfile.ZipFile(file_path, 'r') as jar_ref:
                        # 解压所有文件
                        for file_info in jar_ref.infolist():
                            # 跳过META-INF目录
                            if file_info.filename.startswith('META-INF/'):
                                continue
                                
                            # 解压文件到user-source目录
                            jar_ref.extract(file_info, user_source_dir)
                            
                            # 设置正确的文件权限
                            target_path = os.path.join(user_source_dir, file_info.filename)
                            if os.path.exists(target_path) and not os.path.isdir(target_path):
                                os.chmod(target_path, 0o644)
                    
                    # 删除JAR文件
                    os.remove(file_path)
                    
                    # 记录解压的文件数量
                    extracted_files = list(user_source_dir.rglob('*'))
                    extracted_count = len([f for f in extracted_files if f.is_file()])
                    logging.info(f"从JAR文件中解压出 {extracted_count} 个文件")
                
            except Exception as jar_error:
                logging.error(f"JAR文件处理失败: {str(jar_error)}")
                return jsonify({
                    'status': 'error', 
                    'message': f'JAR文件处理失败: {str(jar_error)}'
                })
        
        # 验证上传结果
        uploaded_files = list(user_source_dir.rglob('*'))
        file_count = len([f for f in uploaded_files if f.is_file()])
        logging.info(f"上传完成，共处理 {file_count} 个文件")
        
        return jsonify({
            'status': 'success', 
            'message': f'文件上传成功，共处理 {file_count} 个文件'
        })
        
    except Exception as e:
        logging.error(f"Upload source failed: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/clear-user-source', methods=['POST'])
def clear_user_source():
    """清空用户源码"""
    try:
        user_source_dir = BASE_DIR / 'user-source'
        
        # 清空容器内的目录内容（不删除挂载点目录本身）
        if user_source_dir.exists():
            logging.info(f"清空用户源码目录内容: {user_source_dir}")
            # 只删除目录内的内容，不删除目录本身（避免挂载点问题）
            for item in user_source_dir.iterdir():
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
        
        # 确保目录存在
        user_source_dir.mkdir(parents=True, exist_ok=True)
        
        # 同时清空宿主机上的映射目录
        try:
            # 使用shell命令确保彻底清理宿主机目录
            cleanup_cmd = [
                '/bin/bash', '-c', 
                'find /app/user-source -mindepth 1 -delete 2>/dev/null || true'
            ]
            subprocess.run(cleanup_cmd, capture_output=True, text=True)
            logging.info("已清空宿主机用户源码目录")
        except Exception as e:
            logging.warning(f"清空宿主机目录时出现警告: {str(e)}")
        
        return jsonify({'status': 'success', 'message': '用户源码已彻底清空'})
        
    except Exception as e:
        logging.error(f"Clear user source failed: {str(e)}")
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/database-archives')
def get_database_archives():
    """获取数据库压缩包列表"""
    try:
        result = subprocess.run(['/app/scripts/database-manager.sh', 'list'], 
                              capture_output=True, text=True, check=True)
        archives = json.loads(result.stdout)
        return jsonify(archives)
    except Exception as e:
        logging.error(f"Failed to get database archives: {str(e)}")
        return jsonify([])

@app.route('/api/database-archives/<archive_name>/download')
def download_database_archive(archive_name):
    """下载数据库压缩包"""
    archive_path = Path('/app/data/database/archives') / archive_name
    if archive_path.exists():
        return send_file(archive_path, as_attachment=True)
    return "Archive not found", 404

@app.route('/api/database-archives/<archive_name>', methods=['DELETE'])
def delete_database_archive(archive_name):
    """删除数据库压缩包"""
    try:
        subprocess.run(['/app/scripts/database-manager.sh', 'delete', archive_name], 
                      check=True)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/database-archives/<archive_name>/extract', methods=['POST'])
def extract_database_archive(archive_name):
    """解压数据库压缩包"""
    try:
        subprocess.run(['/app/scripts/database-manager.sh', 'extract', archive_name], 
                      check=True)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/database-archives/cleanup', methods=['POST'])
def cleanup_database_residuals():
    """清理残留的数据库文件"""
    try:
        subprocess.run(['/app/scripts/database-manager.sh', 'cleanup'], 
                      check=True)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/storage-stats')
def get_storage_stats():
    """获取存储统计信息"""
    try:
        result = subprocess.run(['/app/scripts/database-manager.sh', 'stats'], 
                              capture_output=True, text=True, check=True)
        stats = json.loads(result.stdout)
        return jsonify(stats)
    except Exception as e:
        logging.error(f"Failed to get storage stats: {str(e)}")
        return jsonify({})

@app.route('/api/stats')
def get_stats():
    """获取统计信息"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # 总构建次数
    cursor.execute('SELECT COUNT(*) FROM build_history')
    total_builds = cursor.fetchone()[0]
    
    # 成功率
    cursor.execute('SELECT COUNT(*) FROM build_history WHERE status = "success"')
    successful_builds = cursor.fetchone()[0]
    
    # 平均构建时间
    cursor.execute('SELECT AVG(duration) FROM build_history WHERE status = "success"')
    avg_duration = cursor.fetchone()[0] or 0
    
    # 压缩统计
    cursor.execute('SELECT COUNT(*) FROM build_history WHERE compressed = 1')
    compressed_builds = cursor.fetchone()[0]
    
    conn.close()
    
    success_rate = (successful_builds / total_builds * 100) if total_builds > 0 else 0
    compression_rate = (compressed_builds / total_builds * 100) if total_builds > 0 else 0
    
    return jsonify({
        'total_builds': total_builds,
        'successful_builds': successful_builds,
        'success_rate': round(success_rate, 2),
        'avg_duration': round(avg_duration, 2),
        'compressed_builds': compressed_builds,
        'compression_rate': round(compression_rate, 2)
    })

# CodeQL管理API端点
@app.route('/api/codeql/status')
def get_codeql_status():
    """获取CodeQL状态"""
    try:
        status = codeql_manager.get_status()
        return jsonify(status)
    except Exception as e:
        logging.error(f"Failed to get CodeQL status: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/codeql/download', methods=['POST'])
def download_codeql():
    """下载CodeQL CLI"""
    try:
        result = codeql_manager.download_codeql()
        if result['success']:
            return jsonify(result)
        else:
            return jsonify(result), 400
    except Exception as e:
        logging.error(f"Failed to download CodeQL: {str(e)}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/codeql/ensure', methods=['POST'])
def ensure_codeql():
    """确保CodeQL可用（如果不可用则自动下载）"""
    try:
        result = codeql_manager.ensure_codeql_available()
        if result['success']:
            return jsonify(result)
        else:
            return jsonify(result), 400
    except Exception as e:
        logging.error(f"Failed to ensure CodeQL: {str(e)}")
        return jsonify({'success': False, 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)