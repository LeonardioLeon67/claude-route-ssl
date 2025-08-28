#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
定时任务脚本：更新产品过期时间
每天北京时间1:00和13:00执行
根据soldAt时间（北京时间）设置过期时间
Trial级别：soldAt + 1天
其他级别：soldAt + 30天
"""

import json
import os
from datetime import datetime, timedelta
import pytz
import redis
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/leon/claude-route-ssl/claude-route-ssl/logs/expire-update.log'),
        logging.StreamHandler()
    ]
)

# 配置
PRODUCT_DIR = '/home/leon/claude-route-ssl/claude-route-ssl/product'
REDIS_PORT = 6380
BEIJING_TZ = pytz.timezone('Asia/Shanghai')

def parse_sold_at(sold_at_str):
    """解析soldAt时间字符串（北京时间）"""
    if sold_at_str is None:
        return None
    
    try:
        # soldAt格式: "2025-08-14 15:42:05"
        # 假设这是北京时间
        dt = datetime.strptime(sold_at_str, "%Y-%m-%d %H:%M:%S")
        # 添加北京时区信息
        dt_beijing = BEIJING_TZ.localize(dt)
        return dt_beijing
    except Exception as e:
        logging.error(f"Failed to parse soldAt: {sold_at_str}, error: {e}")
        return None

def update_product_file(file_path, tier):
    """更新产品文件中的过期时间"""
    try:
        # 读取文件
        with open(file_path, 'r') as f:
            products = json.load(f)
        
        updated_count = 0
        
        # 遍历所有产品
        for key, product in products.items():
            sold_at_value = product.get('soldAt')
            
            # 如果soldAt为None（JSON的null），跳过不处理，保持原样
            if sold_at_value is None:
                # 不做任何修改，保持原有的null状态
                continue
                
            # 只处理有有效soldAt时间的产品
            if product.get('status') == 'sold' and sold_at_value:
                sold_at = parse_sold_at(sold_at_value)
                
                if sold_at:
                    # 计算过期时间（Trial为1天，其他为30天）
                    days_to_add = 1 if tier == 'trial' else 30
                    expire_dt = sold_at + timedelta(days=days_to_add)
                    
                    # 转换为时间戳（毫秒）
                    expire_timestamp = int(expire_dt.timestamp() * 1000)
                    
                    # 格式化为北京时间字符串
                    expire_date_str = expire_dt.astimezone(BEIJING_TZ).strftime("%Y-%m-%d %H:%M:%S")
                    
                    # 更新产品信息
                    product['expiresAt'] = expire_timestamp
                    product['expiresDate'] = expire_date_str
                    
                    updated_count += 1
                    logging.info(f"Updated {tier} key {key[:20]}...: soldAt={product['soldAt']}, expiresDate={expire_date_str}")
        
        # 保存更新后的文件
        with open(file_path, 'w') as f:
            json.dump(products, f, indent=2, ensure_ascii=False)
        
        logging.info(f"Updated {updated_count} products in {file_path}")
        return updated_count
        
    except Exception as e:
        logging.error(f"Error updating file {file_path}: {e}")
        return 0

def update_redis_products(tier):
    """更新Redis中的产品过期时间"""
    try:
        r = redis.Redis(host='localhost', port=REDIS_PORT, decode_responses=True)
        
        # 获取所有该级别的产品key
        pattern = f"{tier}_products:*"
        product_keys = r.keys(pattern)
        
        updated_count = 0
        
        for redis_key in product_keys:
            product_data = r.hgetall(redis_key)
            sold_at_value = product_data.get('soldAt')
            
            # 如果soldAt为None或空字符串（Redis中的None表现为空字符串），跳过不处理
            if not sold_at_value:
                continue
                
            if product_data and product_data.get('status') == 'sold' and sold_at_value:
                sold_at = parse_sold_at(sold_at_value)
                
                if sold_at:
                    # 计算过期时间（Trial为1天，其他为30天）
                    days_to_add = 1 if tier == 'trial' else 30
                    expire_dt = sold_at + timedelta(days=days_to_add)
                    expire_timestamp = int(expire_dt.timestamp() * 1000)
                    expire_date_str = expire_dt.astimezone(BEIJING_TZ).strftime("%Y-%m-%d %H:%M:%S")
                    
                    # 更新Redis
                    r.hset(redis_key, mapping={
                        'expiresAt': expire_timestamp,
                        'expiresDate': expire_date_str
                    })
                    
                    updated_count += 1
                    logging.info(f"Updated Redis {redis_key}: expiresDate={expire_date_str}")
        
        logging.info(f"Updated {updated_count} {tier} products in Redis")
        return updated_count
        
    except Exception as e:
        logging.error(f"Error updating Redis for {tier}: {e}")
        return 0

def update_client_keys_in_redis():
    """更新Redis中client_keys的过期时间"""
    try:
        r = redis.Redis(host='localhost', port=REDIS_PORT, decode_responses=True)
        
        # 读取所有产品文件获取soldAt和status信息
        all_products = {}
        tier_map = {}  # 记录每个key属于哪个tier
        for tier in ['trial', 'medium', 'high', 'supreme']:
            file_path = os.path.join(PRODUCT_DIR, f'{tier}.json')
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    products = json.load(f)
                    all_products.update(products)
                    # 记录每个key的tier
                    for key in products:
                        tier_map[key] = tier
        
        # 获取所有client_keys
        pattern = "client_keys:*"
        client_keys = r.keys(pattern)
        
        updated_count = 0
        
        for redis_key in client_keys:
            # 从redis key中提取实际的key
            actual_key = redis_key.replace('client_keys:', '')
            
            # 查找对应的产品信息
            if actual_key in all_products:
                product = all_products[actual_key]
                sold_at_value = product.get('soldAt')
                
                # 如果soldAt为None（JSON的null），跳过不处理，保持原样
                if sold_at_value is None:
                    # 不做任何修改，保持现有状态
                    continue
                    
                # 只处理有有效soldAt时间的已售出产品
                if product.get('status') == 'sold' and sold_at_value:
                    sold_at = parse_sold_at(sold_at_value)
                    
                    if sold_at:
                        # 计算过期时间（根据tier决定天数）
                        tier = tier_map.get(actual_key, 'medium')  # 默认为medium
                        days_to_add = 1 if tier == 'trial' else 30
                        expire_dt = sold_at + timedelta(days=days_to_add)
                        expire_timestamp = int(expire_dt.timestamp() * 1000)
                        expire_date_str = expire_dt.astimezone(BEIJING_TZ).strftime("%Y-%m-%d %H:%M:%S")
                        
                        # 更新Redis中的expires_at和expires_date字段
                        r.hset(redis_key, mapping={
                            'expires_at': str(expire_timestamp),
                            'expires_date': expire_date_str
                        })
                        
                        updated_count += 1
                        logging.info(f"Updated Redis {redis_key}: expires_at={expire_timestamp}, expires_date={expire_date_str}")
        
        logging.info(f"Updated {updated_count} client keys in Redis")
        return updated_count
        
    except Exception as e:
        logging.error(f"Error updating client keys in Redis: {e}")
        return 0

def main():
    """主函数"""
    logging.info("="*60)
    logging.info("Starting expire date update task")
    logging.info(f"Current time: {datetime.now(BEIJING_TZ).strftime('%Y-%m-%d %H:%M:%S')} (Beijing)")
    
    total_updated = 0
    
    # 更新各级别产品文件（Trial使用1天，其他使用30天）
    for tier in ['trial', 'medium', 'high', 'supreme']:
        file_path = os.path.join(PRODUCT_DIR, f'{tier}.json')
        if os.path.exists(file_path):
            count = update_product_file(file_path, tier)
            total_updated += count
            
            # 同步更新Redis
            redis_count = update_redis_products(tier)
            logging.info(f"Synced {redis_count} {tier} products to Redis")
    
    # 更新Redis中的client_keys TTL
    client_keys_count = update_client_keys_in_redis()
    
    logging.info(f"Task completed. Total updated: {total_updated} products, {client_keys_count} client keys")
    logging.info("="*60)

if __name__ == "__main__":
    main()